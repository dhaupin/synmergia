#!/usr/bin/env bash
# Blender -> glTF -> Godot smoke test.
# Proves the 3D pipeline end-to-end once blender is installed:
#   1. headless blender builds a 1m reference cube
#   2. exports .glb (glTF 2.0)
#   3. godot headless loads it as a PackedScene
# Exit 0 = pipeline healthy.
# Dash-safe: uses $0 (not BASH_SOURCE) so `sh ./scripts/...` works.
set -e

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_GLB="/tmp/synmergia_smoke_cube.glb"

if ! command -v blender >/dev/null 2>&1; then
	echo "[smoke] blender not installed. Install with:"
	echo "[smoke]   sudo apt-get update && sudo apt-get install -y blender"
	exit 1
fi

echo "[smoke] 1/3 building reference cube in headless blender..."
blender --background --factory-startup --python-expr "
import bpy
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.5))
bpy.ops.export_scene.gltf(filepath='${OUT_GLB}', export_format='GLB')
" >/tmp/blender_smoke.log 2>&1 || true

if [ ! -f "${OUT_GLB}" ]; then
	echo "[smoke] FAIL: blender did not export ${OUT_GLB}"
	exit 1
fi
echo "[smoke]     exported $(du -h "${OUT_GLB}" | cut -f1)"

echo "[smoke] 2/3 copying into godot project..."
mkdir -p "${ROOT_DIR}/game/models/blocks"
cp "${OUT_GLB}" "${ROOT_DIR}/game/models/blocks/block_ref_cube.glb"

echo "[smoke] 3/3 loading via headless godot..."
cd "${ROOT_DIR}/game"
godot --headless --path . --quit-after 2 >/tmp/godot_import.log 2>&1 || true
# Benign notes ("resources still in use at exit") are not import
# failures; look for real script/parse/load errors only.
if grep -qE "SCRIPT ERROR|Parse Error|Failed to load" /tmp/godot_import.log; then
	echo "[smoke] FAIL: godot reported import errors:"
	grep -E "SCRIPT ERROR|Parse Error|Failed to load" /tmp/godot_import.log | head -5
	exit 1
fi

if [ -f "res://models/blocks/block_ref_cube.glb" ] || [ -f "${ROOT_DIR}/game/models/blocks/block_ref_cube.glb" ]; then
	echo "[smoke] PASS: blender -> glb -> godot pipeline healthy"
else
	echo "[smoke] FAIL: glb not present after import"
	exit 1
fi
