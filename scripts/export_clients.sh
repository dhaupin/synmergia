#!/usr/bin/env bash
## export_clients.sh -- build the web (wasm) and native clients in ONE
## command (feedback #6). The two exports used to be separate hand-runs
## with duplicated steps; this wraps both Godot export presets so a
## release is one line and the web pck and native binary always come
## from the identical source snapshot.
##
## Usage:
##   sh ./scripts/export_clients.sh                # web pck + native Linux
##   sh ./scripts/export_clients.sh --web-only     # just web/game.pck
##   sh ./scripts/export_clients.sh --native-only  # just the Linux binary
##
## Presets (game/export_presets.cfg):
##   "Web Default" -> ../web/game.pck                    (wasm shell loads this)
##   "Web"         -> ../web/game.html (manual full-html export)
##   "Linux"       -> ../builds/linux/synmergia.x86_64  (pck embedded)
##
## itch.io demo flow: run this, then upload web/ (game.html + game.pck
## + game.wasm + game.js stay from the last full web export; this
## script refreshes the content pack).

set -eu  # POSIX-safe (repo runs scripts with `sh`, not bash)

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"

WEB_ONLY=0
NATIVE_ONLY=0
for arg in "$@"; do
	case "$arg" in
		--web-only) WEB_ONLY=1 ;;
		--native-only) NATIVE_ONLY=1 ;;
		*)
			echo "usage: sh ./scripts/export_clients.sh [--web-only|--native-only]" >&2
			exit 2
			;;
	esac
done

build_web() {
	echo "== Web: exporting content pack -> web/game.pck"
	mkdir -p "$ROOT/web"
	(cd "$ROOT/game" && "$GODOT_BIN" --headless --path . \
		--export-pack "Web Default" ../web/game.pck)
	echo "== Web: done (web/game.pck)"
}

build_native() {
	echo "== Native: exporting Linux x86_64 -> builds/linux/synmergia.x86_64"
	mkdir -p "$ROOT/builds/linux"
	(cd "$ROOT/game" && "$GODOT_BIN" --headless --path . \
		--export-release "Linux" ../builds/linux/synmergia.x86_64)
	echo "== Native: done (builds/linux/synmergia.x86_64)"
}

# Web first: it is the demo-critical artifact (feedback #6 priority).
if [ "$NATIVE_ONLY" -eq 0 ]; then
	build_web
fi
if [ "$WEB_ONLY" -eq 0 ]; then
	build_native
fi

echo "All requested client exports finished."
