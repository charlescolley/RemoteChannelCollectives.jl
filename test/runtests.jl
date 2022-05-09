using Test
using Distributed
addprocs(7)

@everywhere using RemoteChannel_MPI
include("MPI_tests.jl")