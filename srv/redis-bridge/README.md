# redis-bridge

HTTP-to-Redis sidecar. Mirrors `srv/pg-bridge/` — same shape, same
stdlib-only default backend, lazy redis import for prod.

Godot's `RedisStore` (game/adapters/cache/redis_store.gd) speaks this
HTTP API. Wire protocol is defined there and in labs/prd-db.md sec.7.2.

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