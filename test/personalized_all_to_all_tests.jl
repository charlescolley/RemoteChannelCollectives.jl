
    @testset "Personalized All to All" begin

        @everywhere function personalized_all_to_all_proc(seed,n,comm,profiled_q)

            seed!(seed)

            all_data = Vector{Matrix{Float64}}(undef,length(comm.sending_to)+1)
            #data_for_me[comm.my_idx] = rand(Float64,n,n)
            for i = 1:length(comm.sending_to) + 1
                     # generate data for all_other_process
                all_data[i] = rand(Float64,n,n)
            end 
            #data_for_me = Vector{Matrix{Float64}}(undef,length(sending_to)+1)
                                            # expecting length(pids) - 1 data points  

            if profiled_q
                data_for_me_profiled = personalized_all_to_all_profiled(all_data,comm)
                return data_for_me_profiled[1]
            else 
                return personalized_all_to_all(all_data,comm)
            end
            #data_for_me_profiled = personalized_all_to_all_profiled(all_data,comm)

            return data_for_me, data_for_me #data_for_me_profiled[1]
        
        end 
        

        


        function spawner(proc_batch,profiled_q)
            #  --  Stage the Communication  --  #

            communication = personalized_all_to_all_communication(proc_batch,zeros(Float64,0,0))
            futures = []
        
            
            # -- Start the processors -- #
            for p = 1:length(proc_batch)
                future = @spawnat proc_batch[p] personalized_all_to_all_proc(seeds[p],n,communication[p],profiled_q)
                push!(futures,future)
            end
        

            all_vals = Array{Matrix{Float64}}(undef,length(proc_batch),length(proc_batch))
            #all_vals_profiled = Array{Matrix{Float64}}(undef,length(proc_batch),length(proc_batch))
            

            # collect and aggregate the results 
            for (i,future) in enumerate(futures)
                data = fetch(future)
                all_vals[i,:] = data
                #all_vals_profiled[i,:] = data_profiled
            end    
            
        
            serial_generated = Array{Matrix{Float64}}(undef,length(proc_batch),length(proc_batch))
            for p_i in 1:length(proc_batch)
                seed!(seeds[p_i])
                for p_j=1:length(proc_batch)
                    serial_generated[p_j,p_i] = rand(Float64,n,n)
                end
            end

            return all_vals == serial_generated
            #@test all_vals_profiled == serial_generated
    
        end

        @inferred personalized_all_to_all_communication(pids,zeros(Float64,0,0))
        for proc_batch in [pids,pids[1:7]]
            @test spawner(proc_batch,true)
            @test spawner(proc_batch,false)
        end 
    end 
