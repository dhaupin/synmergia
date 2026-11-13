# terrain_batch.jl — the terrain pre-solve batch driver (Facet 1).
#
# Evaluates TerrainGen's raw analytic heightfield for a whole batch of
# directions in ONE process, so the frame pays a single round-trip (or,
# offline, zero) instead of deriving each vertex in GDScript.
#
# The batch of directions is a deterministic Fibonacci sphere so the
# GDScript bench (`tests/bench_terrain.gd`) generates the IDENTICAL set --
# the two timings are comparable and the two height vectors cross-check.
#
# Usage:
#     julia --project=. terrain_batch.jl [--n N] [--seed HEX] [--json]
include("terrainmath.jl")
using .TerrainMath

const TAU = 2 * pi

"""Fibonacci-sphere directions, identical to bench_terrain.gd's generator."""
function fib_sphere(n::Int)
    pts = Vector{NTuple{3,Float64}}(undef, n)
    ga = pi * (3.0 - sqrt(5.0))
    for i in 0:(n - 1)
        z = 1.0 - (2.0 * i + 1.0) / n
        r = sqrt(max(0.0, 1.0 - z * z))
        th = ga * i
        pts[i + 1] = (cos(th) * r, z, sin(th) * r)
    end
    return pts
end

hexb(h::AbstractString) = UInt8[parse(UInt8, h[i:i+1]; base = 16) for i in 1:2:length(h)]

function main()
    n = 20000
    seed_hex = "73616c7463726f776e2d69736c652d34"  # "saltcrown-isle-4"
    json = false
    args = ARGS
    i = 1
    while i <= length(args)
        if args[i] == "--n";        n = parse(Int, args[i+1]); i += 2
        elseif args[i] == "--seed"; seed_hex = args[i+1]; i += 2
        elseif args[i] == "--json"; json = true; i += 1
        else; i += 1
        end
    end

    seed = hexb(seed_hex)
    dirs = fib_sphere(n)

    # Warm up (compile the height path) before timing.
    acc = 0.0
    for d in dirs[1:min(n, 500)]
        acc += TerrainMath.natural_raw(d, seed)
    end

    t0 = time_ns()
    heights = Vector{Float64}(undef, n)
    for k in 1:n
        heights[k] = TerrainMath.natural_raw(dirs[k], seed)
    end
    t1 = time_ns()

    total = sum(heights)
    if json
        println("{\"usec\":", div(t1 - t0, 1000), ",\"n\":", n, ",\"total\":", total, "}")
    else
        println("JULIA_TERRAIN_USEC ", div(t1 - t0, 1000), " n=", n, " total=", total)
    end
end

main()
