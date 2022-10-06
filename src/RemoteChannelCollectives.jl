module RemoteChannelCollectives

using Distributed

abstract type Communication end

struct seeded_data 
     seed::UInt
     n::Int
end #used as a flag to indicate profiling routines to generate data locally.

include("shared.jl")

include("all_to_all_reduce.jl")
include("broadcast.jl")
include("gather.jl")
include("reduce.jl")
include("personalized_all_to_all.jl")
include("prefix_scan.jl")

using Random: seed!
export Communication

using ..Base: broadcast
     # exporting broadcast triggers a
     # warning due to existance in Base. 
export broadcast_comm, broadcast_communication, broadcast, broadcast_profiled

export all_to_all_reduce_comm, all_to_all_reduction_communication, all_to_all_reduce, all_to_all_reduce_profiled
export gather_comm, gather_communication, gather, gather_profiled
export reduce_comm, reduce_communication, reduce, reduce_profiled

export personalized_all_to_all_comm, personalized_all_to_all_communication, personalized_all_to_all, personalized_all_to_all_profiled
export prefix_scan_comm, powot_batch_prefix_scan_comm, prefix_scan_communication, prefix_scan, prefix_scan_profiled

export seeded_data

export tree_spawn_fetch

end # module end 