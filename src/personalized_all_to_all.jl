struct personalized_all_to_all_comm{T} <: Communication
    sending_to::Vector{Tuple{Int,RemoteChannel{Channel{Tuple{Int,T}}}}} 
    #TODO: make Int a Uint, there'll never be negative indices. 
    my_channel::RemoteChannel{Channel{Tuple{Int,T}}}
    my_idx::Int
end


function personalized_all_to_all_communication(pids,channel_type::T) where T 

    # each process gets its own channel 
    process_channels = Vector{RemoteChannel{Channel{Tuple{Int,T}}}}(undef,length(pids))
    sending_to = Vector{Vector{Tuple{Int,RemoteChannel{Channel{Tuple{Int,T}}}}}}(undef,length(pids))

    for (i,pid) in enumerate(pids)
        process_channels[i] = RemoteChannel(()->Channel{Tuple{Int,T}}(length(pids)-1),pid)
        sending_to[i] = Vector{Tuple{Int,RemoteChannel{Channel{Tuple{Int,T}}}}}(undef,length(pids)-1)
    end 

    if length(pids) == 2^Int(round(log2(length(pids))))
        personalized_all_to_all_communication_PoWOT!(pids,sending_to,process_channels,channel_type)
    else
        personalized_all_to_all_communication_naive!(pids,sending_to,process_channels,channel_type)
    end

    communication = Vector{personalized_all_to_all_comm{T}}(undef,length(pids))

    for p = 1:length(pids)
        communication[p] = personalized_all_to_all_comm(sending_to[p],process_channels[p],p)
    end 

    return communication
end

function personalized_all_to_all_communication_naive!(pids,sending_to,process_channels,channel_type::T) where T 
    # have all processes send to the same process at every iteration

    for i = 1:length(pids)
        idx = 1
        for j = 1:length(sending_to[i])
            if idx == i
                idx += 1
            end
            sending_to[i][j] = (idx,process_channels[idx])
            idx += 1
            j+=1
        end
    end 
end

function personalized_all_to_all_communication_PoWOT!(pids,sending_to,process_channels,channel_type::T) where T 
    # have all processes send to the same process at every iteration


    for i = 1:length(pids)
        #sending_to[i] = Vector{Tuple{Int,RemoteChannel{Channel{Tuple{Int,T}}}}}(undef,length(pids)-1)
        for j = 1:(length(pids)-1)
            sending_idx = ((i - 1) ⊻ j) + 1
            sending_to[i][j] = (sending_idx,process_channels[sending_idx])
        end
    end 

end


function personalized_all_to_all(all_data::Vector{T},communication::C) where {T,C <: personalized_all_to_all_comm} 

    all_received_data = Vector{T}(undef,length(communication.sending_to)+1)
    all_received_data[communication.my_idx] = all_data[communication.my_idx]

    personalized_all_to_all!(all_data::Vector{T},all_received_data,communication::C)

    return all_received_data
end

function personalized_all_to_all!(all_data::Vector{T},all_received_data,communication::C) where {T,C <: personalized_all_to_all_comm} 

    idx = 1
    for (dest_idx,channel) in communication.sending_to
        if idx == communication.my_idx
            idx += 1 
        end 
        put!(channel,(communication.my_idx,all_data[dest_idx]))
        idx += 1
    end 

    
    data_taken = 1 
    while data_taken <= length(communication.sending_to)
        (idx,their_data) = take!(communication.my_channel)
        all_received_data[idx] = their_data
        data_taken += 1 
    end 
end


function personalized_all_to_all_profiled(data_seed::seeded_data,communication::C) where {C <: personalized_all_to_all_comm} 

    seed!(data_seed.seed)
    data_gen_start_t = time_ns()
    all_data = Vector{Matrix{Float64}}(undef,length(communication.sending_to)+1)
    for i=1:(length(communication.sending_to) + 1)
        all_data[i] = rand(Float64,data_seed.n,data_seed.n) 
    end
    data_gen_t = Float64(time_ns() - data_gen_start_t)*1e-9

    return personalized_all_to_all_profiled(all_data,communication)..., data_gen_t

end

function personalized_all_to_all_profiled(all_data::Vector{T},communication::C) where {T,C <: personalized_all_to_all_comm} 

    alloc_start_time = time_ns()
    put_timings = Vector{Float64}(undef,length(communication.sending_to))
    take_timings = Vector{Float64}(undef,length(communication.sending_to))
    all_received_data = Vector{T}(undef,length(communication.sending_to)+1)
    all_received_data[communication.my_idx] = all_data[communication.my_idx]
    alloc_t = Float64(time_ns() - alloc_start_time)*1e-9

    return personalized_all_to_all_profiled!(all_data,all_received_data,put_timings,take_timings,communication)..., alloc_t
    
end

function personalized_all_to_all_profiled!(all_data::Vector{T},data_for_me::Vector{T},
                                           put_timings::Vector{Float64}, take_timings::Vector{Float64},
                                           communication::C) where {T,C <: personalized_all_to_all_comm} 

    start_time = time_ns()

    for (i,(dest_i,channel)) in enumerate(communication.sending_to)
        put_start_time = time_ns()
        put!(channel,(communication.my_idx,all_data[dest_i]))
        put_timings[i] = Float64(time_ns() - put_start_time)*1e-9
    end 

    data_taken = 1 
    while data_taken <= length(communication.sending_to)
        take_start_time = time_ns()
        (idx,their_data) = take!(communication.my_channel)
        take_timings[data_taken] = Float64(time_ns() - take_start_time)*1e-9
     
        data_for_me[idx] = their_data
        data_taken += 1 
    end 

    internal_timing = Float64(time_ns() - start_time)*1e-9
    return data_for_me, internal_timing, put_timings, take_timings

end

