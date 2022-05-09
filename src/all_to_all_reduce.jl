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

        put!(send_channel,my_data)
        their_data =  take!(take_channel)
        my_data = reduction_f(my_data,their_data)
    end 

    #println(batch_reduce_receiving_from, batch_reduce_sending_to, bcast_receiving_from, bcast_sending_to)

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