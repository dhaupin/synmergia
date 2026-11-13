"""
orchestrator.jl — Julia multi-iso orchestrator (HTTP sidecar)

Relocated 2026-09-30 to `srv/julia-bridge/` -- the bridge-service
slot (sibling of pg-bridge/ and redis-bridge/), NOT a Godot frame
primitive. The canonical-slot doc this file once cited
(docs/architecture/labs-organization.md) lives archived at
labs/archive/docs/architecture/.

This is a pure Julia orchestrator with no external dependencies.
The Godot game consumes it via the HTTP server wrapper (server.jl)
through MultiIsoService; the polyglot FFI (labs/polyglot-ffi/) is
the future replacement.

Usage:
    julia --project=. server.jl    # Start HTTP API server
    julia --project=. orchestrator.jl  # Run self-tests

Design:
    Every entity has one NSC-9 code per axis.
    Each axis is its own hash-set of entity IDs.
    Multi-axis query = set intersection = O(min).
    See docs/architecture/multi-iso-frame.md for the full design.
"""
module MultiIso

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
    seq(s::String) = Int(hash(id * s) % 1_000_000)

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

The multi-iso orchestrator. ONE inverted index: axis number -> set of
entity ids. Axis numbers are globally unique (spatial 1-12, faction
100-199, social 300-399, game 400-499), so a single dict keys them
all. A single-axis query is a dict lookup; a multi-axis query is a
set intersection over the smallest bucket (O(min)).
"""
mutable struct Orchestrator
    by_axis::Dict{Int, Set{String}}  # axis number -> entity ids
    entities::Dict{String, Entity}
end

function Orchestrator()
    Orchestrator(Dict{Int, Set{String}}(), Dict{String, Entity}())
end

"""
    register!(orch::Orchestrator, entity::Entity)

Register an entity on all axes. O(1) per axis.
"""
function register!(orch::Orchestrator, entity::Entity)
    orch.entities[entity.id] = entity
    for axis in (
        spatial_axis(entity.spatial_vertex),
        faction_axis(entity.faction_id),
        social_axis(entity.social_group),
        game_axis(entity.game_class),
        TEMPORAL_YEAR,
        TEMPORAL_SEASON,
    )
        push!(get!(orch.by_axis, axis, Set{String}()), entity.id)
    end
    return entity
end

_bucket(orch::Orchestrator, axis::Int)::Set{String} =
    get(orch.by_axis, axis, Set{String}())

"""
    unregister!(orch::Orchestrator, id) -> Bool

Remove an entity from every axis bucket. Returns false if the id was
not registered.
"""
function unregister!(orch::Orchestrator, id::AbstractString)::Bool
    if !haskey(orch.entities, id)
        return false
    end
    delete!(orch.entities, id)
    for bucket in values(orch.by_axis)
        delete!(bucket, id)
    end
    return true
end

# ---- Single-axis queries (O(1) dict lookups) ----

"""All entity IDs at a given icosahedral vertex (0-11)."""
spatial_at(orch::Orchestrator, vertex::Int)::Set{String} =
    _bucket(orch, spatial_axis(vertex))

"""All entity IDs in a given faction."""
faction_eq(orch::Orchestrator, faction_id::Int)::Set{String} =
    _bucket(orch, faction_axis(faction_id))

"""All entity IDs in a given social group."""
social_eq(orch::Orchestrator, group::Int)::Set{String} =
    _bucket(orch, social_axis(group))

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
    sets = Set{String}[]
    !isnothing(spatial)        && push!(sets, spatial)
    !isnothing(faction)        && push!(sets, faction)
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
        result = Base.intersect(result, s)
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
    println("  Axis buckets: $(length(orch.by_axis))")
end

# ============================================================
# Self-tests (run: julia --project=. orchestrator.jl)
# ============================================================

function run_self_tests()::Bool
    failures = Ref(0)
    check(name, cond) = (println(cond ? "  [OK]   $name" : "  [FAIL] $name"); if !cond; failures[] += 1; end)

    println("MultiIso orchestrator self-tests")

    # NSC-9 round-trip.
    code = nsc9_encode(7, 103, 42)
    check("nsc9_encode format", code == "9-007-103-000042")
    parsed = nsc9_parse(code)
    check("nsc9_parse facility", parsed.facility == 7)
    check("nsc9_parse axis", parsed.axis == 103)
    check("nsc9_parse sequence", parsed.sequence == 42)

    # Registration + single-axis queries.
    orch = Orchestrator()
    a = Entity(id = "a", facility = 1, spatial_vertex = 3, faction_id = 2, social_group = 5)
    b = Entity(id = "b", facility = 1, spatial_vertex = 3, faction_id = 9, social_group = 5)
    c = Entity(id = "c", facility = 1, spatial_vertex = 7, faction_id = 2, social_group = 1)
    for e in (a, b, c); register!(orch, e); end
    check("spatial_at returns set", spatial_at(orch, 3) == Set(["a", "b"]))
    check("faction_eq returns set", faction_eq(orch, 2) == Set(["a", "c"]))
    check("social_eq returns set", social_eq(orch, 5) == Set(["a", "b"]))

    # Multi-axis intersection = O(min).
    r = intersect(orch; spatial = spatial_at(orch, 3), faction = faction_eq(orch, 2))
    check("intersect spatial+faction", r == Set(["a"]))
    r2 = intersect(orch; spatial = spatial_at(orch, 3), faction = faction_eq(orch, 2), social = social_eq(orch, 1))
    check("intersect empty when disjoint", isempty(r2))

    # Query resolves back to entities.
    ents = query(orch; faction = faction_eq(orch, 2))
    check("query resolves entities", Set([e.id for e in ents]) == Set(["a", "c"]))

    println(failures[] == 0 ? "SELF-TESTS PASS" : "SELF-TESTS FAIL ($(failures[]) failures)")
    return failures[] == 0
end

end  # module

if abspath(PROGRAM_FILE) == @__FILE__
    exit(MultiIso.run_self_tests() ? 0 : 1)
end
