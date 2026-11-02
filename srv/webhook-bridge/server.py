"""
server.py -- HTTP routes for the webhook-bridge sidecar.

Wire protocol (the engine transport in game/core/economy/webhook_transport.gd
is this API's second speaker, after the external payment processor):

  GET  /health                       -> { status, backend }
  POST /hooks/<channel>              -> the processor POSTs its RAW webhook
                                        body here; the bridge stores the
                                        delivery verbatim and answers 202
                                        immediately (accept-first,
                                        process-via-poll). Body cap applies.
  GET  /deliveries/next              -> claim the oldest claimable delivery
                                        { delivery, claim } | { delivery: null }
  GET  /deliveries/<id>              -> { delivery: <record> } | { delivery: null }
  POST /deliveries/<id>/ack          -> { claim, verdict, detail } marks the
                                        delivery handled with the engine's
                                        verdict; mismatched/stale claims -> 409
                                        ('already' acks -> 200 ok-same-record).
  GET  /stats                        -> queue operator readout.

Failure contract (why not 500 to the processor): the accepted delivery is
the processor's truth until the engine handles it, so the POST answer is
always 202 or 413 -- a processor that gets a 4xx/5xx would retry a
delivery the bridge already stores, which is harmless under engine
idempotence but noisy; 413 rejects BEFORE accepting (the body is not
stored), which is the one clean refusal.

Headers stored: lowercased, hop-by-hop stripped, duplicates rejoined
with ', '. The processor's signature header travels untouched.
"""
from __future__ import annotations

import base64
import json
import re
import secrets
import time
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

CHANNEL_RE = re.compile(r"^[a-z0-9_-]{1,64}$")
ID_RE = re.compile(r"^whk[a-z0-9_-]{0,128}$")
# Hop-by-hop headers plus the two that would otherwise lie about the
# relay (nginx sets its own Host / X-Real-IP; the signature envelope
# never lives in a hop header).
STRIP_HEADERS = frozenset((
    "host", "connection", "keep-alive", "proxy-authenticate",
    "proxy-authorization", "te", "trailers", "transfer-encoding", "upgrade",
    "content-length", "content-type",
))

VERDICTS = frozenset(("processed", "refused", "expired", "error"))
MAX_QUEUE = 10000            # metadata guard; never a real money volume
DEFAULT_MAX_BODY = 65536
DEFAULT_CLAIM_TTL = 120.0


class WebhookBridgeError(Exception):
    def __init__(self, status: int, message: str):
        super().__init__(message)
        self.status = status
        self.message = message


def build_handler(backend, max_body_bytes: int = DEFAULT_MAX_BODY,
                  claim_ttl_sec: float = DEFAULT_CLAIM_TTL):
    class Handler(SimpleHTTPRequestHandler):
        server_version = "webhook-bridge/1.0"

        def log_message(self, fmt, *args):  # quiet per-file logging
            pass

        # -- helpers --------------------------------------------------------

        def send_json(self, payload: dict, status: int = 200) -> None:
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(json.dumps(payload))))
            self.end_headers()
            self.wfile.write(json.dumps(payload).encode("utf-8"))

        def read_body(self) -> bytes:
            length = int(self.headers.get("Content-Length", 0) or 0)
            if length <= 0:
                raise WebhookBridgeError(400, "missing Content-Length")
            if length > max_body_bytes:
                raise WebhookBridgeError(
                    413,
                    "delivery body %d exceeds the %d byte cap" % (
                        length, max_body_bytes),
                )
            return self.rfile.read(length)

        def captured_headers(self) -> dict:
            merged: dict[str, str] = {}
            for name, value in self.headers.items():
                key = name.lower()
                if key in STRIP_HEADERS:
                    continue
                if key in merged:
                    merged[key] = merged[key] + ", " + value
                else:
                    merged[key] = value
            return merged

        # -- routes ---------------------------------------------------------

        def do_GET(self):  # noqa: N802 (http.server API)
            path = self.path.split("?", 1)[0]
            if path == "/health":
                ok = backend.healthy()
                self.send_json({
                    "status": "ok" if ok else "degraded",
                    "backend": type(backend).__name__,
                })
                return
            if path == "/stats":
                self.send_json({"status": "ok", "stats": backend.stats()})
                return
            if path == "/deliveries/next":
                taken = backend.take_delivery(claim_ttl_sec)
                if taken is None:
                    self.send_json({"delivery": None, "claim": None})
                    return
                self.send_json({
                    "delivery": dict(taken["record"]),
                    "claim": taken["claim"],
                })
                return
            match = re.match(r"^/deliveries/(whk[a-z0-9_-]{0,128})$", path)
            if match:
                record = backend.get_delivery(match.group(1))
                self.send_json({"delivery": record})
                return
            self.send_json({"status": "error", "reason": "unknown endpoint"},
                           status=404)

        def do_POST(self):  # noqa: N802 (http.server API)
            path = self.path.split("?", 1)[0]
            # Payment webhook entry: the processor's raw body becomes a
            # queued delivery verbatim.
            match = re.match(r"^/hooks/([a-z0-9_-]{1,64})$", path)
            if match:
                pending = backend.stats().get("pending", 0)
                if pending >= MAX_QUEUE:
                    self.send_json(
                        {"status": "error",
                         "reason": "queue saturated; processor should retry "
                                   "later with its own backoff"},
                        status=503,
                    )
                    return
                try:
                    body = self.read_body()
                except WebhookBridgeError as err:
                    self.send_json({"status": "error", "reason": err.message},
                                   status=err.status)
                    return
                delivery_id = "whk_%d_%s" % (
                    int(time.time() * 1000), base64.b32encode(
                        secrets.token_bytes(6)).decode("ascii")
                    .replace("=", "").lower())
                record = {
                    "delivery_id": delivery_id,
                    "channel": match.group(1),
                    "body_b64": base64.b64encode(body).decode("ascii"),
                    "headers": self.captured_headers(),
                    "received_ts": time.time(),
                    "claim": None,
                    "claim_expiry": 0,
                    "delivered": False,
                    "verdict": "",
                    "ack_detail": "",
                    "acked_ts": 0,
                }
                backend.put_delivery(record)
                self.send_json({"status": "accepted", "delivery_id": delivery_id},
                               status=202)
                return
            ack = re.match(r"^/deliveries/(whk[a-z0-9_-]{0,128})/ack$", path)
            if ack:
                try:
                    body = self.read_body()
                except WebhookBridgeError as err:
                    self.send_json({"status": "error", "reason": err.message},
                                   status=err.status)
                    return
                try:
                    parsed = json.loads(body.decode("utf-8"))
                except (UnicodeDecodeError, ValueError):
                    self.send_json({"status": "error",
                                    "reason": "ack body is not JSON"},
                                   status=400)
                    return
                if not isinstance(parsed, dict):
                    self.send_json({"status": "error",
                                    "reason": "ack body is not an object"},
                                   status=400)
                    return
                claim = str(parsed.get("claim", ""))
                verdict = str(parsed.get("verdict", ""))
                detail = str(parsed.get("detail", ""))[:256]
                if not claim:
                    self.send_json({"status": "error",
                                    "reason": "ack carries no claim"},
                                   status=400)
                    return
                if verdict not in VERDICTS:
                    self.send_json({"status": "error",
                                    "reason": "verdict must be one of "
                                              "processed|refused|expired|error"},
                                   status=400)
                    return
                result = backend.ack_delivery(ack.group(1), claim, verdict,
                                              detail)
                if result["status"] == "mismatch":
                    self.send_json({"status": "error",
                                    "reason": "claim mismatch or expired; "
                                              "another claim may hold it",
                                    "record": result["record"]},
                                   status=409)
                    return
                if result["status"] == "unknown":
                    self.send_json({"status": "error",
                                    "reason": "unknown delivery"},
                                   status=404)
                    return
                self.send_json({"status": "ok", "record": result["record"]})
                return
            self.send_json({"status": "error", "reason": "unknown endpoint"},
                           status=404)

    return Handler


def build_server(backend, host: str = "127.0.0.1", port: int = 8083,
                 max_body_bytes: int = DEFAULT_MAX_BODY,
                 claim_ttl_sec: float = DEFAULT_CLAIM_TTL) -> ThreadingHTTPServer:
    handler = build_handler(backend, max_body_bytes, claim_ttl_sec)
    return ThreadingHTTPServer((host, port), handler)
