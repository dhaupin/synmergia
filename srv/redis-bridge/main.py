"""
main.py -- entry point for the redis-bridge sidecar.

Env:
  REDIS_BRIDGE_HOST  (default 0.0.0.0)
  REDIS_BRIDGE_PORT  (default 8081)
  REDIS_BACKEND      inmemory | redis  (default inmemory)
  REDIS_HOST / REDIS_PORT / REDIS_PASSWORD / REDIS_DB
"""
from __future__ import annotations

import os
import sys
from http.server import ThreadingHTTPServer

# So `import backends` / `import server` resolve when running directly.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from server import make_handler, build_backend  # noqa: E402


def _redis_config() -> dict:
    return {
        "host": os.environ.get("REDIS_HOST", "redis"),
        "port": os.environ.get("REDIS_PORT", "6379"),
        "password": os.environ.get("REDIS_PASSWORD", ""),
        "db": int(os.environ.get("REDIS_DB", "0")),
    }


def main() -> int:
    backend_name = os.environ.get("REDIS_BACKEND", "inmemory")
    config = _redis_config() if backend_name == "redis" else {}

    backend = build_backend(backend_name, config)
    handler = make_handler(backend)

    host = os.environ.get("REDIS_BRIDGE_HOST", "0.0.0.0")
    port = int(os.environ.get("REDIS_BRIDGE_PORT", "8081"))
    httpd = ThreadingHTTPServer((host, port), handler)

    print("=" * 60)
    print("redis-bridge")
    print("  backend: %s (%s)" % (type(backend).__name__, backend_name))
    print("  listen:  %s:%d" % (host, port))
    print("  routes:  /health /get /set /set_nx /del /exists /expire /incr "
          "/incr_with_ttl /hset /hget /hget_all /hdel /sadd /srem /smembers "
          "/sismember /lpush /rpush /lpop /lrange /llen /publish")
    print("=" * 60)
    sys.stdout.flush()

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        backend.close()
        httpd.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
