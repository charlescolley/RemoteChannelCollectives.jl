struct powot_batch_prefix_scan_comm{T} <: Communication
    init_receiving_from::Union{Nothing,RemoteChannel{Channel{T}}}
    sending_to_end::Union{Nothing,RemoteChannel{Channel{T}}}
    batch_broadcast::Union{Nothing,broadcast_comm{T}}
end 

struct prefix_scan_comm{T} <: Communication
    sending_to_phase1::Union{Nothing,RemoteChannel{Channel{T}}}
    receiving_from_phase1::Vector{RemoteChannel{Channel{T}}}
    sending_to_phase2::Vector{RemoteChannel{Channel{T}}}
    receiving_from_phase2::Vector{RemoteChannel{Channel{T}}}
    zero_out_buffer::Bool
    batch_reduction::Union{Nothing,powot_batch_prefix_scan_comm{T}}
end 


#
#   Communication Setup
#

"""
    prefix_scan_communication(pids, channel_type::T)

Set up the channels to facilitate a prefix scan between pids. Returned vector of 
prefix_scan_comm can be elementwise passed to spawned processors and is used with 
prefix_scan(_,_::prefix_scan_comm{T}).

See also [`prefix_scan`](@ref)
"""
function prefix_scan_communication(pids, channel_type::T) where T

    sending_to_p1 = Vector{Union{Nothing,RemoteChannel{Channel{T}}}}(undef,length(pids))
    receiving_from_p1 = Vector{Vector{RemoteChannel{Channel{T}}}}(undef,length(pids))
    
    sending_to_p2 = Vector{Vector{RemoteChannel{Channel{T}}}}(undef,length(pids))
    receiving_from_p2 = Vector{Vector{RemoteChannel{Channel{T}}}}(undef,length(pids))


    PowOT_batches = PowOT_process_breakdown(pids)
    batch_offset = 0 
    p = 1
    for batch in PowOT_batches
        for _ in batch 

            receiving_from_p1[p] = Vector{RemoteChannel{Channel{T}}}(undef,0)
            sending_to_p2[p] = Vector{RemoteChannel{Channel{T}}}(undef,0)
            receiving_from_p2[p] = Vector{RemoteChannel{Channel{T}}}(undef,0)
            p += 1
        end 
        prefix_scan_communication_PowOT!(batch,batch_offset,
                                            receiving_from_p1,sending_to_p1,
                                            sending_to_p2, receiving_from_p2,
                                            channel_type)
        sending_to_p1[p-1] = nothing
        batch_offset += length(batch)
    end 


    reset_buffer_q = Vector{Bool}(undef,length(pids))
    fill!(reset_buffer_q,false)
    powot_batch_reduction = Vector{Union{Nothing,powot_batch_prefix_scan_comm{T}}}(nothing,length(pids))

    if length(PowOT_batches) > 1 
        powot_batch_reduction = batch_prefix_scan_communication(PowOT_batches,channel_type)
        batch_offset = 0 
        for batch in PowOT_batches
            batch_offset += length(batch)
            reset_buffer_q[batch_offset] = true 
        end 
    else
        reset_buffer_q[end] = true 
    end 


    communication_instructions = Vector{prefix_scan_comm{T}}(undef,length(pids))
    for p =1:length(pids)
        communication_instructions[p] = prefix_scan_comm(
            sending_to_p1[p],
            receiving_from_p1[p], 
            sending_to_p2[p],
            receiving_from_p2[p],
            reset_buffer_q[p],
            powot_batch_reduction[p],
        )
    end 

    return communication_instructions
end

function prefix_scan_communication_PowOT!(pids, batch_offset, 
                                             receiving_from_p1, sending_to_p1,
                                             sending_to_p2, receiving_from_p2,
                                             channel_type::T) where T 
    max_depth = Int(round(log2(length(pids))))

    offset = 1
    for l=1:max_depth

        for p = length(pids):-offset:1
            partner_p = ((p - 1) ⊻ offset) + 1             
            if p > partner_p # handle partner's channel too
                channel = RemoteChannel(()->Channel{T}(1),pids[partner_p]) #TODO: provide variable for channel ownership? 
                sending_to_p1[partner_p + batch_offset] = channel
                push!(receiving_from_p1[p + batch_offset],channel)
            end 
        end    
        offset *= 2 
    end 



    for l=max_depth:-1:1
        offset = Int(offset/2)


        for p = length(pids):-offset:1
            partner_p = ((p - 1) ⊻ offset) + 1 

            if p > partner_p # handle partner's channel too
                channel1 = RemoteChannel(()->Channel{T}(1),pids[partner_p]) #TODO: provide variable for channel ownership? 
                channel2 = RemoteChannel(()->Channel{T}(1),pids[p])
                
                push!(sending_to_p2[p + batch_offset],channel1)
                push!(receiving_from_p2[partner_p + batch_offset],channel1)

                push!(receiving_from_p2[p + batch_offset],channel2)
                push!(sending_to_p2[partner_p + batch_offset],channel2)
            end 

        end    
        
    end 

end 

"""
    batch_prefix_scan_communication(PowOT_batches,_::T)

Create the RemoteChannel communication to sequentially update each prefix_scan batch.
Arrays for needed type components are allocated in this function, please see '!' 
version if arrays are pre-allocated. 

See also [`batch_prefix_scan_communication!`](@ref)
"""
function batch_prefix_scan_communication(PowOT_batches,channel_type::T) where T
    

    num_procs = sum([length(batch) for batch in PowOT_batches])

    init_receiving_from = Vector{Union{Nothing,RemoteChannel{Channel{T}}}}(nothing, num_procs)
    sending_to_end = Vector{Union{Nothing,RemoteChannel{Channel{T}}}}(nothing, num_procs)
    batch_broadcast = Vector{Union{Nothing,broadcast_comm{T}}}(nothing,num_procs)
    powot_batch_reduction = Vector{Union{Nothing,powot_batch_prefix_scan_comm}}(nothing,num_procs)

    batch_prefix_scan_communication!(PowOT_batches,init_receiving_from, sending_to_end, batch_broadcast,channel_type)

    for p = 1:num_procs
        powot_batch_reduction[p] = powot_batch_prefix_scan_comm{T}(
            init_receiving_from[p],
            sending_to_end[p],
            batch_broadcast[p],
        )
    end 
    return powot_batch_reduction
end

"""
    batch_prefix_scan_communication(PowOT_batches,_::T)

Update the input arrays with the channels needed to reduce the PowOT batches. 

See also [`batch_prefix_scan_communication`](@ref)
"""
function batch_prefix_scan_communication!(PowOT_batches,
                                         init_receiving_from::Vector{Union{Nothing,RemoteChannel{Channel{T}}}},
                                         sending_to_end::Vector{Union{Nothing,RemoteChannel{Channel{T}}}},
                                         batch_broadcast::Vector{Union{Nothing,broadcast_comm{T}}},
                                         channel_type::T) where T

    batch_offset = 0
    for i =1:length(PowOT_batches)# enumerate(PowOT_batches)
        batch = PowOT_batches[i]

        if i != 1 # first batch doesn't need to be updated. 
            if length(batch) > 1 
                bcast_communication = broadcast_communication(batch,length(batch),channel_type)
                for p in 1:length(batch) 
                    batch_broadcast[batch_offset + p] = bcast_communication[p]
                end 
            end
        end 
        batch_offset += length(batch)

        if i == 1
            end_channel = RemoteChannel(()->Channel{T}(1),PowOT_batches[i+1][end])
            sending_to_end[batch_offset] = end_channel
        elseif i == length(PowOT_batches)
            init_receiving_from[batch_offset] = sending_to_end[batch_offset-length(batch)]    
        else
            init_receiving_from[batch_offset] = sending_to_end[batch_offset-length(batch)] 

            end_channel = RemoteChannel(()->Channel{T}(1),PowOT_batches[i+1][end])
            sending_to_end[batch_offset] = end_channel
        end
    end
    
end

#
#   Proc level drivers 
#

"""
See also [`prefix_scan_communication`](@ref)
"""
function prefix_scan(scan_f, identity_f, my_data, communication::prefix_scan_comm{T}) where T 


    my_buffer = copy(my_data)

    #  -- perform the Reduction --  # 

    for channel in communication.receiving_from_phase1
        their_data = take!(channel)
        my_buffer = scan_f(my_buffer,their_data)
    end 

 
    if communication.sending_to_phase1 !== nothing 
        put!(communication.sending_to_phase1,my_buffer)
    end

    #  -- perform the downsweep --  # 

    reduction_result = copy(my_buffer)

    if communication.zero_out_buffer
        my_buffer = copy(identity_f)
        replace_my_buffer = false
    else 
        replace_my_buffer = true
    end



    for (send_channel,take_channel) in zip(communication.sending_to_phase2,communication.receiving_from_phase2)

        if replace_my_buffer
            their_buffer = take!(take_channel)
            put!(send_channel,my_buffer)

            my_buffer = their_buffer
            replace_my_buffer = false 
        else 

            put!(send_channel,my_buffer)
            their_buffer = take!(take_channel)
            my_buffer = scan_f(my_buffer,their_buffer)
        end
    end 



    if communication.batch_reduction !== nothing 
        my_buffer = batch_prefix_scan(scan_f, my_buffer, reduction_result, communication.batch_reduction)
    end 

    return my_buffer
end 

function batch_prefix_scan(scan_f, my_data,cumulative_buffer,communication::powot_batch_prefix_scan_comm{T}) where T

    if communication.init_receiving_from !== nothing || communication.sending_to_end !== nothing
        # batch header nodes
        if communication.init_receiving_from === nothing && communication.sending_to_end !== nothing
            # start node 
            put!(communication.sending_to_end,cumulative_buffer)
            return my_data
        elseif communication.init_receiving_from !== nothing && communication.sending_to_end === nothing
            # end node 
            their_cumulative_buffer = take!(communication.init_receiving_from)
            if communication.batch_broadcast !== nothing 
                broadcast(their_cumulative_buffer,communication.batch_broadcast)
            end  # last batch may just be a single node, 
            return scan_f(my_data,their_cumulative_buffer)
        else 
            their_cumulative_buffer = take!(communication.init_receiving_from)
            put!(communication.sending_to_end,scan_f(cumulative_buffer,their_cumulative_buffer))
            
            broadcast(their_cumulative_buffer,communication.batch_broadcast)
            return scan_f(my_data,their_cumulative_buffer)
        end 
    else 
        if communication.batch_broadcast !== nothing 
            their_data = broadcast(nothing,communication.batch_broadcast)
            return scan_f(my_data,their_data)
        else   # part of first batch doesn't need to be updated, nothing to the left
            return my_data
        end 
    end 

end 

#  -- Profiling Code --  # 

function prefix_scan_profiled(data_seed::seeded_data,communication::prefix_scan_comm{T}) where T

    seed!(data_seed.seed)
    data_gen_start_t = time_ns()
    my_data = rand(Float64,data_seed.n,data_seed.n) 
    identity_f = zeros(Float64,data_seed.n,data_seed.n)
    scan_f = (X,Y)-> X# making scan_f minimal to focus on measuring communication.
    data_gen_t = Float64(time_ns() - data_gen_start_t)*1e-9

    return prefix_scan_profiled(scan_f, identity_f, my_data, communication)..., data_gen_t 
end

function prefix_scan_profiled(scan_f, identity_f, my_data, communication::prefix_scan_comm{T}) where T

    alloc_start_t = time_ns()

    #count and pre-allocate the space needed to store the timings 

    #  -- PowOT Scan --  #
    L1 = length(communication.receiving_from_phase1)
    I1 = communication.sending_to_phase1 !== nothing ? 1 : 0 
    L2 = min(length(communication.sending_to_phase2),length(communication.receiving_from_phase2))


    takes = L1 + L2 
    scans = L1 + L2 
    puts = I1 + L2
    if !communication.zero_out_buffer
        scans -= 1
    end

    #  -- Batch Scan --  #
    if communication.batch_reduction !== nothing 
        if communication.batch_reduction.init_receiving_from !== nothing 
            takes += 1 
            if communication.batch_reduction.sending_to_end === nothing
                scans += 1
            end
        end 

        if communication.batch_reduction.sending_to_end !== nothing 
            puts += 1 
        end 

        if communication.batch_reduction.batch_broadcast !== nothing
            puts += length(communication.batch_reduction.batch_broadcast.sending_to)
            takes += communication.batch_reduction.batch_broadcast.receiving_from !== nothing ? 1 : 0
        end

        if communication.batch_reduction.batch_broadcast !== nothing
            scans += 1 
        end 
    end 


    scan_timings = zeros(Float64,scans)
    put_timings = zeros(Float64,puts)
    take_timings =  zeros(Float64,takes)

    alloc_t = Float64(time_ns() - alloc_start_t)*1e-9

    return prefix_scan_profiled!(scan_f,identity_f, my_data,put_timings,take_timings,scan_timings,communication)..., alloc_t

end


function prefix_scan_profiled!(scan_f, identity_f, my_data, put_timings, take_timings, scan_timings, communication::prefix_scan_comm{T}) where T 

    start_time = time_ns()

    put_idx = 1 
    take_idx = 1
    scan_idx = 1 

    my_buffer = copy(my_data)

    #  -- perform the Reduction --  # 

    for channel in communication.receiving_from_phase1
        take_start_t = time_ns()
        their_data = take!(channel)
        take_timings[take_idx] = Float64(time_ns() - take_start_t)*1e-9
        take_idx += 1

        scan_start_t = time_ns()
        my_buffer = scan_f(my_buffer,their_data)
        scan_timings[scan_idx] = Float64(time_ns() - scan_start_t)*1e-9
        scan_idx += 1
    end 

 
    if communication.sending_to_phase1 !== nothing 
        put_start_t = time_ns()
        put!(communication.sending_to_phase1,my_buffer)
        put_timings[put_idx] = Float64(time_ns() - put_start_t)*1e-9
        put_idx += 1
    end

    #  -- perform the downsweep --  # 

    reduction_result = copy(my_buffer)
    if communication.zero_out_buffer
        my_buffer = copy(identity_f)
        replace_my_buffer = false
    else 
        replace_my_buffer = true
    end


    for (send_channel,take_channel) in zip(communication.sending_to_phase2,communication.receiving_from_phase2)

        if replace_my_buffer
            take_start_t = time_ns()
            their_buffer = take!(take_channel)
            take_timings[take_idx] = Float64(time_ns() - take_start_t)*1e-9
            take_idx += 1

            put_start_t = time_ns()
            put!(send_channel,my_buffer)
            put_timings[put_idx] = Float64(time_ns() - put_start_t)*1e-9
            put_idx += 1

            my_buffer = their_buffer
            replace_my_buffer = false 
        else 


            put_start_t = time_ns()
            put!(send_channel,my_buffer)
            put_timings[put_idx] = Float64(time_ns() - put_start_t)*1e-9
            put_idx += 1

            take_start_t = time_ns()
            their_buffer = take!(take_channel)
            take_timings[take_idx] = Float64(time_ns() - take_start_t)*1e-9
            take_idx += 1


            scan_start_t = time_ns()
            my_buffer = scan_f(my_buffer,their_buffer)
            scan_timings[scan_idx] = Float64(time_ns() - scan_start_t)*1e-9
            scan_idx += 1
        end
    end 



    if communication.batch_reduction !== nothing 
        my_buffer = batch_prefix_scan_profiled!(scan_f, my_buffer, reduction_result,put_timings,put_idx,take_timings,take_idx, scan_timings,scan_idx, communication.batch_reduction)
    end 

    internal_time =  Float64(time_ns() - start_time)*1e-9

    return my_buffer, internal_time, put_timings, take_timings, scan_timings
end 


function batch_prefix_scan_profiled!(scan_f, my_data,cumulative_buffer,put_timings,put_idx,take_timings,take_idx, scan_timings,scan_idx,communication::powot_batch_prefix_scan_comm{T}) where T



    if communication.init_receiving_from !== nothing || communication.sending_to_end !== nothing
        # batch header nodes
        if communication.init_receiving_from === nothing && communication.sending_to_end !== nothing
            # start node 
            put_start_t = time_ns()
            put!(communication.sending_to_end,cumulative_buffer)
            put_timings[put_idx] = Float64(time_ns() - put_start_t)*1e-9
            put_idx += 1
            return my_data
        elseif communication.init_receiving_from !== nothing && communication.sending_to_end === nothing
            # end node 
            take_start_t = time_ns()
            their_cumulative_buffer = take!(communication.init_receiving_from)
            take_timings[take_idx] = Float64(time_ns() - take_start_t)*1e-9
            take_idx += 1

            if communication.batch_broadcast !== nothing 
                _,_,_,take_time = broadcast_profiled!(their_cumulative_buffer,
                                                        communication.batch_broadcast,
                                                        put_timings,put_idx-1)
                if take_time != 0.0
                    take_timings[take_idx] = take_time
                    take_idx += 1
                end 
            end  # last batch may just be a single node, 

            scan_start_t = time_ns()
            scan_output = scan_f(my_data,their_cumulative_buffer)
            scan_timings[scan_idx] = Float64(time_ns() - scan_start_t)*1e-9
            scan_idx += 1
            return scan_output
        else 
            take_start_t = time_ns()
            their_cumulative_buffer = take!(communication.init_receiving_from)
            take_timings[take_idx] = Float64(time_ns() - take_start_t)*1e-9
            take_idx += 1
            
            put_start_t = time_ns()
            put!(communication.sending_to_end,scan_f(cumulative_buffer,their_cumulative_buffer))
            put_timings[put_idx] = Float64(time_ns() - put_start_t)*1e-9
            put_idx += 1

            _,_,_,take_time = broadcast_profiled!(their_cumulative_buffer,
                                                        communication.batch_broadcast,
                                                        put_timings,put_idx-1)
            if take_time != 0.0
                take_timings[take_idx] = take_time
                take_idx += 1
            end 

            scan_start_t = time_ns()
            scan_output = scan_f(my_data,their_cumulative_buffer)
            scan_timings[scan_idx] = Float64(time_ns() - scan_start_t)*1e-9
            scan_idx += 1
            return scan_output
        end 
    else 
        if communication.batch_broadcast !== nothing 
            their_data,_,_,take_time = broadcast_profiled!(nothing,
                                                    communication.batch_broadcast,
                                                    put_timings,put_idx-1)
            if take_time != 0.0
                take_timings[take_idx] = take_time
                take_idx += 1
            end 

            scan_start_t = time_ns()
            scan_output = scan_f(my_data,their_data)
            scan_timings[scan_idx] = Float64(time_ns() - scan_start_t)*1e-9
            scan_idx += 1
            return scan_output
        else   # part of first batch doesn't need to be updated, nothing to the left
            return my_data 
        end 
    end 

end 
