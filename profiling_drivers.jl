@everywhere using RemoteChannelCollectives
@everywhere using Random: seed!

@everywhere abstract type CommType end

@everywhere struct PA2A <: CommType end
@everywhere struct AllReduce <: CommType end 
@everywhere struct Reduce <: CommType end 
@everywhere struct Gather <: CommType end
@everywhere struct Broadcast <: CommType end
@everywhere struct ExclusivePrefixScan <: CommType end

using JSON
using Base.Filesystem: mkpath, ispath 

@everywhere function null_program(method::CommType,args...)
    if method === PA2A() || method === Broadcast()

        return time_ns()

    elseif method === AllReduce() || method === Reduce() || method === ExclusivePrefixScan()

        return 0.0 

    elseif method === Gather()
        
        seed, n = args

        seed!(seed)
        mat_gen_start_t = time_ns()
        X = rand(Float64,n,n)
        mat_gen_t = Float64(time_ns() - mat_gen_start_t)*1e-9
        return X, mat_gen_t

    end 
end 

"""
This profiling assumes the user wants to generate the final data on a master 
process and communicate the final data assignment in serial. These programs 
emulate development which just uses the most naive approach possible. 
"""
function RCC_naive_profiling_exp(method::CommType, procs::Vector{Int},n::Int = 10)
  
    num_procs = length(procs)

    seed!(3131)

    if method === PA2A()

        all_data = Matrix{Matrix{Float64}}(undef,num_procs,num_procs)
        for j = 1:num_procs
            for i = 1:num_procs
                all_data[i,j] = rand(Float64,n,n) 
            end
        end

    elseif method === AllReduce() || method === Reduce() || method === ExclusivePrefixScan()
        return 0.0 #this comparison point doesn't make sense 
    elseif method === Gather()

        all_seeds = rand(UInt64, num_procs)

    elseif method === Broadcast()

        data = rand(Float64,n,n)

    end
    


    spawning_time = 0.0
    fetching_time = 0.0
  
    futures = []
    mat_gen_ts = []

    # -- Start the processors -- #
   
    for p = 1:length(procs)


        if method === PA2A()
            spawn_start_time = time_ns()
            future = @spawnat procs[p] null_program(method,all_data[:,p])
            spawning_time += Float64(time_ns() - spawn_start_time)*1e-9
        elseif method === Broadcast() 
            spawn_start_time = time_ns()
            future = @spawnat procs[p] null_program(method,data)
            spawning_time += Float64(time_ns() - spawn_start_time)*1e-9
        elseif method === Gather() 
            spawn_start_time = time_ns()
            future = @spawnat procs[p] null_program(method,all_seeds[p],n)
            spawning_time += Float64(time_ns() - spawn_start_time)*1e-9
        else
            spawn_start_time = time_ns()
            future = @spawnat procs[p] null_program(method)
            spawning_time += Float64(time_ns() - spawn_start_time)*1e-9
        end 

        push!(futures,future)

    end
    
    for future in futures
        if method === Gather()
            fetch_start_time = time_ns()
            _, mat_gen_t = fetch(future)
            fetching_time += Float64(time_ns() - fetch_start_time)*1e-9
            push!(mat_gen_ts,mat_gen_t)
        else
            fetch_start_time = time_ns()
            _ = fetch(future)
            fetching_time += Float64(time_ns() - fetch_start_time)*1e-9
        end
    end
    
    if method === Gather()
        return (fetching_time + spawning_time)# - maximum(mat_gen_ts)
    else 
        return fetching_time + spawning_time
    end
end 

@everywhere function spawning_function(method::CommType, n::Int, comm::T,args...) where {T <: Communication}
        
    if method === PA2A()
            
        seed = args[1]
        output = personalized_all_to_all_profiled(seeded_data(seed,n),comm)

    elseif method === AllReduce()

        seed = args[1]
        output = all_to_all_reduce_profiled(seeded_data(seed,n),comm)


    elseif method === Gather()

        seed = args[1]
        output = gather_profiled(seeded_data(seed,n),comm)

    elseif method === Broadcast()

        b_castseed = 3133
        if comm.receiving_from === nothing
            output = broadcast_profiled(seeded_data(b_castseed,n),comm)
        else
            output = broadcast_profiled(nothing,comm), 0.0 
                                                    # these procs don't 
                                                    # generate messages
        end 
    elseif method === ExclusivePrefixScan()

        seed = args[1]
        output = prefix_scan_profiled(seeded_data(seed,n),comm)


    elseif method === Reduce()

        seed = args[1]
        output = reduce_profiled(seeded_data(seed,n),comm)
        
    else 

        throw(DomainError(method,"Unimplemented"))
    end 
    return output[2:end]
            # don't return the messages computed. 
end 

function RCC_profiling_exp(method::CommType, procs::Vector{Int},n::Int = 10)

    num_procs = length(procs)
    seed!(3131)

    if method === PA2A()

        comm_setup_start_time = time_ns()
        communication = personalized_all_to_all_communication(procs,zeros(Float64,0,0))
        comm_setup_time = Float64(time_ns() - comm_setup_start_time)*1e-9

        all_seeds = rand(UInt64, num_procs)
        inputs = Vector{Tuple{PA2A,Int,personalized_all_to_all_comm{Matrix{Float64}},UInt}}(undef,num_procs)
        for p =1:num_procs
            inputs[p] = (PA2A(),n,communication[p],all_seeds[p])
        end             #TODO: give tree_spawn_fetch a shared args parameter. 

    elseif method === AllReduce()
    
        comm_setup_start_time = time_ns()
        communication = all_to_all_reduction_communication(procs,zeros(Float64,0,0))
        comm_setup_time = Float64(time_ns() - comm_setup_start_time)*1e-9

        all_seeds = rand(UInt64, num_procs)

        inputs = Vector{Tuple{AllReduce,Int,all_to_all_reduce_comm{Matrix{Float64}},UInt}}(undef,num_procs)
        for p =1:num_procs
            inputs[p] = (AllReduce(),n,communication[p],all_seeds[p])
        end


    elseif method === Gather()

        comm_setup_start_time = time_ns()
        communication = gather_communication(procs,1,zeros(Float64,0,0))
        comm_setup_time = Float64(time_ns() - comm_setup_start_time)*1e-9

        all_seeds = rand(UInt64, num_procs)
        inputs = Vector{Tuple{Gather,Int,gather_comm{Matrix{Float64}},UInt}}(undef,num_procs)
        for p =1:num_procs
            inputs[p] = (Gather(),n,communication[p],all_seeds[p])
        end

    elseif method === Broadcast()

        comm_setup_start_time = time_ns()
        communication = broadcast_communication(procs,1,zeros(Float64,0,0))
        comm_setup_time = Float64(time_ns() - comm_setup_start_time)*1e-9

        inputs = Vector{Tuple{Broadcast,Int,broadcast_comm{Matrix{Float64}}}}(undef,num_procs)
        for p =1:num_procs
            inputs[p] = (Broadcast(),n,communication[p])
        end

    elseif method === ExclusivePrefixScan()

        comm_setup_start_time = time_ns()
        communication = prefix_scan_communication(procs,zeros(Float64,0,0))
        comm_setup_time = Float64(time_ns() - comm_setup_start_time)*1e-9

        all_seeds = rand(UInt64, num_procs)
        inputs = Vector{Tuple{ExclusivePrefixScan,Int,prefix_scan_comm{Matrix{Float64}},UInt}}(undef,num_procs)
        for p =1:num_procs
            inputs[p] = (ExclusivePrefixScan(),n,communication[p],all_seeds[p])
        end

    elseif method === Reduce() 

        reduce_pid = 1
        comm_setup_start_time = time_ns()
        communication = reduce_communication(procs,reduce_pid,zeros(Float64,0,0))
        comm_setup_time = Float64(time_ns() - comm_setup_start_time)*1e-9

        all_seeds = rand(UInt64, num_procs)
        inputs = Vector{Tuple{Reduce,Int,reduce_comm{Matrix{Float64}},UInt}}(undef,num_procs)
        for p =1:num_procs
            inputs[p] = (Reduce(),n,communication[p],all_seeds[p])
        end

    end
    
    
    

    spawn_fetch_start_time = time_ns()
    all_profiling  = tree_spawn_fetch(spawning_function, procs, inputs)
    spawn_fetch_time = Float64(time_ns() - spawn_fetch_start_time)*1e-9
    return all_profiling, comm_setup_time, spawn_fetch_time
end

function RCC_profiling_exp(method::CommType, proc_batches::Vector{Vector{Int}},mat_sizes::Vector{Int},trials::Int,output_file::Union{Nothing,String}=nothing)

    profiling_results = Array{Any,4}(undef,length(proc_batches),
                                               length(mat_sizes),trials,3)
                        # last dimension
    serial_comm_results = Array{Any,3}(undef,length(proc_batches),
                        length(mat_sizes),trials)

    for (p_idx,procs) in enumerate(proc_batches)
        for (n_idx,n) in enumerate(mat_sizes)
            for t =1:(trials+1)
                
                #TODO: should we throw away more trials to address cold start effects? 
                if t == 1 
                    RCC_profiling_exp(method,procs,n)
                else
                    all_profiling, comm_setup_time, spawn_fetch_time  = RCC_profiling_exp(method,procs,n)
                    serial_comm_results[p_idx,n_idx,t-1] = RCC_naive_profiling_exp(method,procs,n)

                    profiling_results[p_idx,n_idx,t-1,1] = all_profiling
                    profiling_results[p_idx,n_idx,t-1,2] = comm_setup_time
                    profiling_results[p_idx,n_idx,t-1,3] = spawn_fetch_time

                end
            end 
            println("completed mat_size:$(n)")
        end 

        println("completed proc_batch:$(procs)")
    end 

    if output_file !== nothing 
        output_dict = Dict([
           ("proc_profiling", profiling_results[:,:,:,1]),
           ("comm_setup_time", profiling_results[:,:,:,2]),
           ("spawn_fetch_time", profiling_results[:,:,:,3]),
           ("serial_comm_time",serial_comm_results),
           ("proc_batches",proc_batches),
           ("mat_sizes",mat_sizes),
           ("trials",trials),
           ("output_file",output_file),
        ]) 

        open(output_file,"w") do f
            JSON.print(f, output_dict)
        end

    else
        return profiling_results
    end
end
function RCC_profiling_exp(method::CommType,test::Bool) 
    # experiment driver for tests 

    if test
        batch_size_range = 2:3
        mat_sizes = [10]
        trials = 2
    else
        batch_size_range = [min(2^i,27) for i in 1:5]
        #batch_size_range = 2:27
        mat_sizes = [1,10,100,1000]
        trials = 20
    end 
    proc_batches = [workers()[1:p] for p in collect(batch_size_range)]
 
    if method === PA2A()
        comm_type_str = "PA2A"
    elseif method === AllReduce()
        comm_type_str = "AllReduce"
    elseif method === Gather()
        comm_type_str = "Gather"
    elseif method === Broadcast()
        comm_type_str = "Broadcast"
    elseif method === ExclusivePrefixScan()
        comm_type_str = "ExPrefixScan"
    elseif method === Reduce()
        comm_type_str = "Reduce"
    end #TODO: can we do this by defining string(X::CommType)?

    output_file = "RCC_$(comm_type_str)_numProcs:$(batch_size_range)_n:$(mat_sizes)_trials:$(trials)_"
    output_folder = "./"

    #  -- augment filename with remaining parameters -- #

    if test 
        output_file *= "test_"
        output_folder *= "test/"
    end


    numa_aware = false
    """ this is a var to be set manually as beneath command must be run to 
    execute on a single NUMA core. 
    
    Command to run on a single NUMA core on Skyline:
        numactl --localalloc --physcpubind=1,3,5,7,9,11,13,15,17,19,21,23,25,27,29,31,33,35,37,39,41,43,45,47,49,51,53,55 -- /p/mnt/software/julia-1.8/bin/julia -p 27
    
    TODO: look into using ClusterManager.jl for proc pinning routines. 
    """
    
    if numa_aware 
        output_file *= "NUMA_"
    end
    output_file *= "results.json"
    output_file = filter(x->!isspace(x),output_file)

    if !ispath(output_folder)
        mkpath(output_folder)
    end


    #  -- Run Trials -- # 

    println("starting experiment:\n  $(output_folder*output_file)")
    RCC_profiling_exp(method,proc_batches,mat_sizes,trials,output_folder*output_file)

end

function RCC_profiling_exp(test::Bool) 

    RCC_profiling_exp(Broadcast(),test) 
    RCC_profiling_exp(PA2A(),test) 
    RCC_profiling_exp(AllReduce(),test) 
    RCC_profiling_exp(Reduce(),test) 
    RCC_profiling_exp(Gather(),test) 
    RCC_profiling_exp(ExclusivePrefixScan(),test) 

end