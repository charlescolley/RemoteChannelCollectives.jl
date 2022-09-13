@testset "Gather Test" begin
    
    @everywhere function gather_proc_test(seed,n,communication)

        seed!(seed)
        my_data = rand(Float64,n,n)
        all_data = gather(my_data,communication)
        all_data_profiled,_,_,_ = gather_profiled(my_data,communication)

        return all_data, all_data_profiled
    
    end


    gather_pididx = 1
    
    #
    #  Stage the Communication
    #
    @inferred gather_communication(pids,gather_pididx,zeros(Float64,0,0))
    communication = gather_communication(pids,gather_pididx,zeros(Float64,0,0))

    futures = []


    #
    #  Start the processors
    #

    for p = 1:length(pids)

        future = @spawnat pids[p] gather_proc_test(seeds[p],n,communication[p])
        push!(futures,future)
    end


    gather_data, gather_profiled_data = fetch(futures[gather_pididx])

    serial_generated = []
    for seed in seeds
        seed!(seed)
        push!(serial_generated,rand(Float64,n,n))
    end

    @test serial_generated == gather_data
    @test serial_generated == gather_profiled_data

end
