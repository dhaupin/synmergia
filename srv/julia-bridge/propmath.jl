"""
propmath.jl — pure-Julia mirror of TerrainGen's rock/boulder spec scatter.

The frame's prop scatter (`TerrainGen.rock_specs` / `boulder_specs`) is a
pure function of `(world_seed, face)`: a fresh PCG32 RNG seeded from the
face's SeedChain-derived bytes, then a bounded barycentric draw per site.
That is exactly the offline/batch shape the perf-bridge law wants — derive
a whole planet's worth of specs in one process.

This module mirrors the spec DERIVATION 1:1 from
`game/scenes/worlds/terrain_gen.gd`, using `pcg32.jl` for the RNG stream
and `terrainmath.jl` for the raw heightfield the DRY-REDRAW test reads.

Scope note (measured): the dry test in GDScript reads the CARVED height
(`terrain_height`), but across 8 world seeds x ~590 specs (0 divergences)
the RAW field classifies every spec identically — the carve only fires
where the hydro gates hold, and rock/boulder draws do not land there. So
this raw-field port reproduces the specs exactly; the parity receipt
`tests/test_julia_prop_batch.gd` re-checks that claim against the frame.

The GDScript frame stays authoritative.
"""
module PropMath

using SHA
include("pcg32.jl")
include("terrainmath.jl")
using .PCG32
using .TerrainMath

const RULESET_VERSION = "terrain_v7"
const SPAWN_CENTER = (1.0, 0.0, 0.0)
const SPAWN_CLEAR_ANG = 0.012
const TAU = 6.283185307179586

# ---------------------------------------------------------------- icosahedron
# The 12 unit-icosahedron vertices (Icosahedral.VERTICES) and the 20
# spherical-triangle faces (center + outward-wound vertex indices) from
# IcosahedralFaces. Captured verbatim from the frame (see
# tests/test_julia_prop_batch.gd, which re-derives and asserts them).
include("prop_faces.jl")

"""Unit direction of vertex `i` (normalize the raw golden-rectangle vertex).
`i` is the frame's 0-based index; Julia arrays are 1-based, hence `i + 1`."""
function vertex_dir(i::Int)
    return TerrainMath.norm3(VERTS_RAW[i + 1])
end

"""The three unit vertex dirs of a face, in outward-wound order."""
function face_vertex_dirs(face::Int)
    _, idx = FACE_TABLE[face + 1]
    return (vertex_dir(idx[1]), vertex_dir(idx[2]), vertex_dir(idx[3]))
end

function face_center(face::Int)
    return FACE_TABLE[face + 1][1]
end

# ---------------------------------------------------------------- seed chain
"""SHA-256 of `stack[i] + acc` folded bottom-up, then a final hash if the
stack is empty — a 1:1 mirror of SeedChain.derive_seed."""
function derive_seed(stack::Vector{Vector{UInt8}}, path::AbstractString)
    acc = Vector{UInt8}(codeunits(path))
    for i in length(stack):-1:1
        acc = sha256(vcat(stack[i], acc))
    end
    if isempty(stack)
        acc = sha256(acc)
    end
    return acc
end

function face_seed_bytes(world_seed::Vector{UInt8}, face::Int)
    return derive_seed([world_seed], "terrain/" * RULESET_VERSION * "/face/" * string(face))
end

function boulder_seed_bytes(world_seed::Vector{UInt8}, face::Int)
    return derive_seed([world_seed], "terrain/" * RULESET_VERSION * "/boulders/" * string(face))
end

"""Fold 32 seed bytes into one 64-bit RNG seed (the frame's acc chain)."""
function fold_seed(bytes::Vector{UInt8})
    acc = Int64(0)
    for b in bytes
        acc = mod(acc * 256 + Int64(b), 9007199254740991)
    end
    return acc
end

"""The barycentric site draw: center*0.25 + v*0.35 + v2*0.40, normalized."""
function barycentric(center, v, v2)
    d = (center[1] * 0.25 + v[1] * 0.35 + v2[1] * 0.40,
         center[2] * 0.25 + v[2] * 0.35 + v2[2] * 0.40,
         center[3] * 0.25 + v[3] * 0.35 + v2[3] * 0.40)
    return TerrainMath.norm3(d)
end

# ---------------------------------------------------------------- specs
"""One rock spec: dir (unit), scale, yaw. Mirrors rock_specs()."""
struct RockSpec
    dir::NTuple{3,Float64}
    scale::Float64
    yaw::Float64
end

"""One boulder spec: dir (unit), radius, yaw. Mirrors boulder_specs()."""
struct BoulderSpec
    dir::NTuple{3,Float64}
    radius::Float64
    yaw::Float64
end

function rock_specs(world_seed::Vector{UInt8}, face::Int)
    bytes = face_seed_bytes(world_seed, face)
    rng = PCG32.Rng(fold_seed(bytes))
    count = PCG32.randi_range(rng, 20, 34)
    center = face_center(face)
    vdirs = face_vertex_dirs(face)
    sea = TerrainMath.sea_level(world_seed)
    specs = RockSpec[]
    for _ in 1:count
        i = PCG32.randi_range(rng, 0, 2) + 1
        j = PCG32.randi_range(rng, 0, 2) + 1
        v = vdirs[i]
        v2 = vdirs[j]
        d = barycentric(center, v, v2)
        for _t in 1:4
            if TerrainMath.angle_to(d, SPAWN_CENTER) >= SPAWN_CLEAR_ANG
                break
            end
            i = PCG32.randi_range(rng, 0, 2) + 1
            j = PCG32.randi_range(rng, 0, 2) + 1
            v = vdirs[i]
            v2 = vdirs[j]
            d = barycentric(center, v, v2)
        end
        for _t in 1:6
            if TerrainMath.natural_raw(d, world_seed) >= sea - 0.6
                break
            end
            i = PCG32.randi_range(rng, 0, 2) + 1
            j = PCG32.randi_range(rng, 0, 2) + 1
            v = vdirs[i]
            v2 = vdirs[j]
            d = barycentric(center, v, v2)
        end
        scale = PCG32.rand_f32_range(rng, 1.0f0, 2.2f0)
        yaw = PCG32.rand_f32_range(rng, 0.0f0, Float32(TAU))
        push!(specs, RockSpec(d, Float64(scale), Float64(yaw)))
    end
    return specs
end

function boulder_specs(world_seed::Vector{UInt8}, face::Int)
    bytes = boulder_seed_bytes(world_seed, face)
    rng = PCG32.Rng(fold_seed(bytes))
    count = 2 + PCG32.randi_range(rng, 0, 1)
    center = face_center(face)
    vdirs = face_vertex_dirs(face)
    sea = TerrainMath.sea_level(world_seed)
    specs = BoulderSpec[]
    for _ in 1:count
        i = PCG32.randi_range(rng, 0, 2) + 1
        j = PCG32.randi_range(rng, 0, 2) + 1
        v = vdirs[i]
        v2 = vdirs[j]
        d = barycentric(center, v, v2)
        for _t in 1:4
            if TerrainMath.angle_to(d, SPAWN_CENTER) >= SPAWN_CLEAR_ANG
                break
            end
            i = PCG32.randi_range(rng, 0, 2) + 1
            j = PCG32.randi_range(rng, 0, 2) + 1
            v = vdirs[i]
            v2 = vdirs[j]
            d = barycentric(center, v, v2)
        end
        for _t in 1:6
            if TerrainMath.natural_raw(d, world_seed) >= sea - 0.6
                break
            end
            i = PCG32.randi_range(rng, 0, 2) + 1
            j = PCG32.randi_range(rng, 0, 2) + 1
            v = vdirs[i]
            v2 = vdirs[j]
            d = barycentric(center, v, v2)
        end
        radius = PCG32.rand_f32_range(rng, 3.5f0, 6.5f0)
        yaw = PCG32.rand_f32_range(rng, 0.0f0, Float32(TAU))
        push!(specs, BoulderSpec(d, Float64(radius), Float64(yaw)))
    end
    return specs
end

end # module PropMath
