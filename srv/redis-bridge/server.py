"""
server.py -- HTTP server for the redis-bridge sidecar.

Exposes the wire protocol that Godot's RedisStore speaks (see
game/adapters/cache/redis_store.gd header + labs/prd-db.md sec.7.2).
Each request is a single cache op proxied to the configured CacheBackend.

Routes (all under /):
  GET  /health              -> { ok: true, version, backend }
  GET  /get?key=...         -> { value: <any> } | { value: null }
  POST /set                  { key, value, ttl_sec } -> { ok: true }
  POST /set_nx               { key, value, ttl_sec } -> { ok: true|false }
  POST /del                  { key } -> { deleted: 0|1 }
  GET  /exists?key=...      -> { exists: true|false }
  POST /expire               { key, ttl_sec } -> { changed: -1|0|1 }
  POST /incr                 { key, by } -> { value: N }
  POST /incr_with_ttl        { key, ttl_sec } -> { value: N }
  POST /hset                 { key, field, value } -> { ok: true }
  GET  /hget?key=&field=    -> { value }
  GET  /hget_all?key=       -> { fields: {f: v} }
  POST /hdel                 { key, field } -> { deleted: 0|1 }
  POST /sadd                 { key, member } -> { added: 0|1 }
  POST /srem                 { key, member } -> { removed: 0|1 }
  GET  /smembers?key=       -> { members: [...] }
  GET  /sismember?key=&member= -> { is_member: bool }
  POST /lpush                { key, value } -> { length: N }
  POST /rpush                { key, value } -> { length: N }
  POST /lpop                 { key } -> { value }
  GET  /lrange?key=&start=&stop= -> { values: [...] }
  GET  /llen?key=            -> { length: N }
  POST /publish              { channel, message } -> { delivered: N }
"""
from __future__ import annotations

import json
from http.server import BaseHTTPRequestHandler
from urllib.parse import parse_qs, urlparse

from backends import CacheBackend, InMemoryBackend, RedisBackend

VERSION = "redis-bridge/1.0.0"


def make_handler(backend: CacheBackend):
    """Build a handler class bound to a specific backend instance."""

    class RedisBridgeHandler(BaseHTTPRequestHandler):
        server_version = "RedisBridge/1.0.0"
        # HTTP/1.1 keeps the connection alive; HTTP/1.0 (the default)
        # closes per response and breaks the Godot client's reuse.
        protocol_version = "HTTP/1.1"

        def _send_json(self, status: int, payload: dict) -> None:
            body = json.dumps(payload).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def _read_body(self) -> dict:
            length = int(self.headers.get("Content-Length", 0))
            if length == 0:
                return {}
            raw = self.rfile.read(length)
            try:
                return json.loads(raw)
            except json.JSONDecodeError as e:
                raise ValueError("invalid JSON: %s" % e)

        def _qs(self) -> dict:
            parsed = urlparse(self.path)
            return {k: v[0] for k, v in parse_qs(parsed.query).items()}

        def do_GET(self) -> None:
            try:
                if self.path.startswith("/health"):
                    return self._send_json(200, {
                        "ok": backend.healthy(),
                        "version": VERSION,
                        "backend": type(backend).__name__,
                    })
                q = self._qs()
                if self.path.startswith("/get"):
                    return self._send_json(200, {"value": backend.get(q.get("key", ""))})
                if self.path.startswith("/exists"):
                    return self._send_json(200, {"exists": bool(backend.exists(q.get("key", "")))})
                if self.path.startswith("/hget_all"):
                    return self._send_json(200, {"fields": backend.hget_all(q.get("key", ""))})
                if self.path.startswith("/hget"):
                    return self._send_json(200, {"value": backend.hget(q.get("key", ""), q.get("field", ""))})
                if self.path.startswith("/smembers"):
                    return self._send_json(200, {"members": backend.smembers(q.get("key", ""))})
                if self.path.startswith("/sismember"):
                    return self._send_json(200, {"is_member": bool(backend.sismember(q.get("key", ""), q.get("member", "")))})
                if self.path.startswith("/lrange"):
                    start = int(q.get("start", "0"))
                    stop = int(q.get("stop", "-1"))
                    return self._send_json(200, {"values": backend.lrange(q.get("key", ""), start, stop)})
                if self.path.startswith("/llen"):
                    return self._send_json(200, {"length": backend.llen(q.get("key", ""))})
                self._send_json(404, {"ok": False, "error": "not found: %s" % self.path})
            except Exception as e:  # noqa: BLE001 -- bridge must not crash the process
                self._send_json(500, {"ok": False, "error": str(e)})

        def do_POST(self) -> None:
            try:
                body = self._read_body()
            except ValueError as e:
                return self._send_json(400, {"ok": False, "error": str(e)})

            p = self.path
            try:
                if p == "/set":
                    return self._send_json(200, {"ok": bool(backend.set(
                        body.get("key", ""), body.get("value"),
                        int(body.get("ttl_sec", 0) or 0),
                    ))})
                if p == "/set_nx":
                    return self._send_json(200, {"ok": bool(backend.set_nx(
                        body.get("key", ""), body.get("value"),
                        int(body.get("ttl_sec", 0) or 0),
                    ))})
                if p == "/del":
                    return self._send_json(200, {"deleted": int(backend.delete(body.get("key", "")))})
                if p == "/expire":
                    return self._send_json(200, {"changed": int(backend.expire(
                        body.get("key", ""), int(body.get("ttl_sec", 0) or 0),
                    ))})
                if p == "/incr":
                    return self._send_json(200, {"value": int(backend.incr(
                        body.get("key", ""), int(body.get("by", 1) or 1),
                    ))})
                if p == "/incr_with_ttl":
                    return self._send_json(200, {"value": int(backend.incr_with_ttl(
                        body.get("key", ""), int(body.get("ttl_sec", 0) or 0),
                    ))})
                if p == "/hset":
                    return self._send_json(200, {"ok": bool(backend.hset(
                        body.get("key", ""), body.get("field", ""), body.get("value"),
                    ))})
                if p == "/hdel":
                    return self._send_json(200, {"deleted": int(backend.hdel(
                        body.get("key", ""), body.get("field", ""),
                    ))})
                if p == "/sadd":
                    return self._send_json(200, {"ok": True, "added": int(backend.sadd(
                        body.get("key", ""), body.get("member", ""),
                    ))})
                if p == "/srem":
                    return self._send_json(200, {"ok": True, "removed": int(backend.srem(
                        body.get("key", ""), body.get("member", ""),
                    ))})
                if p == "/lpush":
                    return self._send_json(200, {"length": int(backend.lpush(
                        body.get("key", ""), body.get("value"),
                    ))})
                if p == "/rpush":
                    return self._send_json(200, {"length": int(backend.rpush(
                        body.get("key", ""), body.get("value"),
                    ))})
                if p == "/lpop":
                    return self._send_json(200, {"ok": True, "value": backend.lpop(body.get("key", ""))})
                if p == "/publish":
                    return self._send_json(200, {"ok": True, "delivered": int(backend.publish(
                        body.get("channel", ""), body.get("message"),
                    ))})
                self._send_json(404, {"ok": False, "error": "not found: %s" % p})
            except Exception as e:  # noqa: BLE001 -- bridge must not crash the process
                self._send_json(500, {"ok": False, "error": str(e)})

        def log_message(self, fmt, *args) -> None:  # silence default stderr noise
            pass

    return RedisBridgeHandler


def build_backend(backend_name: str = "inmemory", config: dict | None = None) -> CacheBackend:
    """Factory: 'inmemory' (default) or 'redis'."""
    if backend_name == "redis":
        b = RedisBackend()
    else:
        b = InMemoryBackend()
    b.connect(config or {})
    return b
