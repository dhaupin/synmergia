# redis-bridge

HTTP-to-Redis sidecar. Mirrors `srv/pg-bridge/` — same shape, same
stdlib-only default backend, lazy redis import for prod.

Godot's `RedisStore` (game/adapters/cache/redis_store.gd) speaks this
HTTP API. Wire protocol is defined there and in `labs/prd-db.md` sec.7.2.

## Backends

| Backend | Deps | Use |
|---------|------|-----|
| `InMemoryBackend` | stdlib only | local dev + unit tests |
| `RedisBackend` | redis-py | prod (Docker image) |

## Env

```
REDIS_BACKEND=inmemory|redis     (default: inmemory)
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=
REDIS_DB=0
REDIS_BRIDGE_HOST=0.0.0.0
REDIS_BRIDGE_PORT=8081
```

## Run

```bash
python3 main.py
```

## Docker

The redis-bridge runs as part of the main Synmergia container. Redis
itself is a separate service in `docker-compose.yml` (profile `dev` and
`prod`). The bridge detects `REDIS_BACKEND=redis` and connects to it.

## Health

```
GET /health
```

Returns `{"status":"ok"}` when the backend is reachable.

## Test Results

Run the test suite from the `srv/redis-bridge/` directory:

```bash
python3 test_redis_bridge.py
```

**Expected output:**

```
Ran 20 tests in 11.132s

OK
```

The suite boots a `ThreadingHTTPServer` on an ephemeral port bound to
the `InMemoryBackend` (stdlib only), then exercises every wire endpoint.
Tests use `verbosity=2`, so each test name prints with `... ok`.

### Test classes

| Class | Tests | Verifies |
|-------|-------|----------|
| `TestRedisBridge` | 14 | `/health`, `/set` + `/get` roundtrip, `/get` on missing key (null), `/set_nx` first-writer-wins, `/del` (idempotent), `/exists`, `/expire` (missing key -> -1), `/incr` + `/incr_with_ttl`, hash ops (`/hset`, `/hget`, `/hget_all`, `/hdel`), set ops (`/sadd`, `/smembers`, `/sismember`, `/srem`), list ops (`/lpush`, `/rpush`, `/lrange`, `/llen`, `/lpop`), `/publish`, unknown route -> 404 |
| `TestRedisStoreContract` | 4 | Mirrors the exact HTTP sequence Godot's `RedisStore` uses: session token (`session:tok1` -> account) KV roundtrip with TTL; session token lifecycle (set -> exists -> del -> not-exists); rate-limit counter pipeline (`incr_with_ttl` over a 60s window); friends/players online-status hash (`online:shard_1`) |
| `TestPgRedisEndToEnd` | 2 | Boots **both** bridges (pg-bridge + redis-bridge) and proves the full adapter contract: account created in Postgres, session token stored in Redis, cross-store token resolves to a Postgres account; rate-limit counters live in Redis and are absent from Postgres |

> The end-to-end suite loads `test_pg_bridge.py` by file path (not bare
> `import`) to avoid the `server` / `backends` module-name collision
> between the two sidecars.

## Examples

The default port is `8081` (`REDIS_BRIDGE_PORT`). Replace
`localhost:8081` with your bridge address.

### Health check

```bash
curl -s http://localhost:8081/health | python3 -m json.tool
```

```json
{
  "ok": true,
  "version": "redis-bridge/1.0.0",
  "backend": "InMemoryBackend"
}
```

### Basic set / get

```bash
curl -s -X POST http://localhost:8081/set \
  -H 'Content-Type: application/json' \
  -d '{"key":"greeting","value":"hello"}'

curl -s http://localhost:8081/get?key=greeting
```

```json
{"ok": true}
{"value": "hello"}
```

### get on a missing key

```bash
curl -s http://localhost:8081/get?key=missing
```

```json
{"value": null}
```

### Set with TTL (session token)

```bash
curl -s -X POST http://localhost:8081/set \
  -H 'Content-Type: application/json' \
  -d '{"key":"session:tok_abc","value":"acc_42","ttl_sec":86400}'
```

```json
{"ok": true}
```

### Rate-limit counter (incr_with_ttl)

```bash
for i in 1 2 3 4 5; do
  curl -s -X POST http://localhost:8081/incr_with_ttl \
    -H 'Content-Type: application/json' \
    -d '{"key":"rl:alice","ttl_sec":60}'
  echo
done
```

```json
{"value": 1}
{"value": 2}
{"value": 3}
{"value": 4}
{"value": 5}
```

### Hash operations (online status)

```bash
curl -s -X POST http://localhost:8081/hset \
  -H 'Content-Type: application/json' \
  -d '{"key":"online:shard_1","field":"acc_7","value":"true"}'

curl -s "http://localhost:8081/hget_all?key=online:shard_1"
```

```json
{"ok": true}
{"fields": {"acc_7": "true"}}
```

### Hash field get / delete

```bash
curl -s "http://localhost:8081/hget?key=online:shard_1&field=acc_7"
curl -s -X POST http://localhost:8081/hdel \
  -H 'Content-Type: application/json' \
  -d '{"key":"online:shard_1","field":"acc_7"}'
```

```json
{"value": "true"}
{"deleted": 1}
```

### Pub/sub (publish)

```bash
curl -s -X POST http://localhost:8081/publish \
  -H 'Content-Type: application/json' \
  -d '{"channel":"chat:world","message":"player logged in"}'
```

```json
{"ok": true, "delivered": 0}
```

> `delivered` reflects the number of in-process subscribers at the
> moment of publish. The in-memory backend has no persistent
> subscription list, so `0` is expected for a fresh bridge.
