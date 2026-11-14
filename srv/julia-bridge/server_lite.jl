# server_lite.jl — stdlib-only HTTP API server for the multi-iso orchestrator.
#
# This is the RUNNABLE sibling of `server.jl`. `server.jl` needs
# HTTP.jl + JSON.jl, whose pkgimages cannot compile in this container's
# Julia (see the env note in labs/prd-perf-bridges.md), so that server can
# never boot here or in CI and the orchestrator's live path could never be
# exercised. This server implements the SAME HTTP API on the stdlib only
# (`Sockets` + `jsonlite.jl` + a hand-rolled HTTP/1.1 handler), so the
# sidecar boots anywhere Julia boots and `MultiIsoService` has something
# real to talk to.
#
# Usage:
#     julia --startup-file=no --project=. server_lite.jl [--port 8090]
#
# Endpoints (identical to server.jl):
#     POST /register     Register an entity
#     POST /unregister   Remove an entity
#     GET  /spatial/:v   Entities at icosahedral vertex v
#     GET  /faction/:f   Entities in faction f
#     GET  /social/:s    Entities in social group s
#     POST /intersect    Multi-axis intersection
#     GET  /stats        Orchestrator statistics
#     GET  /health       Health check
#
# Wire: `include("orchestrator.jl")` (module MultiIso, stdlib-only) +
# `include("jsonlite.jl")` (module JsonLite, stdlib-only). No registered
# packages -- see README.md.

include("orchestrator.jl")
include("jsonlite.jl")

using .MultiIso
using .JsonLite
using Sockets
using UUIDs

const ORCH = MultiIso.Orchestrator()

# ---- handlers (return (status, body_dict)) -----------------------------

function handle(method::String, target::String, rawbody::Vector{UInt8})
    if target == "/health"
        return (200, Dict{String,Any}("status" => "ok",
                                      "entities" => length(ORCH.entities)))
    end

    if target == "/stats"
        axes = Dict{String,Any}(string(k) => length(v) for (k, v) in ORCH.by_axis)
        return (200, Dict{String,Any}("total_entities" => length(ORCH.entities),
                                      "axes" => axes))
    end

    if target == "/register" && method == "POST"
        data = JsonLite.parse_json(String(rawbody))
        data isa AbstractDict || return (400, Dict{String,Any}("error" => "bad body"))
        entity = MultiIso.Entity(;
            id             = get(data, "id", string(UUIDs.uuid4())),
            facility       = get(data, "facility", 1),
            spatial_vertex = get(data, "spatial_vertex", 0),
            faction_id     = get(data, "faction_id", 0),
            birth_year     = get(data, "birth_year", 2026),
            social_group   = get(data, "social_group", 0),
            game_class     = get(data, "game_class", 0),
            chunk_key      = get(data, "chunk_key", -1))
        MultiIso.register!(ORCH, entity)
        return (200, Dict{String,Any}("id" => entity.id, "nsc9" => entity.nsc9[:spatial]))
    end

    if target == "/unregister" && method == "POST"
        data = JsonLite.parse_json(String(rawbody))
        data isa AbstractDict || return (400, Dict{String,Any}("error" => "bad body"))
        id = string(get(data, "id", ""))
        removed = MultiIso.unregister!(ORCH, id)
        return (200, Dict{String,Any}("id" => id, "removed" => removed))
    end

    m = match(r"^/spatial/(\d+)$", target)
    if !isnothing(m)
        v = parse(Int, m.captures[1])
        return (200, Dict{String,Any}("vertex" => v,
                                      "entity_ids" => collect(MultiIso.spatial_at(ORCH, v))))
    end

    m = match(r"^/faction/(\d+)$", target)
    if !isnothing(m)
        f = parse(Int, m.captures[1])
        return (200, Dict{String,Any}("faction_id" => f,
                                      "entity_ids" => collect(MultiIso.faction_eq(ORCH, f))))
    end

    m = match(r"^/social/(\d+)$", target)
    if !isnothing(m)
        s = parse(Int, m.captures[1])
        return (200, Dict{String,Any}("social_group" => s,
                                      "entity_ids" => collect(MultiIso.social_eq(ORCH, s))))
    end

    m = match(r"^/chunk/(\d+)$", target)
    if !isnothing(m)
        c = parse(Int, m.captures[1])
        return (200, Dict{String,Any}("chunk_key" => c,
                                      "entity_ids" => collect(MultiIso.chunk_at(ORCH, c))))
    end

    if target == "/intersect" && method == "POST"
        data = JsonLite.parse_json(String(rawbody))
        data isa AbstractDict || return (400, Dict{String,Any}("error" => "bad body"))
        kwargs = Dict{Symbol,Any}()
        haskey(data, "spatial_vertex") && (kwargs[:spatial] = MultiIso.spatial_at(ORCH, data["spatial_vertex"]))
        haskey(data, "faction_id")     && (kwargs[:faction] = MultiIso.faction_eq(ORCH, data["faction_id"]))
        haskey(data, "social_group")   && (kwargs[:social]  = MultiIso.social_eq(ORCH, data["social_group"]))
        haskey(data, "chunk_key")      && (kwargs[:chunk]   = MultiIso.chunk_at(ORCH, data["chunk_key"]))
        ids = MultiIso.intersect(ORCH; kwargs...)
        ents = [Dict{String,Any}(
            "id" => e.id, "facility" => e.facility,
            "spatial_vertex" => e.spatial_vertex, "faction_id" => e.faction_id,
            "birth_year" => e.birth_year, "social_group" => e.social_group,
            "game_class" => e.game_class, "chunk_key" => e.chunk_key) for e in MultiIso.query(ORCH; kwargs...)]
        return (200, Dict{String,Any}("count" => length(ids),
                                      "entity_ids" => collect(ids),
                                      "entities" => ents))
    end

    return (404, Dict{String,Any}("error" => "Not found: $target"))
end

# ---- minimal HTTP/1.1 request loop -------------------------------------

function read_request(sock)
    # Read headers up to the blank line, then Content-Length bytes of body.
    header = IOBuffer()
    while true
        line = readline(sock; keep = true)
        if line == ""                       # EOF / client hung up
            return nothing
        end
        if line == "\r\n" || line == "\n"   # end of headers
            break
        end
        print(header, line)
    end
    text = String(take!(header))
    lines = split(text, "\r\n")
    isempty(lines) && return nothing
    parts = split(lines[1], " ")
    length(parts) < 3 && return nothing
    method, target = String(parts[1]), String(parts[2])
    len = 0
    for l in lines[2:end]
        lo = lowercase(l)
        if startswith(lo, "content-length:")
            len = parse(Int, strip(l[(length("content-length:") + 1):end]))
        end
    end
    body = UInt8[]
    if len > 0
        body = read(sock, len)
    end
    return (method, target, body)
end

function write_response(sock, status::Int, body::String)
    reason = status == 200 ? "OK" : status == 400 ? "Bad Request" :
             status == 404 ? "Not Found" : "Internal Server Error"
    payload = Vector{UInt8}(codeunits(body))
    resp = "HTTP/1.1 $status $reason\r\n" *
           "Content-Type: application/json\r\n" *
           "Content-Length: $(length(payload))\r\n" *
           "Connection: close\r\n\r\n"
    write(sock, Vector{UInt8}(codeunits(resp)))
    write(sock, payload)
    flush(sock)
end

function main()
    port = 8090
    args = ARGS
    i = 1
    while i <= length(args)
        if args[i] == "--port" && i < length(args)
            port = parse(Int, args[i + 1]); i += 2
        else
            i += 1
        end
    end

    server = listen(ip"0.0.0.0", port)
    println("Multi-iso orchestrator HTTP API (stdlib-only) on port $port")
    flush(stdout)

    while true
        sock = accept(server)
        try
            req = read_request(sock)
            if req === nothing
                close(sock); continue
            end
            method, target, body = req
            status, data = Base.invokelatest(handle, method, target, body)
            write_response(sock, status, JsonLite.encode(data))
        catch e
            try
                write_response(sock, 500, JsonLite.encode(Dict{String,Any}("error" => string(e))))
            catch
            end
        finally
            close(sock)
        end
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
