# pg-bridge

HTTP-to-PostgreSQL/SQLite sidecar. Mirrors `srv/redis-bridge/` — same
shape, same stdlib-only default backend, lazy psycopg2 import for prod.

Godot's `PersistenceStore` implementations (game/adapters/persistence/)
speak this HTTP API. Wire protocol is defined in `labs/prd-db.md` sec.3-5.

## Backends

| Backend | Deps | Use |
|---------|------|-----|
| `SQLiteBackend` | stdlib only | local dev + unit tests |
| `PostgresBackend` | psycopg2-binary | prod (Docker image) |

## Env

```
PG_BACKEND=sqlite|postgres       (default: sqlite)
PG_BRIDGE_HOST=0.0.0.0
PG_BRIDGE_PORT=8080
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_DB=synmergia
POSTGRES_USER=synmergia
POSTGRES_PASSWORD=...
PG_BRIDGE_POOL=8                 # connection pool size (postgres only)
```

## Run

```bash
python3 main.py
```

## Docker

The pg-bridge runs as part of the main Synmergia container. PostgreSQL
itself is a separate service in `docker-compose.yml` (profile `dev` and
`prod`). The bridge detects `PG_BACKEND=postgres` and connects to it.

## Health

```
GET /health
```

Returns `{"status":"ok"}` when the backend is reachable.
