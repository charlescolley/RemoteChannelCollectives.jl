@testset "Reduce Test" begin
    
    @everywhere function reduce_proc_test(seed,n,profiled_q,communication)

        seed!(seed)
        my_data = rand(Float64,n,n)
        reduction_f = (X,Y) -> X + Y 
        if profiled_q
            reduced_data = reduce_profiled(reduction_f, my_data, communication)
            return reduced_data[1]
        else
            return reduce(reduction_f, my_data, communication)
        end 
    end


    @inferred reduce_communication(pids,1,zeros(Float64,0,0))

    function spawner(ps,reduce_idx,profiled_q) 

        communication = reduce_communication(ps,reduce_idx,zeros(Float64,0,0))

        futures = []
        for p = 1:length(ps)
            future = @spawnat ps[p] reduce_proc_test(seeds[p],n,profiled_q,communication[p])
            push!(futures,future)
        end

        reduced_data = fetch(futures[reduce_idx])

        serial_mat_sum = zeros(Float64,n,n)
        for seed in seeds
            seed!(seed)
            serial_mat_sum += rand(Float64,n,n)
        end
        return reduced_data == reduced_data
    end 

    experiment_parameters = create_test_parameters(pids,check_all_proc_batches_q,check_all_collection_pids_q)

    @test all([spawner(batch,reduction_idx,true) for (batch,reduction_idx) in experiment_parameters])
    @test all([spawner(batch,reduction_idx,false) for (batch,reduction_idx) in experiment_parameters])

end
