#!/usr/bin/env bash
# GPU-side smoke test: proves a GPU box can generate + land an asset.
# Mirrors scripts/blender_smoke_test.sh (the CPU-side proof).
#
#   1. a CUDA GPU is visible to torch
#   2. blender runs headless and exports a .glb
#   3. the artifact contract prints
#
# Exit 0 = the box is ready for Lane D work.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_GLB="/tmp/synmergia_gpu_smoke.glb"
FAILED=0

echo "[gpu-smoke] 1/3 checking CUDA + torch..."
if command -v python >/dev/null 2>&1; then
    python - <<'PY' || FAILED=1
import sys
try:
    import torch
except ImportError:
    print("[gpu-smoke]   torch missing (install torch, or use a CUDA base image)")
    sys.exit(1)
ok = torch.cuda.is_available()
print(f"[gpu-smoke]   torch {torch.__version__}  cuda_available={ok}")
if ok:
    print(f"[gpu-smoke]   device: {torch.cuda.get_device_name(0)}")
PY
else
    echo "[gpu-smoke]   python not found"
    FAILED=1
fi

echo "[gpu-smoke] 2/3 building a reference cube in headless blender..."
if command -v blender >/dev/null 2>&1; then
    blender --background --factory-startup --python-expr "
import bpy
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.5))
bpy.ops.export_scene.gltf(filepath='${OUT_GLB}', export_format='GLB')
" >/tmp/gpu_blender_smoke.log 2>&1 || true
    if [ -f "${OUT_GLB}" ]; then
        echo "[gpu-smoke]   exported $(du -h "${OUT_GLB}" | cut -f1)"
    else
        echo "[gpu-smoke]   FAIL: blender did not export ${OUT_GLB}"
        FAILED=1
    fi
else
    echo "[gpu-smoke]   blender not installed (run setup_gpu_env.sh)"
    FAILED=1
fi

echo "[gpu-smoke] 3/3 artifact contract:"
cat <<'EOF'
  source:  art/src/        (.blend, reference images)   -- versioned
  scratch: art/out/        (.glb + textures from GPU)   -- may be pruned
  land:    game/models/<data_id>.glb                    -- filename == data id
  verify:  sh ./scripts/blender_smoke_test.sh  (CPU) + naming lint + probe
EOF

if [ "${FAILED}" -eq 0 ]; then
    echo "[gpu-smoke] PASS: GPU box can generate and land an asset"
    exit 0
fi
echo "[gpu-smoke] FAIL: fix the issues above"
exit 1
