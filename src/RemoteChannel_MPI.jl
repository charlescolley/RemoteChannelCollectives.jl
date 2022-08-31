module RemoteChannel_MPI

using Distributed

abstract type Communication end

struct seeded_data 
     seed::UInt
     n::Int
end #used as a flag to indicate profiling routines to generate data locally.

include("shared_mpi.jl")
include("gather.jl")
include("broadcast.jl")
include("personalized_all_to_all.jl")
include("all_to_all_reduce.jl")

using Random: seed!

using ..Base: broadcast
     # exporting broadcast triggers a
     # warning due to existance in Base. 
export broadcast_comm, broadcast_communication, broadcast, broadcast_profiled

export all_to_all_reduce_comm, all_to_all_reduction_communication, all_to_all_reduce, all_to_all_reduce_profiled
export gather_comm, gather_communication, gather, gather_profiled
export personalized_all_to_all_comm, personalized_all_to_all_communication, personalized_all_to_all, personalized_all_to_all_profiled

export seeded_data

end # module end 