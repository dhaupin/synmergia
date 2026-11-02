"""
main.py -- entry point for the webhook-bridge sidecar.

The payment processor's HTTP entry. Accepts delivery POSTs, queues
them, and hands them to the engine's poller
(game/core/economy/webhook_transport.gd), which feeds the premium
provider board's webhook door once per delivery and acks with the
verdict. This sidecar is TRANSPORT, not armor: the HMAC secret stays
in the engine's deployment env (PAYMENT_WEBHOOK_SECRET), the bridge
never verifies signatures, and an accepted delivery's raw body bytes
are stored verbatim so the engine's HMAC chain sees exactly what the
processor signed.

Env:
  WEBHOOK_BRIDGE_HOST   (default 127.0.0.1 prod; 0.0.0.0 for tests)
  WEBHOOK_BRIDGE_PORT   (default 8083)
  WEBHOOK_BACKEND       inmemory | redis  (default inmemory)
  WEBHOOK_MAX_BODY      body cap in bytes              (default 65536)
  WEBHOOK_CLAIM_TTL     claim hold seconds             (default 120)
  WEBHOOK_HOST / WEBHOOK_PORT / WEBHOOK_PASSWORD / WEBHOOK_DB  (redis backend)
"""
from __future__ import annotations

import os
import sys

# So `import backends` / `import server` resolve when run directly.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from backends import build_backend  # noqa: E402
from server import build_server  # noqa: E402


def _backend() -> object:
    name = os.environ.get("WEBHOOK_BACKEND", "inmemory")
    if name == "redis":
        config = {
            "host": os.environ.get("WEBHOOK_HOST", "redis"),
            "port": int(os.environ.get("WEBHOOK_PORT", "6379")),
            "password": os.environ.get("WEBHOOK_PASSWORD", "") or None,
            "db": int(os.environ.get("WEBHOOK_DB", "0")),
        }
    else:
        config = {}
    return build_backend(name, config)


def main() -> int:
    backend = _backend()
    host = os.environ.get("WEBHOOK_BRIDGE_HOST", "0.0.0.0")
    port = int(os.environ.get("WEBHOOK_BRIDGE_PORT", "8083"))
    max_body = int(os.environ.get("WEBHOOK_MAX_BODY", "65536"))
    claim_ttl = float(os.environ.get("WEBHOOK_CLAIM_TTL", "120"))
    httpd = build_server(backend, host, port, max_body, claim_ttl)

    print("=" * 60)
    print("webhook-bridge")
    print("  backend: %s" % type(backend).__name__)
    print("  listen:  %s:%d" % (host, port))
    print("  accept:  POST /hooks/<channel>   (raw processor webhook)")
    print("  poll:    GET /deliveries/next     (engine claim)")
    print("  ack:     POST /deliveries/<id>/ack  (engine verdict)")
    print("  operator: GET /deliveries/<id> / /stats / /health")
    print("  body cap: %d bytes, claim TTL: %.0f s" % (max_body, claim_ttl))
    print("  secret:  none -- the engine env owns the HMAC secret")
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
