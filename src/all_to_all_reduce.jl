struct all_to_all_reduce_comm{T} <: Communication
    all_reduce_receiving_from::Vector{RemoteChannel{Channel{T}}}
    all_reduce_sending_to::Vector{RemoteChannel{Channel{T}}}

    batch_reduce_receiving_from::Union{Nothing,Vector{RemoteChannel{Channel{T}}}}
    batch_reduce_sending_to::Union{Nothing,RemoteChannel{Channel{T}}}
    
    bcast_receiving_from::Union{Nothing,RemoteChannel{Channel{T}}}
    bcast_sending_to::Vector{RemoteChannel{Channel{T}}}
    
end 




function all_to_all_reduction_communication_PowOT!(pids,batch_offset,sending_to,receiving_from,channel_type::T) where T 

    
    max_depth = Int(round(log2(length(pids))))

    offset = 1
    for l=1:max_depth
        for p=1:length(pids)

            channel1 = RemoteChannel(()->Channel{T}(1),pids[((p - 1) ⊻ offset) + 1 ])
            channel2 = RemoteChannel(()->Channel{T}(1),pids[p])
            
            sending_to[p + batch_offset][l] = channel1
            receiving_from[((p - 1) ⊻ offset) + 1 + batch_offset][l] = channel1

            sending_to[((p - 1) ⊻ offset) + 1 + batch_offset][l] = channel2
            receiving_from[p + batch_offset][l] = channel2

        end
        offset *= 2 
    end 

end

function all_to_all_reduction_communication(pids, channel_type::T) where T

    
    all_reduce_receiving_from = Vector{Vector{RemoteChannel{Channel{T}}}}(undef,length(pids))
    all_reduce_sending_to = Vector{Vector{RemoteChannel{Channel{T}}}}(undef,length(pids))


    batch_reduce_receiving_from = Vector{Union{Nothing,Vector{RemoteChannel{Channel{T}}}}}(undef,length(pids))
    batch_reduce_sending_to = Vector{Union{Nothing,RemoteChannel{Channel{T}}}}(undef,length(pids))

    bcast_receiving_from = Vector{Union{Nothing,RemoteChannel{Channel{T}}}}(undef,length(pids))
    bcast_sending_to = Vector{Vector{RemoteChannel{Channel{T}}}}(undef,length(pids))
    
    for p in 1:length(pids)
        batch_reduce_receiving_from[p] = nothing
        batch_reduce_sending_to[p] = nothing
        bcast_receiving_from[p] = nothing

        bcast_sending_to[p] = Vector{RemoteChannel{Channel{T}}}(undef,0)
    end


    PowOT_batches = PowOT_process_breakdown(pids)



    #batch_offset = length(PowOT_batches[1]) + 1
    batch_offset = 0 
    # each batch runs PowOT all-to-all reduction 
    p = 1
    for batch in PowOT_batches

        max_depth = Int(round(log2(length(batch))))
        for _ in batch 
            all_reduce_receiving_from[p] = Vector{RemoteChannel{Channel{T}}}(undef,max_depth)
            all_reduce_sending_to[p] = Vector{RemoteChannel{Channel{T}}}(undef,max_depth)
            p += 1
        end 

        all_to_all_reduction_communication_PowOT!(batch,batch_offset,
                                                  all_reduce_sending_to,all_reduce_receiving_from,
                                                  channel_type::T)
        batch_offset += length(batch)
    end 


    if length(PowOT_batches) > 1 
        # reduce across batch leads 

        batch_reduce_receiving_from[1] = Vector{RemoteChannel{Channel{T}}}(undef,length(PowOT_batches)-1)

        batch_offset = length(PowOT_batches[1]) + 1
        for i = 1:(length(PowOT_batches)-1)
            channel = RemoteChannel(()->Channel{T}(1),PowOT_batches[i][1])
            batch_reduce_sending_to[batch_offset] = channel
            batch_reduce_receiving_from[1][i] = channel
            batch_offset += length(PowOT_batches[i+1])
        end 

        broadcast_communication!(pids,bcast_receiving_from, bcast_sending_to, channel_type::T)
    end 

    #convert communication to types 
    communication_instructions = Vector{all_to_all_reduce_comm{T}}(undef,length(pids))
    for p =1:length(pids)
        communication_instructions[p] = all_to_all_reduce_comm(
            all_reduce_receiving_from[p],
            all_reduce_sending_to[p], 
            batch_reduce_receiving_from[p], 
            batch_reduce_sending_to[p], 
            bcast_receiving_from[p], 
            bcast_sending_to[p]
        )
    end 

    return communication_instructions
    
end 

function all_to_all_reduce(reduction_f,my_data,communication::all_to_all_reduce_comm{T}) where T

    for (send_channel,take_channel) in zip(communication.all_reduce_sending_to,communication.all_reduce_receiving_from)
    #TODO:                                               change this to just sending_to, check other 
        put!(send_channel,my_data)
        their_data =  take!(take_channel)
        my_data = reduction_f(my_data,their_data)
    end 

    if communication.batch_reduce_receiving_from !== nothing 
        for channel in communication.batch_reduce_receiving_from
            their_data = take!(channel)
            my_data = reduction_f(my_data,their_data)
        end 
    end 

    if communication.batch_reduce_sending_to !== nothing 
        put!(communication.batch_reduce_sending_to,my_data)
    end 



    if communication.bcast_receiving_from !== nothing 
        my_data = take!(communication.bcast_receiving_from)
    end 

    for channel in communication.bcast_sending_to
        put!(channel,my_data)
    end

    return my_data
end 

function all_to_all_reduce_profiled(data_seed::seeded_data,communication::all_to_all_reduce_comm{T}) where T

    seed!(data_seed.seed)
    data_gen_start_t = time_ns()
    my_data = rand(Float64,data_seed.n,data_seed.n) 
    reduction_f = (X,Y)-> X# making reduction_f minimal to focus on measuring communication.
    data_gen_t = Float64(time_ns() - data_gen_start_t)*1e-9

    return all_to_all_reduce_profiled(reduction_f,my_data,communication)..., data_gen_t
end 

function all_to_all_reduce_profiled(reduction_f,my_data,communication::all_to_all_reduce_comm{T}) where T

    alloc_start_t = time_ns()
    #loop_i
    L1 = min(length(communication.all_reduce_sending_to),length(communication.all_reduce_receiving_from))
    L2 = communication.batch_reduce_receiving_from !== nothing ?  length(communication.batch_reduce_receiving_from) : 0 
    I1 = communication.batch_reduce_sending_to !== nothing ? 1 : 0  
    I2 = communication.bcast_receiving_from !== nothing ? 1 : 0
    I3 = communication.bcast_sending_to !== nothing ? length(communication.bcast_sending_to) : 0
    #If_i 

    reduction_timings = zeros(Float64,L1 + L2)
    put_timings = zeros(Float64,L1 + I1 + I3)
    take_timings =  zeros(Float64,L1+ L2 + I2)

    alloc_t = Float64(time_ns() - alloc_start_t)*1e-9


    return all_to_all_reduce_profiled!(reduction_f,my_data,put_timings,take_timings,reduction_timings,communication)..., alloc_t

end

function all_to_all_reduce_profiled!(reduction_f,my_data,put_timings,take_timings,reduction_timings,communication::all_to_all_reduce_comm{T}) where T

    internal_start_t = time_ns()

    take_idx = 1
    put_idx = 1
    reduction_idx = 1

    for (send_channel,take_channel) in zip(communication.all_reduce_sending_to,communication.all_reduce_receiving_from)

        put_start_t = time_ns()
        put!(send_channel,my_data)
        put_timings[put_idx] = Float64(time_ns() - put_start_t)*1e-9
        put_idx += 1

        take_start_t = time_ns()
        their_data = take!(take_channel)
        take_timings[take_idx] = Float64(time_ns() - take_start_t)*1e-9
        take_idx += 1

        reduction_start_t = time_ns()
        my_data = reduction_f(my_data,their_data)
        reduction_timings[reduction_idx] = Float64(time_ns() - reduction_start_t)*1e-9
        reduction_idx += 1
    end 

    if communication.batch_reduce_receiving_from !== nothing 
        for channel in communication.batch_reduce_receiving_from
            take_start_t = time_ns()
            their_data = take!(channel)
            take_timings[take_idx] = Float64(time_ns() - take_start_t)*1e-9
            take_idx += 1

            reduction_start_t = time_ns()
            my_data = reduction_f(my_data,their_data)
            reduction_timings[reduction_idx] = Float64(time_ns() - reduction_start_t)*1e-9
            reduction_idx += 1
        end 
    end 

    if communication.batch_reduce_sending_to !== nothing 
        put_start_t = time_ns()
        put!(communication.batch_reduce_sending_to,my_data)
        put_timings[put_idx] = Float64(time_ns() - put_start_t)*1e-9
        put_idx += 1
    end 

    if communication.bcast_receiving_from !== nothing 
        take_start_t = time_ns()
        my_data = take!(communication.bcast_receiving_from)
        take_timings[take_idx] = Float64(time_ns() - take_start_t)*1e-9
        take_idx += 1
    end 

    for channel in communication.bcast_sending_to
        put_start_t = time_ns()
        put!(channel,my_data)
        put_timings[put_idx] = Float64(time_ns() - put_start_t)*1e-9
        put_idx += 1
    end

    internal_timing = Float64(time_ns() - internal_start_t)*1e-9
    return my_data,  internal_timing, put_timings, take_timings, reduction_timings
end 