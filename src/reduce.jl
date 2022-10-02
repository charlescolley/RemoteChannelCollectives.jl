struct reduce_comm{T} <: Communication
    receiving_from::Vector{RemoteChannel{Channel{T}}}
    sending_to::Union{Nothing,RemoteChannel{Channel{T}}}
end 

"""
    reduce_communication(pids,reduce_pididx,_::T)

  Create the RemoteChannels of type T needed to facilitate a reduce operation
over the pids passed in, collecting to the process with the id, reduce_pididx. 
"""
function reduce_communication(pids,reduce_pididx,channel_type::T) where T 

    pid_indices = collect(1:length(pids))
    if reduce_pididx != 1 
        temp = copy(pid_indices[1])
        pid_indices[1] = pid_indices[reduce_pididx]
        pid_indices[reduce_pididx] = temp

        temp = copy(pids[1])
        pids[1] = pids[reduce_pididx]
        pids[reduce_pididx] = temp
    end

    #initialize memory

    sending_to = Vector{Union{Nothing,RemoteChannel{Channel{T}}}}(undef,length(pids))
    receiving_from = Vector{Vector{RemoteChannel{Channel{T}}}}(undef,length(pids))
    for p in 1:length(pids)
        sending_to[p] = nothing 
        receiving_from[p] = Vector{RemoteChannel{Channel{T}}}(undef,0)
    end

    reduce_communication!(pids, sending_to, receiving_from, channel_type)

    communication = Vector{reduce_comm{T}}(undef,length(pids))

    for p = 1:length(pids)
        communication[p] = reduce_comm(
            receiving_from[pid_indices[p]],
            sending_to[pid_indices[p]]
        )
    end 

    return communication
end

"""
    reduce_communication!(pids,sending_to, receiving_from,reduce_pididx,_::T)

  Update sending_to and receiving_from with the RemoteChannels of type T needed
to facilitate a reduce operation over the pids collecting to the process with 
the id, reduce_pididx. 
"""
function reduce_communication!(pids, sending_to, receiving_from, channel_type::T) where T 


    PowOT_batches = PowOT_process_breakdown(pids)

    #gather the results from the first nodes in the Power of Two batches
    if length(PowOT_batches) > 1

        batch_offset = length(pids) + 1

        for i = length(PowOT_batches):-1:2
            batch_offset -= length(PowOT_batches[i])
            channel = RemoteChannel(()->Channel{T}(1),PowOT_batches[i][1])
            
            push!(receiving_from[1],channel)
            sending_to[batch_offset] = channel

        end
    end


    batch_offset = length(pids) 
    
    for batch in reverse(PowOT_batches)
        batch_offset -= length(batch)

        reduce_PowOT_communication!(batch,batch_offset, 
                                    sending_to, receiving_from,
                                    channel_type)
        
    end


end

"""
    reduce_PowOT_communication!(pids,  batch_offset, sending_to, receiving_from, _::T)
     
Update sending_to and receiving_from starting from the index batch_offset, with
the RemoteChannels of type T needed to facilitate a reduce operation over a batch 
of 2^k pids (for some k).
"""
function reduce_PowOT_communication!(pids, batch_offset, sending_to,receiving_from,channel_type::T) where T
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
            channel = RemoteChannel(()->Channel{T}(1),pids[pididx + offset])
                                                        #channels should exist on sending nodes

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

"""
    reduce(reduction_f,my_data,communication::reduce_comm)
     
Reduce my_data with the reduction_f across all the processors connected by the
RemoteChannels in communication.
"""
function Base.reduce(reduction_f,my_data,communication)
    my_buffer = copy(my_data)
    return reduce!(reduction_f,my_buffer,communication) 
end
   
"""
    reduce!(reduction_f,data,communication::reduce_comm)
     
Reduce data with the reduction_f across all the processors connected by the
RemoteChannels in communication and update data with the result.
"""
function reduce!(reduction_f,data,communication::C) where {C <: reduce_comm}

    for channel in reverse(communication.receiving_from)
                    # communication patterns come from the inverse of the broadcast code, 
                    # so receiving channels need to be reverse.  
                    # TODO: may be good to reconsider this version

        their_data = take!(channel)
        data = reduction_f(data,their_data)
    end

    if communication.sending_to !== nothing 
        put!(communication.sending_to,data)
    end
    return data

end


function reduce_profiled(data_seed::seeded_data, communication::C) where {C <: reduce_comm}
    
    seed!(data_seed.seed)
    data_gen_start_t = time_ns()
    my_data = rand(Float64,data_seed.n,data_seed.n) 
    data_gen_t = Float64(time_ns() - data_gen_start_t)*1e-9
    reduction_f = (X,Y)-> X
    return reduce_profiled(reduction_f, my_data, communication)..., data_gen_t

end

function reduce_profiled(reduction_f, my_data, communication::C) where {C <: reduce_comm}

    alloc_start_time = time_ns()

    my_buffer = copy(my_data)
    take_timings = Vector{Float64}(undef,length(communication.receiving_from))
    reduce_timings = Vector{Float64}(undef,length(communication.receiving_from))
    
    alloc_t = Float64(time_ns() - alloc_start_time)*1e-9
    return reduce_profiled!(reduction_f, my_buffer, take_timings, reduce_timings,communication)..., alloc_t
end 

function reduce_profiled!(reduction_f,data,take_timings,reduce_timings,communication::C) where {C <: reduce_comm}

    start_time = time_ns()

    for (i,channel) in enumerate(reverse(communication.receiving_from))

        take_start_time = time_ns()
        their_data = take!(channel)
        take_timings[i] = Float64(time_ns() - take_start_time)*1e-9

        reduce_start_time = time_ns()
        data = reduction_f(data,their_data)
        reduce_timings[i] = Float64(time_ns() - reduce_start_time)*1e-9
    end


    if communication.sending_to !== nothing 
        put_start_time = time_ns()
        put!(communication.sending_to,data)
        put_time = Float64(time_ns() - put_start_time)*1e-9
    else 
        put_time = 0.0
    end

    internal_time = Float64(time_ns() - start_time)*1e-9
    return data, internal_time, put_time, take_timings, reduce_timings
end