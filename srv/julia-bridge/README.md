# julia-bridge

Julia multi-iso orchestrator sidecar. Sibling of `srv/pg-bridge/` and
`srv/redis-bridge/` -- same role in the architecture: a non-Godot
service the game reaches over HTTP, never by import path.

Client: `MultiIsoService` (game/core/services/multi_iso_service.gd)
talks to `http://localhost:8090` (dev) or `http://julia:8090`
(docker-compose service name) to register entities and run
multi-axis intersection queries. Port 8090 is deliberate: 8080/8081 are
pg-bridge/redis-bridge. `MULTI_ISO_URL` (or `JULIA_BRIDGE_URL`) overrides
the URL at boot.

## Run

    julia --project=. server.jl        # HTTP API server (needs HTTP.jl + JSON.jl)
    julia --project=. orchestrator.jl  # self-tests

Deps are stdlib + HTTP.jl + JSON.jl (see Project.toml). The Godot
Dockerfile installs Julia; the service runs as a sidecar container.

**Started by the container.** `srv/docker/entrypoint.sh` starts the
stdlib-only `server_lite.jl` on `127.0.0.1:8090` in every server mode
(dev/prod/headless/coordinator) via `_start_julia_bridge`, so the
engine's `MultiIsoService` (autoload) reaches a live orchestrator and
mirrors the entity roster into it. Fails soft: no julia on PATH -> the
engine degrades to empty results, no boot failure.

## server_lite.jl — the RUNNABLE server (stdlib-only)

`server.jl` needs HTTP.jl + JSON.jl. In this container's Julia (1.11.1)
those pkgimages CANNOT compile (a segfault compiling a pkgimage for any
registered package -- see the env note in `labs/prd-perf-bridges.md`), so
`server.jl` never boots here or in CI and the orchestrator's live path
could never be exercised. `server_lite.jl` is the stdlib-only sibling:
the SAME HTTP API on `Sockets` + `jsonlite.jl` + a small HTTP/1.1 loop,
no registered packages. It boots anywhere Julia boots.

    julia --startup-file=no --compile=min --project=. server_lite.jl [--port 8090]

`--compile=min` is REQUIRED on this Julia build: its default optimizer
MISCOMPILES the request loop to a segfault (the same class of codegen
bug as the out-of-bounds read documented in `propmath.jl`). `--compile=min`
runs the interpreter path and is stable. The two codegen traps found
while porting are recorded in `jsonlite.jl`.

Endpoints are identical to `server.jl`; `MultiIsoService` points at the
same `http://localhost:8090`. The receipt
`game/tests/test_julia_orchestrator_live.gd` boots this server, drives
`MultiIsoService` through a real register -> query -> unregister cycle,
and asserts the results.

## Spatial axes: vertex + canonical chunk

An entity is indexed on TWO spatial axes:

- the coarse 0..11 icosahedral VERTEX (`/spatial/:v`) -- near-uniform,
  ~1/12 of the planet per bucket; and
- the EXACT canonical clipmap CHUNK (`GET /chunk/:c`) -- `PropChunk`
  (terrain face 0..19 + a barycentric cell at depth 6), the
  player-independent cell the prop layer and every client derive
  (`labs/prd-clipmap.md` sec. 12).

`/register` and `/intersect` take a `chunk_key` (>= 0; -1 means "no
position", so a body with no position is indexed on every axis EXCEPT
`chunk`). The Godot side derives it with `PropChunk.chunk_for_dir`, the
same law the prop layer uses, so the server holds exactly the cell a
client derives. Readers: `MultiIsoService.query_chunk` /
`query_chunk_at_dir`; admin `/chunk` prints the sender's cell + the
bodies the index holds there.


## History

Relocated 2026-09-30: the files spent time inside
`game/core/frame/srv/` (wrongly, as "frame primitives") and briefly
`labs/multi-iso/srv/`, but the repo's bridge convention is `srv/`
-- this slot, next to pg-bridge and redis-bridge. The original
canonical-slot doc survives archived at
`labs/archive/docs/architecture/labs-organization.md`.
