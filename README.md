# RemoteChannelCollectives.jl

A package for tree based communication using Distributed.jl's [RemoteChannel](https://docs.julialang.org/en/v1/stdlib/Distributed/#Distributed.RemoteChannel). Distributed.jl uses "one-sided" communication, but SPDM program's send/receive can be emulated by putting to/taking from RemoteChannels. [Collective operations](https://en.wikipedia.org/wiki/Collective_operation) needed are prebuilt and passed to SPMD programs which are spawned by the spawning process (pid). 

## How to Install

```
# in ']' mode
add https://github.com/charlescolley/RemoteChannelCollectives.jl
test RemoteChannelCollectives
```

## How to Use

Communications are built by the spawning node, and passed to each of the processors running the SPMD when they're spawned. Within the Single Program Multiple Data (SPMD) program, each communication function receives the channels that they need in the form of instances of `Communication` subtypes. 

Using parallel array summation as an example, we want to sum a series of numbers on each process and reduce the sum onto one processor. We'll focus on the how to run a reduction, but the process for other communication patterns will be the same. The SPDM program we'll run is 
```julia 
@everywhere function array_sum(data_seed::UInt, comm::C) where {C <: reduce_comm}
    seed!(data_seed)
    reduction = (x,y)-> x + y 
    local_result = reduce(reduction,sum(rand(Float64,100)),comm)
    if comm.sending_to === nothing
        return local_result
    end
end
```

We generate a array of 100 floats on each process and reduce will them to the first processor returned by `workers()`. Each of the processes running `array_sum` are given the RemoteChannels needed for the `reduce` in the `comm <: reduce_comm` argument, which consists of 
```julia 
struct reduce_comm{T} <: Communication
    receiving_from::Vector{RemoteChannel{Channel{T}}}
    sending_to::Union{Nothing,RemoteChannel{Channel{T}}}
end 
```
RemoteChannels are parameterized by the type of the message to be exchanged between processes, and are initialized with 
```julia 
reduce_pid = 1
communication = reduce_communication(pids,reduce_pid,0.0)
```
RemoteChannels are parameterized by their message type. We inform the `..._communication` function of the message type by passing in a small instance of a message. Here we use a 0.0 to indicate we want to send floats. In profiling_drivers.jl, we use zeros(Float64,0,0) to indicate matrices of Floats. 

NOTE: If a program needs to run two reductions with different types, multiple instances of `reduce_comm` need to be created and passed into the spawned programs. 

`reduce_communication` returns an array with each `reduce_comm{T}` needed for each process. Each of the different communication operations have their own `..._communication` function. These functions take in the list of processors, and by default, treat the first process in the list as the root node in the tree-based communication. `communication[p]` is the communication which needed to be passed to the `p`th process, and programs are spawned with 
```julia 
pids = workers() 
seeds = rand(UInt,length(pids))

futures = []
for p = 1:length(pids)
    future = @spawnat pids[p] array_sum(seeds[p],communication[p])
    push!(futures,future)
end 
```

More examples can be found in `profiling_drivers.jl` within the project's top folder.

NOTE: In this example we used a for loop to spawn the processors, but there is also `tree_spawn_fetch` which uses a scatter and gather template to spawn processors, run the algorithm, and fetch the results. This is primarily used in our profiling routines as we want profiling results from each of the processors, but this method wouldn't be recommended for collecting large messages back to the spawning processor. 

<details>

<summary>TLDR, just show me a full program.</summary>

```julia
@everywhere using Random:seed!
@everywhere using RemoteChannelCollectives

@everywhere function array_sum(data_seed::UInt, comm::C) where {C <: reduce_comm}
    seed!(data_seed)
    reduction = (x,y)-> x + y 
    local_result = reduce(reduction,sum(rand(Float64,100)),comm)
    if comm.sending_to === nothing
        return local_result
    end
end

pids = workers() 
reduce_pid = 1
communication = reduce_communication(pids,reduce_pid,0.0)
seeds = rand(UInt,length(pids))

futures = []
for p = 1:length(pids)
    future = @spawnat pids[p] array_sum(seeds[p],communication[p])
    push!(futures,future)
end 

serial_sum = 0.0 
for s in seeds
    seed!(s)
    serial_sum += sum(rand(Float64,100)) 
end

par_sum = fetch(futures[reduce_pid])
println(serial_sum == par_sum)

```
</details>