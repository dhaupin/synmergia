# world_batch.jl — the presolve tier batch driver (Facet 2).
#
# Evaluates the closed-form world lattice forward over N sky-day steps
# and emits ONE flat text record per epoch, so the GDScript frame can
# re-derive a sample and assert equality (tests/test_julia_presolve.gd).
#
# This is the JSON-free sibling of presolve.jl. The pre-solve math is
# stdlib-only (worldmath.jl -> SHA), so the batch runs even where the
# JSON/HTTP pkgimages cannot build. Same fields, same order, one line.
#
# Usage:
#     julia --project=. world_batch.jl [--epochs N] [--step D]
#
# Output (stdout):
#     WORLD <id> <seed_hex>
#     EPOCH <world> <t> <day> <sky> <window> <orbx> <orby> <orbz> <fav>
#     END <epochs> <step>
include("worldmath.jl")
using .WorldMath

## The S16.1 lattice, from game/data/worlds/*.tres (kept in sync with
## presolve.jl's table -- both mirror the same declarations).
const WORLDS = Dict{String, WorldMath.WorldDecl}(
    "main" => WorldMath.WorldDecl("main", "", 0.0, 0.0, 0.0, 0.0),
    "moon" => WorldMath.WorldDecl("moon", "main", 90000.0, 8.0, 0.7, 0.12),
    "underworld" => WorldMath.WorldDecl("underworld", "main", 0.0, 0.0, 0.0, 0.0),
)

const WORLD_IDS = ["main", "moon", "underworld"]
const EPOCH_ORIGIN_UNIX = 0.0

function main()
    epochs = 365
    step = 1.0
    args = ARGS
    i = 1
    while i <= length(args)
        if args[i] == "--epochs"; epochs = parse(Int, args[i+1]); i += 2
        elseif args[i] == "--step"; step = parse(Float64, args[i+1]); i += 2
        else; i += 1
        end
    end

    for id in WORLD_IDS
        println("WORLD ", id, " ", WorldMath.world_seed_hex(WORLDS, id))
    end
    moon = WORLDS["moon"]
    for id in WORLD_IDS
        w = WORLDS[id]
        for e in 0:(epochs - 1)
            unix = EPOCH_ORIGIN_UNIX + e * step * WorldMath.SKY_DAY_SECONDS
            sky = WorldMath.sky_epoch_days(unix)
            orb = WorldMath.orbit_position(w, sky)
            fav = WorldMath.window_favorability(w, moon, sky)
            println("EPOCH ", id, " ", unix, " ", WorldMath.day_index_for(unix),
                    " ", sky, " ", WorldMath.window_index_for(unix), " ",
                    orb[1], " ", orb[2], " ", orb[3], " ", fav)
        end
    end
    println("END ", epochs, " ", step)
end

main()
