"""
worldmath.jl — pure closed-form world derivations, ported to Julia.

These are the frame's "a world is a function" primitives
(labs/prd-industry-labs.md T1/T2), the same math as:

  game/core/frame/kv/seed_chain.gd        -> derive_seed
  game/core/frame/srv/world_registry.gd   -> world_seed / orbit_position
                                             / window_favorability
  game/core/services/sign_service.gd      -> day_index_for / sky_epoch_days
                                             / window_index_for

Ported so the pre-solve tier can evaluate a world forward at many
epochs in parallel (the "pre-solves races" work) without booting
Godot. The GDScript remains authoritative; this module is validated
byte-for-byte against it by tests/test_julia_presolve.gd.
"""
module WorldMath

using SHA

const TAU = 2 * pi

## The one constant of the universe (world_registry.UNIVERSE_SEED_HEX):
## "synmergia" (9 ASCII bytes) + 23 zero bytes = 32.
const UNIVERSE_SEED_HEX = "73796e6d65726769610000000000000000000000000000000000000000000000"

## A Concord sky day is 7200 real seconds (sign_service.SKY_DAY_SECONDS).
const SKY_DAY_SECONDS = 7200.0

## Window length within a UTC day (sign_service.WINDOW_SECONDS).
const WINDOW_SECONDS = 6 * 3600

sha256(data::AbstractVector{UInt8}) = SHA.sha256(collect(data))

hex_to_bytes(hex::AbstractString)::Vector{UInt8} =
    [parse(UInt8, hex[i:i+1]; base = 16) for i in 1:2:length(hex)]

bytes_to_hex(b::AbstractVector{UInt8})::String =
    join(string.(b; base = 16, pad = 2))

universe_seed()::Vector{UInt8} = hex_to_bytes(UNIVERSE_SEED_HEX)

"""
    derive_seed(stack, path) -> Vector{UInt8}

Bottom-up fold: acc starts as the path bytes, then each stack entry
(from the top down) is prepended and hashed. An empty stack still
finishes with one hash so the output is 32 bytes.
Mirrors SeedChain.derive_seed exactly.
"""
function derive_seed(stack::Vector{Vector{UInt8}}, path::AbstractString)::Vector{UInt8}
    acc = Vector{UInt8}(codeunits(path))
    for i in length(stack):-1:1
        acc = sha256(vcat(stack[i], acc))
    end
    if isempty(stack)
        acc = sha256(acc)
    end
    return acc
end

## A world declaration: only the fields the derivations read.
struct WorldDecl
    id::String
    parent_world::String
    orbit_radius_m::Float64
    orbit_period_days::Float64
    orbit_phase_rad::Float64
    orbit_inclination_rad::Float64
end

## world_data.seed_path(): "world:<id>" or "world:<parent>/subworld:<id>".
function seed_path(w::WorldDecl)::String
    return w.parent_world == "" ? "world:" * w.id :
           "world:" * w.parent_world * "/subworld:" * w.id
end

"""
    world_seed(worlds::Dict{String,WorldDecl}, id) -> Vector{UInt8}

SeedChain through the universe root and the world's nesting path.
Subworlds inherit their primary's domain (the parent folds first).
"""
function world_seed(worlds::Dict{String,WorldDecl}, id::AbstractString)::Vector{UInt8}
    w = worlds[id]
    stack = Vector{Vector{UInt8}}([universe_seed()])
    if w.parent_world != "" && haskey(worlds, w.parent_world)
        push!(stack, world_seed(worlds, w.parent_world))
    end
    return derive_seed(stack, seed_path(w))
end

world_seed_hex(worlds, id) = bytes_to_hex(world_seed(worlds, id))

## Closed-form orbital angle (rad); static bodies return 0.
_orbit_angle(w::WorldDecl, epoch::Float64)::Float64 =
    w.orbit_period_days <= 0.0 ? 0.0 :
    TAU * (epoch / w.orbit_period_days) + w.orbit_phase_rad

"""
    orbit_position(w, epoch) -> NTuple{3,Float64}

World-local position at sky-epoch `epoch`. Returns (0,0,0) for a
static world. Inclination rotates the orbital plane about the X axis.
Mirrors WorldRegistry.orbit_position.
"""
function orbit_position(w::WorldDecl, epoch::Float64)::NTuple{3,Float64}
    if w.orbit_radius_m <= 0.0 || w.orbit_period_days <= 0.0
        return (0.0, 0.0, 0.0)
    end
    a = _orbit_angle(w, epoch)
    x = cos(a) * w.orbit_radius_m
    y = 0.0
    z = sin(a) * w.orbit_radius_m
    inc = w.orbit_inclination_rad
    if abs(inc) > 0.0001
        # Vector3.rotated((1,0,0), inc): y' = y cos - z sin; z' = y sin + z cos
        c, s = cos(inc), sin(inc)
        y, z = y * c - z * s, y * s + z * c
    end
    return (x, y, z)
end

"""
    window_favorability(a, b, epoch) -> Float64

Phase-distance favorability in [0,1]; 0 = aligned, 1 = opposite.
Mirrors WorldRegistry.window_favorability for two declared worlds.
"""
function window_favorability(a::WorldDecl, b::WorldDecl, epoch::Float64)::Float64
    ab = a.orbit_radius_m > 0.0 ? a : b
    pivot = ab === a ? b : a
    if ab === pivot
        return 1.0
    end
    if ab.orbit_radius_m <= 0.0 && pivot.orbit_radius_m <= 0.0
        return 1.0
    end
    diff = abs(mod(_orbit_angle(ab, epoch) - _orbit_angle(pivot, epoch), TAU))
    if diff > pi
        diff = TAU - diff
    end
    return clamp(diff / pi, 0.0, 1.0)
end

## sign_service.day_index_for: UTC day index of a unix timestamp.
day_index_for(unix::Float64)::Int = Int(floor(unix / 86400.0))

## sign_service.sky_epoch_days: fractional SKY days.
sky_epoch_days(unix::Float64)::Float64 = unix / SKY_DAY_SECONDS

## sign_service.window_index_for: 0..3 window within the UTC day.
window_index_for(unix::Float64)::Int =
    Int(floor(mod(unix, 86400.0) / WINDOW_SECONDS))

end  # module
