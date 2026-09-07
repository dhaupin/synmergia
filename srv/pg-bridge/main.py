"""
main.py — entry point for the pg-bridge sidecar.

Env:
  PG_BRIDGE_HOST  (default 0.0.0.0)
  PG_BRIDGE_PORT  (default 8080)
  PG_BACKEND      sqlite | postgres  (default sqlite)
  POSTGRES_HOST / POSTGRES_PORT / POSTGRES_DB / POSTGRES_USER / POSTGRES_PASSWORD
"""
from __future__ import annotations

import os
import sys
import threading
from http.server import ThreadingHTTPServer

# So `import backends` / `import server` resolve when running directly.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from server import make_handler, build_backend  # noqa: E402


def _postgres_config() -> dict:
    host = os.environ.get("POSTGRES_HOST", "postgres")
    port = os.environ.get("POSTGRES_PORT", "5432")
    db = os.environ.get("POSTGRES_DB", "synmergia")
    user = os.environ.get("POSTGRES_USER", "synmergia")
    pw = os.environ.get("POSTGRES_PASSWORD", "synmergia_dev_pass")
    return {
        "dsn": "host=%s port=%s dbname=%s user=%s password=%s" % (host, port, db, user, pw),
        "pool_size": int(os.environ.get("PG_BRIDGE_POOL", "8")),
    }


def main() -> int:
    backend_name = os.environ.get("PG_BACKEND", "sqlite")
    if backend_name == "postgres":
        config = _postgres_config()
    else:
        config = {}

    backend = build_backend(backend_name, config)
    handler = make_handler(backend)

    host = os.environ.get("PG_BRIDGE_HOST", "0.0.0.0")
    port = int(os.environ.get("PG_BRIDGE_PORT", "8080"))
    httpd = ThreadingHTTPServer((host, port), handler)

    print("=" * 60)
    print("pg-bridge")
    print("  backend: %s (%s)" % (type(backend).__name__, backend_name))
    print("  listen:  %s:%d" % (host, port))
    print("  routes:  /health /query /execute /tx/begin /tx/commit /tx/rollback /insert_many /batch")
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
