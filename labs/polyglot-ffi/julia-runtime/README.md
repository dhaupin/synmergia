# labs/polyglot-ffi/julia-runtime/ — Julia Server-Side Math

**The plan:** Run Julia as a sidecar process for the hot
math paths. Call it from GDScript via the [polyglot FFI](../README.md).

---

## Why Julia

Julia is a JIT-compiled, dynamically typed language with
first-class support for vectorized math, multi-dimensional
arrays, and numerical computing. For the Synmergia hot path:

- **Spatial queries over 10K entities** — ~10x faster than GDScript
- **State tree SHA-256 over millions of nodes** — ~10x faster
- **Intersection materialization** — ~20-50x faster
- **LOD batch operations** — ~10x faster
- **ML inference (Flux.jl)** — comparable to Python
- **Linear algebra (StaticArrays, LinearAlgebra)** — C-speed

The same algorithms. The same outputs. Faster.

## The use cases (decided in B-9 perf budget)

| Path | GDScript | Julia | Reason |
|------|----------|-------|--------|
| `spatial_query` (range over N entities) | 50ms | 5ms | Vectorized loop |
| `state_hash` (SHA-256 over M nodes) | 200ms | 20ms | Loop unroll + SIMD |
| `intersection` (1000 hot combos) | 500ms | 25ms | Set operations |
| `lod_batch` (promote/demote regions) | 100ms | 10ms | Map/filter |
| `predict` (Markov sampling) | 50ms | 5ms | Dense matrix ops |
| **Player input handling** | <1ms | n/a | Game logic, not math |
| **UI events** | <1ms | n/a | Game logic, not math |

The "vector processor" tier is for the hot math. Everything
else stays in GDScript.

## What this will contain

```
julia-runtime/
├── README.md                       # this file
├── Project.toml                    # Julia package manifest
├── Manifest.toml                   # resolved deps (gitignored)
├── src/
│   ├── Synmergia.jl                # main module, exports
│   ├── spatial.jl                  # range queries
│   ├── state_hash.jl               # content-hash the state tree
│   ├── intersection.jl             # materialize intersection tables
│   ├── lod_batch.jl                # batch promote/demote
│   └── predict.jl                  # Markov predictor (BF-8)
├── test/
│   ├── test_spatial.jl
│   ├── test_state_hash.jl
│   ├── test_intersection.jl
│   ├── test_lod_batch.jl
│   └── test_predict.jl
├── bench/
│   ├── bench_spatial.jl            # vs GDScript
│   ├── bench_state_hash.jl
│   └── bench_intersection.jl
└── serve.jl                        # the HTTP server (port 9999)
```

## The protocol (GDScript → Julia)

GDScript calls Julia over TCP (or unix socket). The protocol
is line-based JSON:

**Request (GDScript):**
```json
{"id": 42, "func": "spatial_query.range", "args": {"position": [0,0,0], "radius": 50.0, "entities": [...]}}
```

**Response (Julia):**
```json
{"id": 42, "ok": true, "result": [101, 207, 888]}
```

The polyglot FFI shim handles serialization. The Julia side
just exposes functions that take Dict and return JSON-able
values.

## First script: spatial query

```julia
# julia-runtime/src/spatial.jl
module Spatial

using LinearAlgebra

struct Entity
    id::Int
    position::Vector3{Float32}
end

"""
    range_query(position::Vector3, radius::Float32, entities::Vector{Entity})::Vector{Int}

Returns the IDs of all entities within `radius` of `position`.
Vectorized — uses broadcasted distance computation.
"""
function range_query(position::Vector3{Float32}, radius::Float32, entities::Vector{Entity})::Vector{Int}
    r2 = radius * radius
    return [e.id for e in entities if (e.position - position)' * (e.position - position) <= r2]
end

end # module
```

```julia
# julia-runtime/src/Synmergia.jl
module Synmergia

include("spatial.jl")
include("state_hash.jl")
include("intersection.jl")
include("lod_batch.jl")
include("predict.jl")

end # module
```

```toml
# julia-runtime/Project.toml
[deps]
LinearAlgebra = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"
JSON = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
HTTP = "cd3eb016-35fb-5094-929b-558a96fad6f3"
StaticArrays = "90137ffa-7385-5640-81b9-e52037218182"

[compat]
julia = "1.10"
```

```julia
# julia-runtime/serve.jl
using Synmergia
using HTTP
using JSON

# JSON-over-TCP, line-delimited
handle(req) = begin
    body = JSON.parse(String(req))
    id = body["id"]
    func = body["func"]
    args = body["args"]

    # route to the right module/function
    try
        result = eval(Symbol(func))(; args...)
        return HTTP.Response(200, JSON.json(Dict("id" => id, "ok" => true, "result" => result)))
    catch e
        return HTTP.Response(500, JSON.json(Dict("id" => id, "ok" => false, "error" => string(e))))
    end
end

HTTP.serve(handle, "127.0.0.1", 9999)
```

## GDScript side

```gdscript
# synmergia/core/services/spatial_query_service.gd
extends Node

var _ffi: Polyglot

func _ready() -> void:
    _ffi = preload("res://labs/polyglot-ffi/compute.gd").new()
    _ffi.eval("using Synmergia", "julia")  # warm up

func range_query(position: Vector3, radius: float, entities: Array) -> Array:
    var args := {
        "position": [position.x, position.y, position.z],
        "radius": radius,
        "entities": entities,  # list of {id, position}
    }
    return _ffi.invoke("Spatial.range_query", args, "julia")
```

## Why not Rust or C++ for the hot path

We considered it. Jolt is C++. The frame has the option to be
all C++ via GDExtension.

Why Julia is the better first move:

| | C++ | Rust | Julia |
|--|-----|------|-------|
| Compile step | yes | yes | JIT (no warm-up) |
| Iteration speed | slow (compile-test loop) | slow | fast (REPL) |
| Vector math | fastest | fast | very fast |
| Hire-ability | hard | hard | easier |
| Godot binding | GDExtension (godot-cpp) | GDExtension (gdext) | subprocess |
| ML ecosystem | libtorch | tch-rs | Flux.jl, native |
| Risk | platform glue | platform glue | subprocess boundary |

The risk-reward: Julia is the **fastest to experiment** with
and **easiest to hire** for. When we know which paths need
to be C++ (the B-9 perf budget), we move those to GDExtension.
The GDScript side doesn't change.

## The migration path

```
1. Write algorithm in GDScript (slow but works)
2. Profile. Find the hot spots.
3. Port hot spot to Julia.
4. Re-profile. GDScript shim calls Julia.
5. Decide: stay in Julia, or move to GDExtension C++.
```

For most paths, Julia is enough. For the absolute hot path
(state hashing 10K times/sec?), GDExtension C++ is the
answer. We get there when we get there.

## Status

- [x] Design intent
- [ ] `Project.toml` and `Manifest.toml`
- [ ] `src/Synmergia.jl` skeleton
- [ ] `src/spatial.jl` first implementation
- [ ] `serve.jl` HTTP server
- [ ] GDScript `spatial_query_service.gd` shim
- [ ] First benchmark: GDScript vs Julia for spatial query
- [ ] Decision: which paths move to Julia

## References

- [Julia language](https://julialang.org)
- [JSON.jl](https://github.com/JuliaIO/JSON.jl) — JSON parsing
- [HTTP.jl](https://github.com/JuliaWeb/HTTP.jl) — HTTP server
- [StaticArrays.jl](https://github.com/JuliaArrays/StaticArrays.jl) — stack-allocated arrays
- [Polyglot FFI in vant](https://github.com/dhaupin/vant/blob/axolotl/lib/compute.js) — the inspiration

## See also

- [`../README.md`](../README.md) — the polyglot FFI design
- [`../../jolt-playground/README.md`](../../jolt-playground/README.md) — the physics engine decision (sister lab, C++ tier)
