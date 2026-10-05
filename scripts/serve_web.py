#!/usr/bin/env python3
"""Serve the Synmergia web (WASM) export with cross-origin isolation.

The Godot web build is THREADED (SharedArrayBuffer/pthread pool), so the
browser only boots it when the page is cross-origin isolated:
	COOP:  Cross-Origin-Opener-Policy: same-origin
	COEP:  Cross-Origin-Embedder-Policy: require-corp
A plain `python3 -m http.server` sends neither, and index.html's
crossOriginIsolated gate refuses to start the engine.

stdlib-only; binds 0.0.0.0 and honors the injected PORT env var so the
managed preview (or any container) can front it.

Usage:  python3 scripts/serve_web.py   (from the repo root)
"""
import os
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

WEB_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "web")


class GodotWebHandler(SimpleHTTPRequestHandler):
	extensions_map = {
		**SimpleHTTPRequestHandler.extensions_map,
		".wasm": "application/wasm",
		".pck": "application/octet-stream",
		".js": "text/javascript",
	}

	def end_headers(self):
		self.send_header("Cross-Origin-Opener-Policy", "same-origin")
		self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
		# The pck is content-addressed via game.pck?v=<sha256> (immutable);
		# everything else should revalidate so code pushes show up.
		self.send_header("Cache-Control", "no-cache")
		super().end_headers()

	def log_message(self, fmt, *args):
		print("[serve_web] %s" % (fmt % args))


def main():
	port = int(os.environ.get("PORT", "8000"))
	httpd = ThreadingHTTPServer(("0.0.0.0", port), GodotWebHandler)
	print("[serve_web] serving %s on 0.0.0.0:%d (cross-origin isolated)" % (WEB_DIR, port))
	httpd.serve_forever()


if __name__ == "__main__":
	main()
