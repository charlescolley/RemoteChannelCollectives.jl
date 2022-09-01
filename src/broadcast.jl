struct broadcast_comm{T} <: Communication
    receiving_from::Union{Nothing,RemoteChannel{Channel{T}}}
    sending_to::Vector{RemoteChannel{Channel{T}}}
end 


function broadcast_communication(pids,bcast_pididx,channel_type::T) where T

    if bcast_pididx != 1 
        temp = pids[1]
        pids[1] = pids[bcast_pididx]
        pids[bcast_pididx] = temp
    end

    receiving_from = Vector{Union{Nothing,RemoteChannel{Channel{T}}}}(undef,length(pids))
    sending_to = Vector{Vector{RemoteChannel{Channel{T}}}}(undef,length(pids))
    for p in 1:length(pids)
        receiving_from[p] = nothing 
        sending_to[p] = Vector{RemoteChannel{Channel{T}}}(undef,0)
    end

    broadcast_communication!(pids,receiving_from, sending_to, channel_type)

    communication = Vector{broadcast_comm{T}}(undef,length(pids))
    for p =1:length(pids)
        communication[p] = broadcast_comm(
            receiving_from[p],
            sending_to[p]
        )
    end 
    
    return communication
end


function broadcast_communication!(pids,receiving_from, sending_to, channel_type::T) where T

    PowOT_batches = PowOT_process_breakdown(pids)

    if length(PowOT_batches) > 1

        batch_offset = length(PowOT_batches[1]) + 1

        for i = 2:length(PowOT_batches)
            channel = RemoteChannel(()->Channel{T}(1),PowOT_batches[i][1])
            push!(sending_to[1],channel)
            receiving_from[batch_offset] = channel

            batch_offset += length(PowOT_batches[i])
        end
    end

    batch_offset = 0 
    for batch in PowOT_batches

        broadcast_PowOT_communication!(batch,batch_offset,
                                       sending_to, receiving_from,
                                       channel_type)
        batch_offset += length(batch)
    end

end

function broadcast_PowOT_communication!(pids, batch_offset, sending_to,receiving_from,channel_type::T) where T
    #accumulates on pids[1]

    max_depth = Int(round(log2(length(pids))))
    pididx = findfirst(isequal(myid()), pids)


    #
    #    Coordinate communication
    #
  
    receiving_from_idx = zeros(Int,2^max_depth)

    sending = [1]

    for l=1:max_depth

        offset = Int(floor(2^(max_depth-l)))

        new_to_send = []
        for pididx in sending 
            #sendto
            channel = RemoteChannel(()->Channel{T}(1),pids[pididx + offset])
                                                        #channels should exist on receiving nodes
            #push!(channels,RemoteChannel(()->Channel{Matrix{Float64}}(1),pids[pididx]))

            if receiving_from_idx[pididx+offset] == 0
                receiving_from_idx[pididx+offset] = pididx
                receiving_from[batch_offset + pididx+offset] = channel
            end
            
            push!(sending_to[batch_offset + pididx],channel)
            push!(new_to_send,pididx + offset)

        end 

        append!(sending,new_to_send)
        
    end 

end

function broadcast_PowOT_communication(pids,channel_type::T) where T 
    #accumulates on pids[1]

    max_depth = Int(round(log2(length(pids))))
    pididx = findfirst(isequal(myid()), pids)


    #
    #    Coordinate communication
    #
  
    receiving_from_idx = zeros(Int,2^max_depth)
    receiving_from = Vector{RemoteChannel{Channel{T}}}(undef,2^max_depth)

    sending_to = Vector{Vector{RemoteChannel{Channel{T}}}}(undef,2^max_depth)
    for p in 1:2^max_depth
        sending_to[p] = Vector{RemoteChannel{Channel{T}}}(undef,0)
    end

    sending = [1]

    for l=1:max_depth

        offset = Int(floor(2^(max_depth-l)))

        new_to_send = []
        for pididx in sending 
            #sendto
            channel = RemoteChannel(()->Channel{T}(1),pids[pididx + offset])
                                                        #channels should exist on receiving nodes
            #push!(channels,RemoteChannel(()->Channel{Matrix{Float64}}(1),pids[pididx]))

            if receiving_from_idx[pididx+offset] == 0
                receiving_from_idx[pididx+offset] = pididx
                receiving_from[pididx+offset] = channel
            end
            
            push!(sending_to[pididx],channel)
            push!(new_to_send,pididx + offset)

        end 

        append!(sending,new_to_send)
        
    end 

    return sending_to, receiving_from
end


function Base.broadcast(data,communication::C) where {C <: broadcast_comm}

    if communication.receiving_from !== nothing 
        data = take!(communication.receiving_from)
    end

    for channel in communication.sending_to
        put!(channel,data)
    end

    return data 

end

#
#    Profiling subroutines 
#

#= run:
   @everywhere using Random.seed!
=#
function broadcast_profiled(data_seed::seeded_data,communication::C) where {C <: broadcast_comm}

    seed!(data_seed.seed)
    data_gen_start_t = time_ns()
    data = rand(Float64,data_seed.n,data_seed.n) 
    data_gen_t = Float64(time_ns() - data_gen_start_t)*1e-9

    return broadcast_profiled(data,communication)..., data_gen_t
end

function broadcast_profiled(data,communication::C) where {C <: broadcast_comm}

    alloc_start_t = time_ns()
    put_timings = Vector{Float64}(undef,length(communication.sending_to))
    alloc_t = Float64(time_ns() - alloc_start_t)*1e-9

    return broadcast_profiled!(data,communication,put_timings)..., alloc_t
 
end

function broadcast_profiled!(data,communication::C,put_timings) where {C <: broadcast_comm}

    start_time = time_ns()

    if communication.receiving_from === nothing 
        take_time = 0.0
    else
        take_start_time = time_ns()
        data = take!(communication.receiving_from)
        take_time = Float64(time_ns() - take_start_time)*1e-9
    end

    for (i,channel) in enumerate(communication.sending_to)
        put_start_time = time_ns()
        put!(channel,data)
        put_timings[i]= Float64(time_ns() - put_start_time)*1e-9
    end

    internal_time =  Float64(time_ns() - start_time)*1e-9

    return data, internal_time, put_timings, take_time

end