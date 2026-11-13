# presolve.jl — the pre-solve tier: evaluate a world forward, in parallel.
#
# This is the "pre-solves races" work (labs/prd-industry-labs.md sec 6):
# the frame's derivations are pure functions of (seed, path, epoch), so
# a swarm of epochs/worlds can be evaluated with no simulation. Julia
# does the embarrassingly-parallel sweep; the GDScript frame stays the
# authoritative evaluator and validates this output byte-for-byte
# (tests/test_julia_presolve.gd).
#
# Usage:
#     julia --project=. presolve.jl [--out FILE] [--epochs N] [--step D]
#
# Output (stdout, or --out FILE): one JSON object per line:
#     {"world":"main","seed":"<hex>","epochs":[{...}, ...]}
# where each epoch row is:
#     {"t":<unix>,"day":<i>,"sky":<f>,"window":<i>,
#      "orbit":[x,y,z],"moon_fav":<f>}
#
# The world declarations mirror game/data/worlds/*.tres (the fields the
# derivations read). Keep them in sync with the .tres files.
include("worldmath.jl")
using .WorldMath
using JSON

## The S16.1 lattice, from game/data/worlds/*.tres.
const WORLDS = Dict{String, WorldMath.WorldDecl}(
    "main" => WorldMath.WorldDecl("main", "", 0.0, 0.0, 0.0, 0.0),
    "moon" => WorldMath.WorldDecl("moon", "main", 90000.0, 8.0, 0.7, 0.12),
    "underworld" => WorldMath.WorldDecl("underworld", "main", 0.0, 0.0, 0.0, 0.0),
)

## Default sweep: a full Concord year of sky days at 1-day resolution.
const DEFAULT_EPOCHS = 365
const DEFAULT_STEP_DAYS = 1.0
const EPOCH_ORIGIN_UNIX = 0.0

function parse_args(argv)
    out = ""
    epochs = DEFAULT_EPOCHS
    step = DEFAULT_STEP_DAYS
    i = 1
    while i <= length(argv)
        a = argv[i]
        if a == "--out" && i < length(argv)
            out = argv[i+1]; i += 1
        elseif a == "--epochs" && i < length(argv)
            epochs = parse(Int, argv[i+1]); i += 1
        elseif a == "--step" && i < length(argv)
            step = parse(Float64, argv[i+1]); i += 1
        end
        i += 1
    end
    return out, epochs, step
end

"""
    presolve(epochs, step_days) -> Vector{NamedTuple}

Evaluate every world forward over `epochs` sky-day steps. Pure; no
state. Runs in parallel over the world list (Threads.@threads) so a
large sweep uses every core.
"""
function presolve(epochs::Int, step_days::Float64)
    ids = collect(keys(WORLDS))
    rows = Vector{Any}(undef, length(ids))
    Threads.@threads for k in eachindex(ids)
        id = ids[k]
        w = WORLDS[id]
        seed = WorldMath.world_seed_hex(WORLDS, id)
        epoch_rows = Vector{Any}(undef, epochs)
        for e in 0:(epochs - 1)
            unix = EPOCH_ORIGIN_UNIX + e * step_days * WorldMath.SKY_DAY_SECONDS
            sky = WorldMath.sky_epoch_days(unix)
            orb = WorldMath.orbit_position(w, sky)
            fav = WorldMath.window_favorability(w, WORLDS["moon"], sky)
            epoch_rows[e + 1] = Dict(
                "t" => unix,
                "day" => WorldMath.day_index_for(unix),
                "sky" => sky,
                "window" => WorldMath.window_index_for(unix),
                "orbit" => [orb[1], orb[2], orb[3]],
                "moon_fav" => fav,
            )
        end
        rows[k] = Dict("world" => id, "seed" => seed, "epochs" => epoch_rows)
    end
    return rows
end

function main()
    out, epochs, step = parse_args(ARGS)
    rows = presolve(epochs, step)
    io = out == "" ? stdout : open(out, "w")
    for r in rows
        println(io, JSON.json(r))
    end
    if out != ""
        close(io)
    end
    n = length(rows)
    println(stderr, "presolve: $n worlds x $epochs epochs (step $(step)d)")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
