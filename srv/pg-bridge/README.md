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

## Test Results

Run the test suite from the `srv/pg-bridge/` directory:

```bash
python3 test_pg_bridge.py
```

**Expected output:**

```
Ran 12 tests in 6.098s

OK
```

The suite boots a `ThreadingHTTPServer` on an ephemeral port bound to
the `SQLiteBackend` (stdlib only), then exercises every wire endpoint.
Tests use `verbosity=2`, so each test name prints with `... ok`.

### Test classes

| Class | Tests | Verifies |
|-------|-------|----------|
| `TestPgBridge` | 10 | `/health`, `/query` (rows + empty + `WHERE` with params), `/execute` (affected count + SQL error -> 500), `/tx/begin` + `/tx/commit` (persists), `/tx/begin` + `/tx/rollback` (reverts), `/batch` (multiple statements), `/insert_many` (bulk insert) |
| `TestMigrationAgainstBridge` | 2 | The real first migration (`game/adapters/migrations/V20260907_001__init_accounts.sql`) is well-formed and splits into non-empty statements; a SQLite-compatible migration applied through the bridge writes queryable rows and creates the `schema_migrations` table |

> The real migration is Postgres-flavored (`TIMESTAMPTZ`, `JSONB`,
> `UUID`, `CHECK IN`) and cannot run against the SQLite test backend.
> The test verifies the *contract* (load / split / apply / record)
> with a SQLite-compatible mirror, and separately asserts the real
> file is loadable so a typo doesn't reach prod.

## Examples

The default port is `8080` (`PG_BRIDGE_PORT`). Replace `localhost:8080`
with your bridge address.

### Health check

```bash
curl -s http://localhost:8080/health | python3 -m json.tool
```

```json
{
  "ok": true,
  "version": "pg-bridge/1.0.0",
  "backend": "SQLiteBackend"
}
```

### Execute (DDL / INSERT with params)

```bash
curl -s -X POST http://localhost:8080/execute \
  -H 'Content-Type: application/json' \
  -d '{"sql":"CREATE TABLE people (id TEXT, name TEXT)"}'

curl -s -X POST http://localhost:8080/execute \
  -H 'Content-Type: application/json' \
  -d '{"sql":"INSERT INTO people (id, name) VALUES ($1, $2)","params":["a1","alice"]}'
```

```json
{"affected": 1, "ok": true}
```

### Query (SELECT with params)

```bash
curl -s -X POST http://localhost:8080/query \
  -H 'Content-Type: application/json' \
  -d '{"sql":"SELECT * FROM people WHERE name = $1","params":["alice"]}'
```

```json
{"rows": [{"id": "a1", "name": "alice"}], "ok": true}
```

### Batch (multiple statements in one request)

```bash
curl -s -X POST http://localhost:8080/batch \
  -H 'Content-Type: application/json' \
  -d '{"statements":["CREATE TABLE b (id TEXT)","INSERT INTO b (id) VALUES ('\''x'\'')","INSERT INTO b (id) VALUES ('\''y'\'')"]}'
```

```json
{"ok": true}
```

### insert_many (bulk insert)

```bash
curl -s -X POST http://localhost:8080/insert_many \
  -H 'Content-Type: application/json' \
  -d '{"table":"im","columns":["id","val"],"rows":[["a",1],["b",2],["c",3]]}'
```

```json
{"affected": 3, "ok": true}
```

### Transaction flow (begin / commit)

```bash
# Begin a transaction; note the returned tx_id.
TX=$(curl -s -X POST http://localhost:8080/tx/begin \
  -H 'Content-Type: application/json' \
  -d '{}' | python3 -c 'import sys,json;print(json.load(sys.stdin)["tx_id"])')

# Run a statement scoped to that transaction (POST /execute is tx-aware
# when a transaction connection is active on the bridge).
curl -s -X POST http://localhost:8080/execute \
  -H 'Content-Type: application/json' \
  -d '{"sql":"INSERT INTO people (id, name) VALUES ($1, $2)","params":["tx1","carol"]}'

# Commit (or roll back) using the tx_id.
curl -s -X POST http://localhost:8080/tx/commit \
  -H 'Content-Type: application/json' \
  -d "{\"tx_id\": $TX}"
```

```json
{"ok": true}
```

### Transaction rollback (reverts uncommitted writes)

```bash
TX=$(curl -s -X POST http://localhost:8080/tx/begin \
  -H 'Content-Type: application/json' \
  -d '{}' | python3 -c 'import sys,json;print(json.load(sys.stdin)["tx_id"])')

curl -s -X POST http://localhost:8080/execute \
  -H 'Content-Type: application/json' \
  -d '{"sql":"INSERT INTO people (id, name) VALUES ($1, $2)","params":["rb1","dave"]}'

# Rollback discards the insert.
curl -s -X POST http://localhost:8080/tx/rollback \
  -H 'Content-Type: application/json' \
  -d "{\"tx_id\": $TX}"
```

```json
{"ok": true}
```
