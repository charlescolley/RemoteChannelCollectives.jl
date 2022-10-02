@everywhere using RemoteChannel_MPI

@everywhere using Random: seed!
using JSON
using Base.Filesystem: mkpath, ispath 

abstract type CommType end

struct PA2A <: CommType end
struct AllReduce <: CommType end 
struct Reduce <: CommType end 
struct Gather <: CommType end
struct Broadcast <: CommType end
struct ExclusivePrefixScan <: CommType end

"""
This profiling assumes the user wants to generate the final data on a master 
process and communicate the final data assignment in serial. These programs 
emulate development which just uses the most naive approach possible. 
"""
function RCMPI_naive_profiling_exp(method::CommType, procs::Vector{Int},n::Int = 10)
  
    num_procs = length(procs)

    seed!(3131)

    if method === PA2A()

        @everywhere function null_program(data)
            return time_ns()
        end

        all_data = Matrix{Matrix{Float64}}(undef,num_procs,num_procs)
        for j = 1:num_procs
            for i = 1:num_procs
                all_data[i,j] = rand(Float64,n,n) 
            end
        end

        spawning_f = p->null_program(all_data[p,:]) 

    elseif method === AllReduce() || method === Reduce() || method === ExclusivePrefixScan()
        return 0.0 #this comparison point doesn't make sense 
    elseif method === Gather()

        @everywhere function null_program(seed,n)
            #                                  passing n in is easier
            #                                  than working with @everywhere
            seed!(seed)
            mat_gen_start_t = time_ns()
            X = rand(Float64,n,n)
            mat_gen_t = Float64(time_ns() - mat_gen_start_t)*1e-9
            return X, mat_gen_t
        end

        seeds = rand(UInt64, num_procs)
        spawning_f = p->null_program(seeds[p],n)

    elseif method === Broadcast()

        @everywhere function null_program(data)
            return time_ns()
        end

        data = rand(Float64,n,n)
        spawning_f = p-> null_program(data)

    end
    


    spawning_time = 0.0
    fetching_time = 0.0
  
    futures = []
    mat_gen_ts = []

    # -- Start the processors -- #
   
    for p = 1:length(procs)

        spawn_start_time = time_ns()
        future = @spawnat procs[p] spawning_f(p)
        spawning_time += Float64(time_ns() - spawn_start_time)*1e-9
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
        return (fetching_time + spawning_time) - maximum(mat_gen_ts)
    else 
        return fetching_time + spawning_time
    end
end 

function RCMPI_profiling_exp(method::CommType, procs::Vector{Int},n::Int = 10)

    num_procs = length(procs)
    seed!(3131)

    if method === PA2A()

        comm_setup_start_time = time_ns()
        communication = personalized_all_to_all_communication(procs,zeros(Float64,0,0))
        comm_setup_time = Float64(time_ns() - comm_setup_start_time)*1e-9

        all_seeds = rand(UInt64, num_procs)

        spawning_f = p->personalized_all_to_all_profiled(seeded_data(all_seeds[p],n),communication[p])[2:end]

    elseif method === AllReduce()
    
        comm_setup_start_time = time_ns()
        communication = all_to_all_reduction_communication(procs,zeros(Float64,0,0))
        comm_setup_time = Float64(time_ns() - comm_setup_start_time)*1e-9

        all_seeds = rand(UInt64, num_procs)

        spawning_f = p->all_to_all_reduce_profiled(seeded_data(all_seeds[p],n),communication[p])[2:end]


    elseif method === Gather()

        comm_setup_start_time = time_ns()
        communication = gather_communication(procs,1,zeros(Float64,0,0))
        comm_setup_time = Float64(time_ns() - comm_setup_start_time)*1e-9

        all_seeds = rand(UInt64, num_procs)

        spawning_f = p->gather_profiled(seeded_data(all_seeds[p],n),communication[p])[2:end]

    elseif method === Broadcast()

        comm_setup_start_time = time_ns()
        communication = broadcast_communication(procs,1,zeros(Float64,0,0))
        comm_setup_time = Float64(time_ns() - comm_setup_start_time)*1e-9

        spawning_f = p-> p == 1 ? broadcast_profiled(seeded_data(3133,n),communication[p])[2:end] : [broadcast_profiled(nothing,communication[p])[2:end]...,0.0]

    elseif method === ExclusivePrefixScan()

        comm_setup_start_time = time_ns()
        communication = prefix_scan_communication(procs,zeros(Float64,0,0))
        comm_setup_time = Float64(time_ns() - comm_setup_start_time)*1e-9

        all_seeds = rand(UInt64, num_procs)
        spawning_f = p-> prefix_scan_profiled(seeded_data(all_seeds[p],n),communication[p])[2:end]
    elseif method === Reduce() 

        reduce_pid = 1
        comm_setup_start_time = time_ns()
        communication = reduce_communication(procs,reduce_pid,zeros(Float64,0,0))
        comm_setup_time = Float64(time_ns() - comm_setup_start_time)*1e-9

        all_seeds = rand(UInt64, num_procs)
        spawning_f = p-> reduce_profiled(seeded_data(all_seeds[p],n),communication[p])[2:end]
    end
    


    futures = []

    # -- Start the processors -- #

    spawning_time = 0.0
    for p = 1:length(procs)

        spawn_start_time = time_ns()
        future = @spawnat procs[p] spawning_f(p)
        spawning_time += Float64(time_ns() - spawn_start_time)*1e-9
        push!(futures,future)
    end
    

    all_profiling = []
    
    fetching_time = 0.0
    for future in futures
        fetch_start_time = time_ns()
        results = fetch(future)
        fetching_time += Float64(time_ns() - fetch_start_time)*1e-9

        push!(all_profiling,results)
                                    # expecting first arg to be data returned
    end 
    
    return all_profiling, comm_setup_time, fetching_time, spawning_time
end

function RCMPI_profiling_exp(method::CommType, proc_batches::Vector{Vector{Int}},mat_sizes::Vector{Int},trials::Int,output_file::Union{Nothing,String}=nothing)

    profiling_results = Array{Any,4}(undef,length(proc_batches),
                                               length(mat_sizes),trials,4)
                        # last dimension
    serial_comm_results = Array{Any,3}(undef,length(proc_batches),
                        length(mat_sizes),trials)

    for (p_idx,procs) in enumerate(proc_batches)
        for (n_idx,n) in enumerate(mat_sizes)
            for t =1:(trials+1)
                
                #TODO: should we throw away more trials to address cold start effects? 
                if t == 1 
                    RCMPI_profiling_exp(method,procs,n)
                else
                    all_profiling, comm_setup_time, fetching_time, spawning_time = RCMPI_profiling_exp(method,procs,n)
                    serial_comm_results[p_idx,n_idx,t-1] = RCMPI_naive_profiling_exp(method,procs,n)

                    profiling_results[p_idx,n_idx,t-1,1] = all_profiling
                    profiling_results[p_idx,n_idx,t-1,2] = comm_setup_time
                    profiling_results[p_idx,n_idx,t-1,3] = fetching_time
                    profiling_results[p_idx,n_idx,t-1,4] = spawning_time

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
           ("fetching_time", profiling_results[:,:,:,3]),
           ("spawning_time", profiling_results[:,:,:,4]),
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

function RCMPI_profiling_exp(method::CommType,test::Bool) 
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

    output_file = "RCMPI_$(comm_type_str)_numProcs:$(batch_size_range)_n:$(mat_sizes)_trials:$(trials)_"
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
    RCMPI_profiling_exp(method,proc_batches,mat_sizes,trials,output_folder*output_file)

end