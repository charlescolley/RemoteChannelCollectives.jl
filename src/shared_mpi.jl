function PowOT_process_breakdown(pids)
         # power of two 
    num_procs = length(pids)

    PowOT_batches = Vector{Vector{Int}}(undef,0)

    start_idx = 1 
    while num_procs > 0
        mesh_size = Int(2^floor(log2(num_procs)))
        push!(PowOT_batches,pids[start_idx:(start_idx - 1+mesh_size)])
        num_procs -= mesh_size
        start_idx += mesh_size
    end

    return PowOT_batches
end

function PowOT_breakdown(num_procs::Int)
    # power of two 

    PowOT_offsets = Vector{Int}(undef,0)
    start_idx = 1 
    
    remaining_procs = copy(num_procs)

    while remaining_procs  > 0
        push!(PowOT_offsets,start_idx)

        batch_size = Int(2^floor(log2(remaining_procs)))
        remaining_procs  -= batch_size
        start_idx += batch_size
    end
    return PowOT_offsets
end


#
#    Spawn Fetch Routines
#


@views function tree_spawn_fetch_powot(f, pids::AbstractArray{Int}, args::AbstractArray{T}) where {T}

    max_depth = Int(round(log2(length(pids))))
    futures = Array{Future}(undef,max_depth)
    batch_end_proc::Int = length(pids)

    for l = 1:max_depth
        split = Int(floor(2^(max_depth-l))) + 1 
        futures[l] = @spawnat pids[split] tree_spawn_fetch_powot(f, pids[split:batch_end_proc],args[split:batch_end_proc])
        batch_end_proc /= 2
    end
    
    results = []
    push!(results,f(args[1]...))
    # fetch(future) doesn't preserve types, push! keeps results type Vector{Any}.

    for l = max_depth:-1:1
        x = fetch(futures[l])
        append!(results,x)
    end 

    return results

end 


@views function tree_spawn_fetch(f, pids::AbstractArray{Int}, args::Vector{T}) where {T}
    #run from the spawning node
    batch_offsets = PowOT_breakdown(length(pids))

    num_batches = length(batch_offsets)
    futures = Array{Future}(undef,num_batches)
    for b =1:(num_batches-1)
        start_idx = batch_offsets[b]
        end_idx = start_idx + (batch_offsets[b+1] - batch_offsets[b]) - 1 
        futures[b] = @spawnat pids[start_idx] tree_spawn_fetch_powot(f,pids[start_idx:end_idx],args[start_idx:end_idx])
    end 
    futures[end] = @spawnat pids[batch_offsets[end]] tree_spawn_fetch_powot(f,pids[batch_offsets[end]:end],args[batch_offsets[end]:end])
    

    results = [] 
    for future in reverse!(futures)
                  #small batches are likely to finish first
        batch_result = fetch(future)
        reverse!(batch_result)
        append!(results,batch_result)
        
    end 
    reverse!(results)
    return results
end
