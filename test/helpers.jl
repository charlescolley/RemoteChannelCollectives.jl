function create_test_parameters(pids,check_all_proc_batches_q,check_all_collection_pids_q)
    exp_parameters = [] 

    if check_all_proc_batches_q && check_all_collection_pids_q
        for p = 2:length(pids)
            batch = pids[1:p]
            for idx in 1:length(batch)
                push!(exp_parameters,(batch,idx))
            end 
        end 
    elseif check_all_proc_batches_q  
        for p = 2:length(pids)
            push!(exp_parameters,(pids[1:p],1))
        end 
    elseif check_all_collection_pids_q
        for idx in 1:length(pids)
            push!(exp_parameters,(pids,idx))
        end 
    else 
        push!(exp_parameters,(pids,1))
    end 
    return exp_parameters
end 