# prop_batch.jl — the prop-scatter pre-solve batch driver (Facet 3).
#
# Derives EVERY face's rock + boulder specs in ONE process, so the frame
# pays a single round-trip (or, offline, zero) instead of deriving each
# face's PCG32 stream in GDScript. The GDScript bench
# (`dev_temp/probes/bench_prop.gd`) derives the IDENTICAL set, so the two
# timings are comparable and the two spec vectors cross-check.
#
# Usage:
#     julia --project=. prop_batch.jl [--seed HEX] [--json] [--parity]
# `--parity` emits one `P <face> <rock_n> <rock_sum> <boulder_n> <boulder_sum>`
# line per face; tests/test_julia_prop_batch.gd computes the same from the
# frame and asserts equality (the spec-level cross-check).
include("propmath.jl")
using .PropMath

hexb(h::AbstractString) = UInt8[parse(UInt8, h[i:i+1]; base = 16) for i in 1:2:length(h)]

function main()
    seed_hex = "73616c7463726f776e2d69736c652d34"  # "saltcrown-isle-4"
    json = false
    parity = false
    args = ARGS
    i = 1
    while i <= length(args)
        if args[i] == "--seed"; seed_hex = args[i+1]; i += 2
        elseif args[i] == "--json"; json = true; i += 1
        elseif args[i] == "--parity"; parity = true; i += 1
        else; i += 1
        end
    end

    seed = hexb(seed_hex)

    if parity
        for f in 0:19
            rn = 0; rs = 0.0
            for s in PropMath.rock_specs(seed, f)
                rn += 1
                rs += s.dir[1] + s.dir[2] + s.dir[3] + s.scale + s.yaw
            end
            bn = 0; bs = 0.0
            for b in PropMath.boulder_specs(seed, f)
                bn += 1
                bs += b.dir[1] + b.dir[2] + b.dir[3] + b.radius + b.yaw
            end
            println("P ", f, " ", rn, " ", rs, " ", bn, " ", bs)
        end
        return
    end

    # Warm up (compile the spec path) before timing.
    PropMath.rock_specs(seed, 0)
    PropMath.boulder_specs(seed, 0)

    t0 = time_ns()
    rocks = 0
    boulders = 0
    checksum = 0.0
    for f in 0:19
        for s in PropMath.rock_specs(seed, f)
            rocks += 1
            checksum += s.dir[1] + s.dir[2] + s.dir[3] + s.scale + s.yaw
        end
        for b in PropMath.boulder_specs(seed, f)
            boulders += 1
            checksum += b.dir[1] + b.dir[2] + b.dir[3] + b.radius + b.yaw
        end
    end
    t1 = time_ns()

    usec = div(t1 - t0, 1000)
    if json
        println("{\"usec\":", usec, ",\"rocks\":", rocks, ",\"boulders\":", boulders,
                ",\"checksum\":", checksum, "}")
    else
        println("JULIA_PROP_USEC ", usec, " rocks=", rocks, " boulders=", boulders,
                " checksum=", checksum)
    end
end

main()
