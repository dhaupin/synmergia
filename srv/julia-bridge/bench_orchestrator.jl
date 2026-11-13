# bench_orchestrator.jl — the same core workload as
# game/tests/bench_multi_iso.gd (register N entities across axes, then
# Q multi-axis intersections), so the two numbers are comparable.
#
# Run: julia --project=. bench_orchestrator.jl
include("orchestrator.jl")
using .MultiIso
using Random

const N = 20000
const Q = 5000

function main()
    orch = MultiIso.Orchestrator()
    # Deterministic arithmetic placement (identical in bench_multi_iso.gd)
    # so the query totals cross-check as a correctness signal.
    for i in 0:(N - 1)
        e = MultiIso.Entity(
            id = "e$i",
            spatial_vertex = i % 12,
            faction_id = (i * 7) % 100,
            social_group = (i * 3) % 50,
        )
        MultiIso.register!(orch, e)
    end

    total = 0
    # Warm up (compile the query path) before timing.
    for _ in 1:200
        total += length(MultiIso.intersect(orch;
            spatial = MultiIso.spatial_at(orch, 0),
            faction = MultiIso.faction_eq(orch, 0)))
    end
    total = 0

    t0 = time_ns()
    for q in 0:(Q - 1)
        v = q % 12
        f = q % 100
        r = MultiIso.intersect(orch;
            spatial = MultiIso.spatial_at(orch, v),
            faction = MultiIso.faction_eq(orch, f))
        total += length(r)
    end
    t1 = time_ns()

    println("JULIA_USEC ", div(t1 - t0, 1000), " total=", total, " n=", N, " q=", Q)
end

main()
