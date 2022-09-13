struct gather_comm{T} <: Communication
    receiving_from::Vector{RemoteChannel{Channel{Vector{T}}}}
    sending_to::Union{Nothing,RemoteChannel{Channel{Vector{T}}}}
end

function gather_communication(pids,gather_pididx,channel_type::T) where T 

    if gather_pididx != 1 
        temp = pids[1]
        pids[1] = pids[gather_pididx]
        pids[gather_pididx] = temp
    end

    #initialize memory
    #channels = Vector{RemoteChannel{Channel{Vector{T}}}}(undef,0)

    sending_to = Vector{Union{Nothing,RemoteChannel{Channel{Vector{T}}}}}(undef,length(pids))
    receiving_from = Vector{Vector{RemoteChannel{Channel{Vector{T}}}}}(undef,length(pids))
    for p in 1:length(pids)
        sending_to[p] = nothing 
        receiving_from[p] = Vector{RemoteChannel{Channel{Vector{T}}}}(undef,0)
    end

    gather_communication!(pids, sending_to, receiving_from, channel_type)

    communication = Vector{gather_comm{T}}(undef,length(pids))

    for p = 1:length(pids)
        communication[p] = gather_comm(receiving_from[p],sending_to[p])
    end 

    return communication
end

function gather_communication!(pids, sending_to, receiving_from, channel_type::T) where T 


    PowOT_batches = PowOT_process_breakdown(pids)

    #gather the results from the first nodes in the Power of Two batches
    if length(PowOT_batches) > 1

        batch_offset = length(pids) + 1

        for i = length(PowOT_batches):-1:2
            batch_offset -= length(PowOT_batches[i])
            channel = RemoteChannel(()->Channel{Vector{T}}(1),PowOT_batches[i][1])
            
            push!(receiving_from[1],channel)
            sending_to[batch_offset] = channel

        end
    end


    batch_offset = length(pids) 
    
    for batch in reverse(PowOT_batches)
        batch_offset -= length(batch)

        gather_PowOT_communication!(batch,batch_offset, 
                                    sending_to, receiving_from,
                                    channel_type)
        
    end


end

function gather_PowOT_communication!(pids, batch_offset, sending_to,receiving_from,channel_type::T) where T
    #accumulates on pids[1]

    max_depth = Int(round(log2(length(pids))))
    pididx = findfirst(isequal(myid()), pids)


    #
    #    Coordinate communication
    #
  
    sending_to_idx = zeros(Int,2^max_depth)

    receiving = [1]

    for l=1:max_depth

        offset = Int(floor(2^(max_depth-l)))

        new_to_receive = []
        for pididx in receiving
            #sendto
            channel = RemoteChannel(()->Channel{Vector{T}}(1),pids[pididx + offset])
                                                        #channels should exist on sending nodes
            #push!(channels,RemoteChannel(()->Channel{Matrix{Float64}}(1),pids[pididx]))

            if sending_to_idx[pididx+offset] == 0
                sending_to_idx[pididx+offset] = pididx
                sending_to[batch_offset + pididx+offset] = channel 
            end
            
            push!(receiving_from[batch_offset + pididx],channel)
            push!(new_to_receive,pididx + offset)

        end 

        append!(receiving,new_to_receive)
        
    end 

end


function gather(my_data::T,communication::C) where {T,C <: gather_comm}

    all_data = Vector{T}(undef,1)
    all_data[1] = my_data

    for channel in reverse(communication.receiving_from)
                   # communication patterns come from the inverse of the broadcast code, 
                   # so receiving channels need to be reverse.  
                   # TODO: may be good to reconsider this version

        their_data = take!(channel)

        append!(all_data,their_data)
    end

    if communication.sending_to !== nothing 
        put!(communication.sending_to,all_data)
    end
    return all_data

end


function gather_profiled(data_seed::seeded_data,communication::C) where {C <: gather_comm}

    seed!(data_seed.seed)
    data_gen_start_t = time_ns()
    data = rand(Float64,data_seed.n,data_seed.n) 
    data_gen_t = Float64(time_ns() - data_gen_start_t)*1e-9

    return gather_profiled(data,communication)..., data_gen_t
end

function gather_profiled(my_data,communication::C) where {C <: gather_comm}

    alloc_start_time = time_ns()
    all_data = Vector{Matrix{Float64}}(undef,1)
    take_timings = Vector{Float64}(undef,length(communication.receiving_from))
    all_data[1] = my_data
    alloc_t = Float64(time_ns() - alloc_start_time)*1e-9

    return gather_profiled!(my_data,all_data,take_timings,communication)..., alloc_t

end

function gather_profiled!(my_data,all_data,take_timings,communication::C) where {C <: gather_comm}

    #all_data = Vector{Matrix{Float64}}(undef,1)
    #TODO: make comm type take buffer length
    #take_timings = Vector{Float64}(undef,length(communication.receiving_from))
    start_time = time_ns()
    all_data[1] = my_data
    for (i,channel) in enumerate(reverse(communication.receiving_from))
                   # communication patterns come from the inverse of the broadcast code, 
                   # so receiving channels need to be reverse.  
                   # TODO: may be good to reconsider this version
        take_start_time = time_ns()
        their_data = take!(channel)
        take_timings[i] = Float64(time_ns() - take_start_time)*1e-9

        append!(all_data,their_data)
    end

    if communication.sending_to !== nothing 
        put_start_time = time_ns()
        put!(communication.sending_to,all_data)
        put_time = Float64(time_ns() - put_start_time)*1e-9
    else 
        put_time = 0.0
    end

    internal_time = Float64(time_ns() - start_time)*1e-9
    return all_data, internal_time, put_time, take_timings

end