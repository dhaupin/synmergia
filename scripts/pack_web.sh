#!/usr/bin/env bash
set -e

# Synmergia Web Client PCK Pack Script
# Packages game/ resources into web/game.pck using Godot headless export

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
GAME_DIR="${ROOT_DIR}/game"
WEB_DIR="${ROOT_DIR}/web"

echo "=== Synmergia Web Client Resource Packager ==="
echo "Game directory: ${GAME_DIR}"
echo "Target output:  ${WEB_DIR}/game.pck"

# Locate Godot 4 binary
GODOT_BIN=""
if command -v godot &> /dev/null; then
    GODOT_BIN="godot"
elif command -v godot4 &> /dev/null; then
    GODOT_BIN="godot4"
elif [ -f "${ROOT_DIR}/tools/godot" ]; then
    GODOT_BIN="${ROOT_DIR}/tools/godot"
elif [ -f "/usr/local/bin/godot" ]; then
    GODOT_BIN="/usr/local/bin/godot"
fi

if [ -z "${GODOT_BIN}" ]; then
    echo "Warning: Godot 4.7.2 binary not found in PATH or tools/godot."
    echo "To package game.pck locally, ensure Godot 4.7.2 is installed or run with Docker:"
    echo "  docker compose run --rm synmergia godot --headless --path ${GAME_DIR} --export-pack 'Web' ${WEB_DIR}/game.pck"
    exit 1
fi

echo "Using Godot binary: ${GODOT_BIN}"
mkdir -p "${WEB_DIR}"

cd "${GAME_DIR}"
"${GODOT_BIN}" --headless --export-pack "Web" "${WEB_DIR}/game.pck"

if [ -f "${WEB_DIR}/game.pck" ]; then
    PCK_SIZE=$(du -h "${WEB_DIR}/game.pck" | cut -f1)
    echo "Successfully generated ${WEB_DIR}/game.pck (${PCK_SIZE})"
else
    echo "Error: game.pck was not generated."
    exit 1
fi
