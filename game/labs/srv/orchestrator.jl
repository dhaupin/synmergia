"""
orchestrator.jl — Julia multi-iso orchestrator (frame primitive)

Upgraded from the Python prototype and placed in the canonical
`labs/multi-iso/srv/` slot per the /labs/ convention:
  https://github.com/dhaupin/synmergia/blob/main/docs/architecture/labs-organization.md

This is a pure Julia orchestrator with no external dependencies.
The Godot game consumes it via the HTTP server wrapper (server.jl)
or the polyglot FFI (labs/polyglot-ffi/).

Usage:
    julia --project=. server.jl    # Start HTTP API server
    julia --project=. orchestrator.jl  # Run self-tests

Design:
    Every entity has one NSC-9 code per axis.
    Each axis is its own hash-set of entity IDs.
    Multi-axis query = set intersection = O(min).
    See docs/architecture/multi-iso-frame.md for the full design.
"""
module Orchestrator

using UUIDs

# ============================================================
# NSC-9 Encoding
# ============================================================

"""
    nsc9_encode(facility::Int, axis::Int, sequence::Int) -> String

Encode an NSC-9 code. Format: 9-AAA-BBB-CCCCCC
- AAA: facility (0-999)
- BBB: axis (0-999)
- CCCCCC: sequence (0-999999)
"""
function nsc9_encode(facility::Int, axis::Int, sequence::Int)::String
    return "9-$(lpad(facility, 3, '0'))-$(lpad(axis, 3, '0'))-$(lpad(sequence, 6, '0'))"
end

"""
    nsc9_parse(code::String) -> NamedTuple

Parse an NSC-9 code into its components.
"""
function nsc9_parse(code::String)
    parts = split(code, "-")
    @assert length(parts) == 4 "Invalid NSC-9 code: $code"
    @assert parts[1] == "9" "Invalid prefix: $(parts[1])"
    return (
        prefix = 9,
        facility = parse(Int, parts[2]),
        axis = parse(Int, parts[3]),
        sequence = parse(Int, parts[4])
    )
end

# ============================================================
# Axis Constants
# ============================================================

# Spatial axis (icosahedral vertices): 1-12
spatial_axis(v::Int) = 1 + v

# Faction axis: 100-199 (100 factions)
faction_axis(f::Int) = 100 + f

# Temporal axes: 200-299 (sub-axes, sequence holds the value)
const TEMPORAL_YEAR   = 200
const TEMPORAL_SEASON = 201
const TEMPORAL_MONTH  = 202
const TEMPORAL_HOUR   = 203

# Social axis: 300-399
social_axis(s::Int) = 300 + s

# Game axis: 400-499
game_axis(g::Int) = 400 + g

# ============================================================
# Entity
# ============================================================

"""
    Entity

A game entity registered on all axes.
Each axis has its own NSC-9 code computed from the entity's properties.
"""
mutable struct Entity
    id::String
    facility::Int
    spatial_vertex::Int
    faction_id::Int
    birth_year::Int
    social_group::Int
    game_class::Int
    nsc9::Dict{Symbol, String}
end

"""
    Entity(; id, facility, spatial_vertex, faction_id, birth_year, social_group, game_class)

Construct an Entity with auto-generated NSC-9 codes for all axes.
"""
function Entity(;
    id::String = string(UUIDs.uuid4()),
    facility::Int = 1,
    spatial_vertex::Int = 0,
    faction_id::Int = 0,
    birth_year::Int = 2026,
    social_group::Int = 0,
    game_class::Int = 0
)
    seq(s::String) = hash(id * s) % 1_000_000

    nsc9 = Dict{Symbol, String}(
        :spatial          => nsc9_encode(facility, spatial_axis(spatial_vertex), seq("s")),
        :faction          => nsc9_encode(facility, faction_axis(faction_id), seq("f")),
        :temporal_year    => nsc9_encode(facility, TEMPORAL_YEAR, birth_year - 1900),
        :temporal_season  => nsc9_encode(facility, TEMPORAL_SEASON, birth_year % 4),
        :social           => nsc9_encode(facility, social_axis(social_group), seq("o")),
        :game             => nsc9_encode(facility, game_axis(game_class), seq("g"))
    )

    Entity(id, facility, spatial_vertex, faction_id, birth_year, social_group, game_class, nsc9)
end

# ============================================================
# Orchestrator
# ============================================================

"""
    Orchestrator

The multi-iso orchestrator. One hash-set per axis.
Query = set intersection = O(min(|axis|)).
"""
mutable struct Orchestrator
    axes::Dict{Symbol, Dict{String, String}}  # axis_name -> entity_id -> nsc9_code
    entities::Dict{String, Entity}
end

function Orchestrator()
    Orchestrator(
        Dict{Symbol, Dict{String, String}}(
            :spatial         => Dict{String, String}(),
            :faction         => Dict{String, String}(),
            :temporal_year   => Dict{String, String}(),
            :temporal_season => Dict{String, String}(),
            :social          => Dict{String, String}(),
            :game            => Dict{String, String}()
        ),
        Dict{String, Entity}()
    )
end

"""
    register!(orch::Orchestrator, entity::Entity)

Register an entity on all axes.
"""
function register!(orch::Orchestrator, entity::Entity)
    orch.entities[entity.id] = entity
    for (axis_name, code) in entity.nsc9
        orch.axes[axis_name][entity.id] = code
    end
end

# ---- Single-axis queries ----

"""
    spatial_at(orch::Orchestrator, vertex::Int) -> Set{String}

All entity IDs at a given icosahedral vertex (0-11).
"""
function spatial_at(orch::Orchestrator, vertex::Int)::Set{String}
    axis = spatial_axis(vertex)
    return Set([eid for (eid, code) in orch.axes[:spatial]
                if nsc9_parse(code).axis == axis])
end

"""
    faction_eq(orch::Orchestrator, faction_id::Int) -> Set{String}

All entity IDs in a given faction.
"""
function faction_eq(orch::Orchestrator, faction_id::Int)::Set{String}
    axis = faction_axis(faction_id)
    return Set([eid for (eid, code) in orch.axes[:faction]
                if nsc9_parse(code).axis == axis])
end

"""
    social_eq(orch::Orchestrator, group::Int) -> Set{String}

All entity IDs in a given social group.
"""
function social_eq(orch::Orchestrator, group::Int)::Set{String}
    axis = social_axis(group)
    return Set([eid for (eid, code) in orch.axes[:social]
                if nsc9_parse(code).axis == axis])
end

# ---- Multi-axis intersection ----

"""
    intersect(orch::Orchestrator; spatial=nothing, faction=nothing,
              social=nothing, temporal_year=nothing, kwargs...) -> Set{String}

Intersect any number of axis sets.
Sets are sorted by size; the smallest set drives the iteration — O(min).
"""
function intersect(orch::Orchestrator;
    spatial=nothing,
    faction=nothing,
    social=nothing,
    temporal_year=nothing,
    kwargs...
)
    sets = []
    !isnothing(spatial)        && push!(sets, spatial)
    !isnothing(faction)         && push!(sets, faction)
    !isnothing(social)         && push!(sets, social)
    !isnothing(temporal_year)  && push!(sets, temporal_year)
    for (key, val) in kwargs
        if !isnothing(val)
            push!(sets, val)
        end
    end
    isempty(sets) && return Set(keys(orch.entities))

    sort!(sets, by=length)
    result = copy(sets[1])
    for s in sets[2:end]
        result = intersect(result, s)
        isempty(result) && break
    end
    return result
end

"""
    query(orch::Orchestrator; kwargs...) -> Vector{Entity}

Resolve an intersection back to Entity objects.
"""
function query(orch::Orchestrator; kwargs...)
    ids = intersect(orch; kwargs...)
    return [orch.entities[i] for i in ids if haskey(orch.entities, i)]
end

# ============================================================
# Statistics
# ============================================================

function stats(orch::Orchestrator)
    println("Orchestrator stats:")
    println("  Total entities: $(length(orch.entities))")
    for axis in keys(orch.axes)
        println("  $(axis): $(length(orch.axes[axis])) codes")
    end
end

end  # module
