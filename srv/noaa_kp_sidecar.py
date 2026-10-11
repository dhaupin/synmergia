"""
noaa_stack.py -- the NOAA SWPC Kp sidecar (port 8082); only stdlib.

Polls the NOAA SWPC planetary K-index on a 5-minute cadence and serves
it as JSON for the game's CosmicService:

    GET /health                       -> {"ok": true}
    GET /kp                           -> {"kp": 1.67, "time": <unix_seconds>}

Why a sidecar: the Godot server should not make external requests on
its critical path, and NOAA's 3-hour publication cadence is slow
enough that a 5-minute sidecar poll is equivalent to live. The game
never talks to NOAA directly -- it reads OUR cache.

The most recent NOAAs planetary Kp (SWPC products/plasma_2h or the
text tabular file) is parsed from the text feed:
   https://services.swpc.noaa.gov/text/planetary_k_index_1m.txt
(fallback: 3-hour planetary_k_index_3h.txt). Both are ASCII tables.

When NOAA is unreachable, the sidecar serves the LAST SUCCESSFUL
reading with `stale: true` so CosmicService can keep weather on the
cosmic law until the frame's own staleness law demotes it.

Run: python3 srv/noaa_kp_sidecar.py
Env: NOAA_SIDECAR_HOST (default 0.0.0.0), NOAA_SIDECAR_PORT (8082),
     NOAA_KP_URL (override the upstream feed), NOAA_KP_POLL_SEC (300).
"""
from __future__ import annotations

import json
import os
import re
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

NOAA_1M_URL = "https://services.swpc.noaa.gov/text/planetary_k_index_1m.txt"
NOAA_3H_URL = "https://services.swpc.noaa.gov/text/planetary_k_index_3h.txt"

_host = os.environ.get("NOAA_SIDECAR_HOST", "0.0.0.0")
_port = int(os.environ.get("NOAA_SIDECAR_PORT", "8082"))
_poll_sec = float(os.environ.get("NOAA_KP_POLL_SEC", "300"))
_upstream = os.environ.get("NOAA_KP_URL", NOAA_1M_URL)

# Kp line in the 1-minute text feed, e.g.
# "2026-10-09 12:34:56.789  1.33  2  0 -1 ..." -- first float after the
# timestamp is observed Kp.
# Kp value in the text feeds follows the space-separated timestamp
# column. Match the date+time pair explicitly, then take the FIRST
# numeric token after it — the observed (or forecast) planetary Kp.
_TS_RE = re.compile(
    r'^\s*\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?\s+([0-9]+\.[0-9]+)'
)


class KpCache:
    """Holds the freshest successfully-parsed Kp reading."""

    def __init__(self) -> None:
        self.kp: float | None = None
        self.time: float = 0.0
        self.stale: bool = True
        self.last_error: str = ""

    def update(self, kp: float, at: float) -> None:
        self.kp = kp
        self.time = at
        self.stale = False
        self.last_error = ""


_cache = KpCache()


def _parse_kp(text: str) -> float | None:
    """Scan the text feed's lines for the LAST parseable Kp value."""
    last: float | None = None
    for line in text.splitlines():
        m = _TS_RE.match(line)
        if m:
            try:
                v = float(m.group(1))
                if 0.0 <= v <= 9.0:
                    last = v
            except (ValueError, IndexError):
                continue
    return last


def _poll_once() -> None:
    try:
        with urllib.request.urlopen(_upstream, timeout=10) as resp:
            body = resp.read().decode("utf-8", "replace")
        kp = _parse_kp(body)
        if kp is None:
            _cache.last_error = "no Kp row parsed from upstream"
            return
        _cache.update(kp, time.time())
    except Exception as exc:  # noqa: BLE001 - keep the sidecar alive
        _cache.last_error = str(exc)
        _cache.stale = True


def _poll_loop() -> None:
    while True:
        _poll_once()
        time.sleep(_poll_sec)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:  # noqa: N802 - stdlib API
        path = self.path.split("?", 1)[0]
        if path == "/health":
            body = {"ok": True}
        elif path == "/kp":
            if _cache.kp is None and _cache.kp != 0.0:
                body = {"ok": False, "error": _cache.last_error or "no reading"}
            else:
                body = {
                    "kp": _cache.kp,
                    "time": _cache.time,
                    "stale": _cache.stale,
                }
        else:
            self.send_error(404)
            return
        payload = json.dumps(body).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, fmt: str, *args: object) -> None:  # silence
        return


def main() -> int:
    import threading

    t = threading.Thread(target=_poll_loop, daemon=True)
    t.start()
    _poll_once()  # prime the cache synchronously so first read works

    httpd = ThreadingHTTPServer((_host, _port), Handler)
    print(f"noaa-kp-sidecar listening on {_host}:{_port}, poll every {_poll_sec:.0f}s")
    httpd.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
