"""
server.py — HTTP server for the pg-bridge sidecar.

Exposes the wire protocol that Godot's PostgresStore speaks (see
game/adapters/persistence/postgres_store.gd header + labs/prd-db.md sec.7.1).
Each request is a single SQL op proxied to the configured Backend.

Routes (all under /):
  GET  /health              -> { ok: true, version, backend }
  POST /query               { sql, params }      -> { rows: [...] }
  POST /execute             { sql, params }      -> { affected: N }
  POST /tx/begin                                 -> { tx_id: N }
  POST /tx/commit           { tx_id }            -> { ok: true }
  POST /tx/rollback         { tx_id }            -> { ok: true }
  POST /insert_many         { table, rows, columns } -> { affected: N }
  POST /batch               { statements: [...] } -> { ok: true }
"""
from __future__ import annotations

import json
from http.server import BaseHTTPRequestHandler

from backends import Backend, SQLiteBackend, PostgresBackend

VERSION = "pg-bridge/1.0.0"


def make_handler(backend: Backend):
    """Build a handler class bound to a specific backend instance."""

    class PgBridgeHandler(BaseHTTPRequestHandler):
        server_version = "PgBridge/1.0.0"

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

        def do_GET(self) -> None:
            if self.path == "/health":
                return self._send_json(
                    200, {"ok": backend.healthy(), "version": VERSION,
                          "backend": type(backend).__name__}
                )
            self._send_json(404, {"error": "not found: %s" % self.path})

        def do_POST(self) -> None:
            try:
                body = self._read_body()
            except ValueError as e:
                return self._send_json(400, {"ok": False, "error": str(e)})

            p = self.path
            try:
                if p == "/query":
                    rows = backend.query(body.get("sql", ""), body.get("params"))
                    return self._send_json(200, {"rows": rows, "ok": True})

                if p == "/execute":
                    affected = backend.execute(body.get("sql", ""), body.get("params"))
                    return self._send_json(200, {"affected": affected, "ok": True})

                if p == "/tx/begin":
                    tx_id = backend.begin()
                    return self._send_json(200, {"tx_id": tx_id, "ok": True})

                if p == "/tx/commit":
                    ok = backend.commit(int(body.get("tx_id", -1)))
                    return self._send_json(200, {"ok": ok})

                if p == "/tx/rollback":
                    ok = backend.rollback(int(body.get("tx_id", -1)))
                    return self._send_json(200, {"ok": ok})

                if p == "/insert_many":
                    affected = backend.insert_many(
                        body.get("table", ""), body.get("rows", []),
                        body.get("columns", []),
                    )
                    return self._send_json(200, {"affected": affected, "ok": True})

                if p == "/batch":
                    ok = backend.execute_batch(body.get("statements", []))
                    return self._send_json(200, {"ok": ok})

                self._send_json(404, {"ok": False, "error": "not found: %s" % p})
            except Exception as e:  # noqa: BLE001 — bridge must not crash the process
                self._send_json(500, {"ok": False, "error": str(e)})

        def log_message(self, fmt, *args) -> None:  # silence default stderr noise
            pass

    return PgBridgeHandler


def build_backend(backend_name: str = "sqlite", config: dict | None = None) -> Backend:
    """Factory: 'sqlite' (default) or 'postgres'."""
    if backend_name == "postgres":
        b = PostgresBackend()
    else:
        b = SQLiteBackend()
    b.connect(config or {})
    return b
