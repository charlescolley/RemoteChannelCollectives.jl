@testset "Shared" begin 

    @testset "PowOT_breakdown" begin 

        trials = 10 
        proc_counts = rand(1:100000,trials)
        is_power_of_two = num->2^Int(log2(num)) == num

        function test_offsets(offsets)
            first_idx_is_one = (offsets[1] == 1)

            all_powers_of_two = true 
            for i = 1:(length(offsets)-1)
                if !is_power_of_two(offsets[i+1] - offsets[i])
                    all_powers_of_two = false 
                    break 
                end 
            end 
            return all_powers_of_two && first_idx_is_one
        end 

        @test all([test_offsets(RemoteChannelCollectives.PowOT_breakdown(proc_counts[t])) for t =1:trials])
    end 


    @testset "tree_spawn_fetch" begin 

        experiment_parameters = create_test_parameters(pids,check_all_proc_batches_q)
        @test all([batch == tree_spawn_fetch(x->x,batch,batch) for batch in experiment_parameters])

    end 

end 