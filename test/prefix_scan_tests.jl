@testset "Prefix Scan Test" begin
    

    @inferred prefix_scan_communication(pids,0)

    @everywhere function prefix_proc(proc_communication)
        scan_f = (x,y)-> x + y
        ps_result = prefix_scan(scan_f,0,myid(),proc_communication)    
        ps_profiled_result,_,_,_,_,_ = prefix_scan_profiled(scan_f,0,myid(),proc_communication)
        return ps_result, ps_profiled_result    
    end


    #test_vals = rand(1:100,length(pids))
    function spawner(ps)

        communication = prefix_scan_communication(ps,0)

        futures = []

        for p = 1:length(ps)
            future = @spawnat ps[p] prefix_proc(communication[p])
            push!(futures,future)
        end

        all_vals = [] 
        profiled_all_vals = []

        for future in futures 
            data,profiled_data = fetch(future)
            push!(all_vals,data)
            push!(profiled_all_vals,profiled_data)
        end 
        
        function test_results(data_to_test) 
            test_passed = true 
            cum_sum = 0.0

            for (pid,val) in zip(ps,data_to_test)
                if val != cum_sum
                    test_passed = false 
                    break 
                end
                cum_sum += pid 
            end
            return test_passed
        end 

        return test_results(all_vals) && test_results(profiled_all_vals)
    end

    if check_all_proc_batches_q 
        @test all([spawner(pids[1:p]) for p in 2:length(pids)])
    else 
        @test spawner(pids)
    end 
end 
#=

@everywhere using Revise
] dev . 
@everywhere using RemoteChannel_MPI

=#