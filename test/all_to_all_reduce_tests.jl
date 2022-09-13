@testset "All to All Reduction" begin

    @inferred all_to_all_reduction_communication(pids,1)
    communication = all_to_all_reduction_communication(pids,1)


    @everywhere function all_to_all_reduction_proc(my_data,proc_communication)

        reduction_f = (x,y) -> x + y 
        reduced_data = all_to_all_reduce(reduction_f,my_data,proc_communication)
        profiled_reduced_data = all_to_all_reduce_profiled(reduction_f,my_data,proc_communication)

        return reduced_data, profiled_reduced_data[1]       
    end


    test_vals = rand(1:100,length(pids))

    futures = []

    for p = 1:length(pids)
        future = @spawnat pids[p] all_to_all_reduction_proc(test_vals[p],communication[p])
        push!(futures,future)
    end

    all_vals = [] 
    profiled_all_vals = []

    for future in futures 
        data, profiled_data = fetch(future)
        push!(all_vals,data)
        push!(profiled_all_vals,profiled_data)
    end 

    for vals in [all_vals,profiled_all_vals]
        @test sum(test_vals) == vals[1]
        @test all([v == vals[1] for v in vals])
    end
    
end
