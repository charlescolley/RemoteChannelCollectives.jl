using Test
using Distributed
addprocs(8)

@everywhere using RemoteChannel_MPI
@everywhere using Random: seed!

pids = workers()
println("MPI Test procs:$(pids)")
seed!(0)
seeds = rand(UInt,length(pids))
n = 1

check_all_proc_batches_q = true

include("all_to_all_reduce_tests.jl")
include("broadcast_tests.jl")   
include("gather_tests.jl")
include("personalized_all_to_all_tests.jl")
include("prefix_scan_tests.jl")
