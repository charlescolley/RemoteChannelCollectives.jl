@testset "Broadcast Test" begin

    @everywhere function broadcast_test_proc(communication,n)
        if communication.receiving_from === nothing 
            seed!(0)
            data = rand(Float64,n,n)
            broadcast(data,communication)
            
        else
            data = broadcast(nothing ,communication)
        end 

        if communication.receiving_from === nothing 
            broadcast(data,communication)
            profiled_data = data
        else
            profiled_data,_,_,_ = broadcast_profiled(nothing ,communication)
        end 

        return data, profiled_data      
    end
    

    bcast_pididx = 5
    #n = 10
    #
    #  Stage the Communication
    #
    @inferred broadcast_communication(pids,bcast_pididx,zeros(Float64,0,0))
    communication = broadcast_communication(pids,bcast_pididx,zeros(Float64,0,0))

    futures = []

    #
    #  Start the processors
    #

    for p = 1:length(pids)
        future = @spawnat pids[p] broadcast_test_proc(communication[p],n)
        push!(futures,future)
    end

    bcast_vals = []
    bcast_profiled_vals = []

    
    # collect and aggregate the results 
    for future in futures
        bcast_data, bcast_profiled_data = fetch(future)
        push!(bcast_vals,bcast_data)
        push!(bcast_profiled_vals,bcast_profiled_data)
    end    

    @test all([v == bcast_vals[bcast_pididx] for v in bcast_vals])
    @test all([v == bcast_profiled_vals[bcast_pididx] for v in bcast_profiled_vals])

end
