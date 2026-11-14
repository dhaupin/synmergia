# prop_presolve.jl — emit the FULL planet's prop specs as a committed
# presolve artifact (labs/prd-perf-bridges.md Facet 3, live consumer).
#
# prop_batch.jl proves the SPEC-LEVEL parity and times the derive; this
# script writes the ARTIFACT the frame loads at boot: every face's rock +
# boulder specs, one line per spec, plus a header (seed, ruleset) and a
# trailing checksum. `core/world/presolve_props.gd` loads it, VALIDATES it
# against the live law (per-face counts + direction tolerance + checksum),
# and serves it through `TerrainProvider` -- so the frame skips the PCG32
# derivation (measured 17.7x on the derive) and a CLIENT can load the same
# artifact instead of re-deriving. A mismatch falls back to the live law.
#
# Usage:
#     julia --project=. prop_presolve.jl [--seed HEX] [--out PATH]
# Default seed is the frame's boot world seed; default out is stdout.
include("propmath.jl")
using .PropMath

hexb(h::AbstractString) = UInt8[parse(UInt8, h[i:i+1]; base = 16) for i in 1:2:length(h)]

function main()
    seed_hex = "73616c7463726f776e2d69736c652d34"  # "saltcrown-isle-4"
    out_path = ""
    args = ARGS
    i = 1
    while i <= length(args)
        if args[i] == "--seed"; seed_hex = args[i+1]; i += 2
        elseif args[i] == "--out"; out_path = args[i+1]; i += 2
        else; i += 1
        end
    end

    seed = hexb(seed_hex)
    io = IOBuffer()
    total_r = 0
    total_b = 0
    checksum = 0.0

    println(io, "SYNMERGIA PRESOLVE props 1")
    println(io, "SEED ", seed_hex)
    println(io, "RULESET ", PropMath.RULESET_VERSION)
    println(io, "FACES 20")

    for f in 0:19
        rocks = PropMath.rock_specs(seed, f)
        boulders = PropMath.boulder_specs(seed, f)
        println(io, "FACE ", f, " ROCKS ", length(rocks), " BOULDERS ", length(boulders))
        for s in rocks
            println(io, "R ", s.dir[1], " ", s.dir[2], " ", s.dir[3], " ", s.scale, " ", s.yaw)
            checksum += s.dir[1] + s.dir[2] + s.dir[3] + s.scale + s.yaw
        end
        for b in boulders
            println(io, "B ", b.dir[1], " ", b.dir[2], " ", b.dir[3], " ", b.radius, " ", b.yaw)
            checksum += b.dir[1] + b.dir[2] + b.dir[3] + b.radius + b.yaw
        end
        total_r += length(rocks)
        total_b += length(boulders)
    end
    println(io, "END ", total_r, " ", total_b, " ", checksum)

    text = String(take!(io))
    if out_path == ""
        print(text)
    else
        open(out_path, "w") do fh
            write(fh, text)
        end
        println(stderr, "wrote ", out_path, " (", total_r, " rocks, ", total_b, " boulders)")
    end
end

main()
