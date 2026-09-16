"""
server.jl — HTTP API server for the multi-iso orchestrator

Exposes the Julia Orchestrator as a JSON HTTP API so Godot can
query it via HTTP calls (no FFI needed, works across Docker networks).

Usage:
    julia --project=. server.jl [--port 8080]

Endpoints:
    POST /register     Register an entity
    GET  /spatial/:v  Entities at vertex v
    GET  /faction/:f  Entities in faction f
    GET  /social/:s   Entities in social group s
    POST /intersect   Multi-axis intersection
    GET  /stats       Orchestrator statistics
    GET  /health      Health check
"""
module Server

using UUIDs
using Sockets

include("orchestrator.jl")
using .Orchestrator

# ---- Global orchestrator instance ----
const ORCH = Orchestrator()

# ---- HTTP request handlers ----

function parse_json_body(req::HTTP.Request)
    body = HTTP.payload(req)
    return JSON.parse(String(body))
end

function json_response(status::Int, data::Any)
    body = JSON.json(data)
    return HTTP.Response(status, ["Content-Type" => "application/json"]; body=body)
end

function json_ok(data::Any)
    json_response(200, data)
end

function json_error(status::Int, message::String)
    json_response(status, Dict("error" => message))
end

function route(req::HTTP.Request)
    target = HTTP.target(req)
    method = HTTP.method(req)

    @info "→ $method $target"

    try
        # Health
        if target == "/health"
            return json_ok(Dict("status" => "ok", "entities" => length(ORCH.entities)))

        # Stats
        if target == "/stats"
            axis_counts = Dict(String(k) => length(v) for (k, v) in ORCH.axes)
            return json_ok(Dict(
                "total_entities" => length(ORCH.entities),
                "axes" => axis_counts
            ))
        end

        # Register entity
        if target == "/register" && method == "POST"
            data = parse_json_body(req)
            entity = Entity(;
                id              = get(data, "id", string(UUIDs.uuid4())),
                facility        = get(data, "facility", 1),
                spatial_vertex  = get(data, "spatial_vertex", 0),
                faction_id      = get(data, "faction_id", 0),
                birth_year      = get(data, "birth_year", 2026),
                social_group    = get(data, "social_group", 0),
                game_class      = get(data, "game_class", 0)
            )
            register!(ORCH, entity)
            return json_ok(Dict("id" => entity.id, "nsc9" => entity.nsc9))
        end

        # Spatial query: GET /spatial/:vertex
        m = match(r"^/spatial/(\d+)$", target)
        if !isnothing(m)
            vertex = parse(Int, m.captures[1])
            result = spatial_at(ORCH, vertex)
            return json_ok(Dict("vertex" => vertex, "entity_ids" => collect(result)))
        end

        # Faction query: GET /faction/:faction_id
        m = match(r"^/faction/(\d+)$", target)
        if !isnothing(m)
            fid = parse(Int, m.captures[1])
            result = faction_eq(ORCH, fid)
            return json_ok(Dict("faction_id" => fid, "entity_ids" => collect(result)))
        end

        # Social query: GET /social/:group
        m = match(r"^/social/(\d+)$", target)
        if !isnothing(m)
            group = parse(Int, m.captures[1])
            result = social_eq(ORCH, group)
            return json_ok(Dict("social_group" => group, "entity_ids" => collect(result)))
        end

        # Intersect: POST /intersect
        if target == "/intersect" && method == "POST"
            data = parse_json_body(req)

            # Build keyword args from JSON body
            kwargs = Dict{Symbol, Any}()

            if haskey(data, "spatial_vertex")
                kwargs[:spatial] = spatial_at(ORCH, data["spatial_vertex"])
            end
            if haskey(data, "faction_id")
                kwargs[:faction] = faction_eq(ORCH, data["faction_id"])
            end
            if haskey(data, "social_group")
                kwargs[:social] = social_eq(ORCH, data["social_group"])
            end

            result_ids = intersect(ORCH; kwargs...)
            result_entities = [Dict(
                "id" => e.id,
                "facility" => e.facility,
                "spatial_vertex" => e.spatial_vertex,
                "faction_id" => e.faction_id,
                "birth_year" => e.birth_year,
                "social_group" => e.social_group,
                "game_class" => e.game_class
            ) for e in query(ORCH; kwargs...)]

            return json_ok(Dict(
                "count" => length(result_ids),
                "entity_ids" => collect(result_ids),
                "entities" => result_entities
            ))
        end

        return json_error(404, "Not found: $target")

    catch e
        @error "Handler error" exception = (e, catch_backtrace())
        return json_error(500, string(e))
    end
end

# ---- Main ----
function main()
    port = 8080
    for (i, arg) in enumerate(ARGS)
        if arg == "--port" && i < length(ARGS)
            port = parse(Int, ARGS[i + 1])
        end
    end

    println("=" ^ 60)
    println("Multi-iso orchestrator HTTP API")
    println("  Port:  $port")
    println("  Endpoints:")
    println("    GET  /health          health check")
    println("    GET  /stats           orchestrator statistics")
    println("    POST /register        register an entity")
    println("    GET  /spatial/:v      entities at vertex v")
    println("    GET  /faction/:f      entities in faction f")
    println("    GET  /social/:s       entities in social group s")
    println("    POST /intersect       multi-axis intersection")
    println("=" ^ 60)

    server = Sockets.listen(Sockets.IPv4(0.0.0.0), port)
    HTTP.serve(route, server)
end

end  # module

if abspath(PROGRAM_FILE) == @__FILE__
    Server.main()
end
