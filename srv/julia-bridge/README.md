# julia-bridge

Julia multi-iso orchestrator sidecar. Sibling of `srv/pg-bridge/` and
`srv/redis-bridge/` -- same role in the architecture: a non-Godot
service the game reaches over HTTP, never by import path.

Client: `MultiIsoService` (game/core/services/multi_iso_service.gd)
talks to `http://localhost:8080` (dev) or `http://julia:8080`
(docker-compose service name) to register entities and run
multi-axis intersection queries.

## Run

    julia --project=. server.jl        # HTTP API server
    julia --project=. orchestrator.jl  # self-tests

Deps are stdlib + HTTP.jl + JSON.jl (see Project.toml). The Godot
Dockerfile installs Julia; the service runs as a sidecar container.

## History

Relocated 2026-09-30: the files spent time inside
`game/core/frame/srv/` (wrongly, as "frame primitives") and briefly
`labs/multi-iso/srv/`, but the repo's bridge convention is `srv/`
-- this slot, next to pg-bridge and redis-bridge. The original
canonical-slot doc survives archived at
`labs/archive/docs/architecture/labs-organization.md`.
