# Sidecars & Container Operations

This is the entry point for the non-Godot services and container assets in
`srv/`. They run **inside the `synmergia` container**; they are not separate
Compose services. The only separate state services are `postgres` and `redis`,
and those are profile-gated.

Start here:

```bash
# Dev profile: postgres, redis, and synmergia (which starts all sidecars)
docker compose --profile dev up --build -d

# Check every sidecar from inside the running container
docker compose exec synmergia curl -f http://127.0.0.1:8080/health
docker compose exec synmergia curl -f http://127.0.0.1:8081/health
docker compose exec synmergia curl -f http://127.0.0.1:8083/health
docker compose exec synmergia curl -f http://127.0.0.1:8090/health
```

## Services

| Service | Port | Default backend | Purpose | Docs |
|---------|------|-----------------|---------|------|
| pg-bridge | 8080 | SQLite | Persistence API over SQLite/Postgres | [pg-bridge/README.md](./pg-bridge/README.md) |
| redis-bridge | 8081 | in-memory | Cache, sessions, rate-limit state | [redis-bridge/README.md](./redis-bridge/README.md) |
| webhook-bridge | 8083 | in-memory | Payment-processor webhook queue | [webhook-bridge/README.md](./webhook-bridge/README.md) |
| Julia orchestrator | 8090 | stdlib Julia | Multi-iso spatial index | [julia-bridge/README.md](./julia-bridge/README.md) |

The bridges are stdlib-only by default. `psycopg2-binary` and `redis-py` are
imported lazily only when the matching backend is selected. The container
entrypoint starts `server_lite.jl` for Julia, so the base image needs no
registered Julia packages.

The sidecar ports are internal to the `synmergia` container network and are
not published. Nginx (also inside that container) proxies the public routes;
in the dev/prod profiles Compose publishes nginx, the game port, and (dev
only) noVNC.

## Backends

- **SQLite / in-memory** — local development and CI. No external service.
- **Postgres / Redis** — the `dev` and `prod` profiles start `postgres` and
  `redis`; select the real backends with `PG_BACKEND=postgres` and
  `REDIS_BACKEND=redis`.
- **Julia** — `MULTI_ISO_URL=http://127.0.0.1:8090` is the engine default.

The storage and adapter contracts live in
[labs/prd-db.md](../labs/prd-db.md); the server runbook is
[DEPLOY.md](../DEPLOY.md).

## Container and test assets

- [docker/README.md](./docker/README.md) — runtime entrypoint modes and the
  headless test image.
- `docker/test-headless.sh` — run from the repo root:
  `sh ./srv/docker/test-headless.sh` (requires a host `godot`).
- Unit tests:
  - `python3 srv/pg-bridge/test_pg_bridge.py`
  - `python3 srv/redis-bridge/test_redis_bridge.py`
  - `python3 srv/webhook-bridge/test_webhook_bridge.py`
  - `python3 srv/test_noaa_kp_sidecar.py`
  - `sh srv/backup/test_backup.sh`

For the full game regression set, use the repo runner:

```bash
sh ./scripts/godot_test_runner.sh
```

## Backup and recovery

[backup/README.md](./backup/README.md) documents the WorldManifest three-tier
backup (Postgres primary, S3 hot tier, cold tier) and its cron schedule.

## TLS

First issuance is the one-shot `certbot-init` service; the `certbot`
service only renews. The app mounts the shared cert/webroot volumes and
reloads nginx when the lineage changes. See
[DEPLOY.md section 4](../DEPLOY.md#4-stagingproduction-setup).

## See also

- [DEPLOY.md](../DEPLOY.md) — Docker profiles, production setup, operations
- [DEVCODE.md](../DEVCODE.md) — local development without Docker
- [labs/prd-db.md](../labs/prd-db.md) — persistence/cache wire contracts
- [labs/prd-shard-mesh.md](../labs/prd-shard-mesh.md) — multi-container mesh
