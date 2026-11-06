#!/usr/bin/env bash
# Synmergia GPU-side environment bootstrap (Lane D: asset generation).
#
# Provisions a GPU compute surface (Google Colab first; RunPod/Vast/
# Lambda later) with the toolchain asset generation needs: a working
# CUDA/PyTorch, headless Blender, and the optional modeling suites.
# Colab is EPHEMERAL -- pip installs do not survive a restart, so this
# script is written to be re-run every session (every step checks first
# and skips what is already present).
#
# The artifact contract is printed at the end (and lives in
# DEPLOY-GPU.md sec 2). This script is the INTERFACE: a new provider
# needs no repo change beyond pointing it at a CUDA base image.
#
# Usage:
#   sh ./scripts/gpu/setup_gpu_env.sh                  # torch check + blender + base deps
#   sh ./scripts/gpu/setup_gpu_env.sh --with-trellis   # + TRELLIS (image-to-3D)
#   sh ./scripts/gpu/setup_gpu_env.sh --with-hunyuan   # + Hunyuan3D-2
#   sh ./scripts/gpu/setup_gpu_env.sh --with-diffusion # + SDXL/Flux (textures)
#   sh ./scripts/gpu/setup_gpu_env.sh --all            # all three suites
#   sh ./scripts/gpu/setup_gpu_env.sh --smoke-only     # just the GPU + Blender smoke check
#   sh ./scripts/gpu/setup_gpu_env.sh --dry-run        # print the plan, install nothing
#
# Needs no sudo on Colab (everything is user-level pip / conda).

# ── Bash re-exec ───────────────────────────────────────────────────────────
if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi

# ── Args ───────────────────────────────────────────────────────────────────
WITH_TRELLIS=0
WITH_HUNYUAN=0
WITH_DIFFUSION=0
SMOKE_ONLY=0
DRY_RUN=0

usage() { awk 'NR>1 && /^#/ { sub(/^# ?/, ""); print; next } NR>1 { exit }' "$0"; exit 0; }

while [ $# -gt 0 ]; do
    case "$1" in
        --with-trellis)   WITH_TRELLIS=1 ;;
        --with-hunyuan)   WITH_HUNYUAN=1 ;;
        --with-diffusion) WITH_DIFFUSION=1 ;;
        --all)            WITH_TRELLIS=1; WITH_HUNYUAN=1; WITH_DIFFUSION=1 ;;
        --smoke-only)     SMOKE_ONLY=1 ;;
        --dry-run)        DRY_RUN=1 ;;
        -h|--help)        usage ;;
        *) echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
    esac
    shift
done

# ── Paths ──────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# ── Helpers ────────────────────────────────────────────────────────────────
log() { printf '[gpu] %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

run() {
    if [ "${DRY_RUN}" -eq 1 ]; then
        printf '[dry-run] %s\n' "$*"
        return 0
    fi
    "$@"
}

pip_install() {
    if [ "${DRY_RUN}" -eq 1 ]; then
        printf '[dry-run] pip install %s\n' "$*"
        return 0
    fi
    python -m pip install --quiet "$@" || python -m pip install "$@"
}

# ── CUDA / PyTorch check ───────────────────────────────────────────────────
check_cuda() {
    if ! have python; then
        log "python not found -- install python3 first (Colab ships it)"
        return 1
    fi
    if [ "${DRY_RUN}" -eq 1 ]; then
        printf '[dry-run] python -c "import torch; print(torch.cuda.is_available())"\n'
        return 0
    fi
    python - <<'PY'
import sys
try:
    import torch
except ImportError:
    print("[gpu] torch NOT installed -- run with a CUDA base image or pip install torch")
    sys.exit(1)
print(f"[gpu] torch {torch.__version__}  cuda_available={torch.cuda.is_available()}")
if torch.cuda.is_available():
    print(f"[gpu]   device: {torch.cuda.get_device_name(0)}")
    print(f"[gpu]   vram:   {torch.cuda.get_device_properties(0).total_memory // (1024**3)} GB")
else:
    print("[gpu] WARNING: no CUDA device visible -- generation will be CPU-slow or fail")
PY
}

# ── Blender (headless, for rig/export + smoke) ─────────────────────────────
install_blender() {
    if have blender; then
        log "blender already present: $(blender --version 2>/dev/null | head -1)"
        return 0
    fi
    log "installing blender (headless DCC for rig/export)"
    if have apt-get && [ "$(id -u)" -eq 0 ]; then
        run apt-get update
        run apt-get install -y blender
    elif have conda; then
        run conda install -y -c conda-forge blender
    else
        log "no apt (as root) or conda -- install blender manually, then re-run"
        return 1
    fi
}

# ── Modeling suites (each opt-in; heavy) ───────────────────────────────────
install_base_deps() {
    log "installing base python deps (numpy, pillow, trimesh, huggingface_hub)"
    pip_install numpy pillow trimesh huggingface_hub
}

install_trellis() {
    log "installing TRELLIS (Microsoft image-to-3D; wants ~16 GB VRAM)"
    pip_install "git+https://github.com/microsoft/TRELLIS.git" || \
        log "TRELLIS install failed -- check CUDA/torch version compatibility"
}

install_hunyuan() {
    log "installing Hunyuan3D-2 (Tencent image-to-3D; wants ~16-24 GB VRAM)"
    pip_install "git+https://github.com/Tencent/Hunyuan3D-2.git" || \
        log "Hunyuan3D install failed -- check CUDA/torch version compatibility"
}

install_diffusion() {
    log "installing diffusion stack (SDXL / Flux for textures + concept art)"
    pip_install diffusers transformers accelerate safetensors
}

# ── Smoke ──────────────────────────────────────────────────────────────────
run_smoke() {
    if [ "${DRY_RUN}" -eq 1 ]; then
        printf '[dry-run] sh %s\n' "${SCRIPT_DIR}/gpu_smoke_test.sh"
        return 0
    fi
    log "running the GPU smoke test"
    sh "${SCRIPT_DIR}/gpu_smoke_test.sh"
}

# ── The artifact contract (printed so nobody forgets where output goes) ─────
print_contract() {
    cat <<'EOF'

---------------------------- ARTIFACT CONTRACT ----------------------------
  source:  art/src/        (.blend, reference images)   -- versioned
  scratch: art/out/        (.glb + textures from GPU)   -- may be pruned
  land:    game/models/<data_id>.glb                    -- filename == data id
  law:     origin at base, +Y up, 1 unit = 1 meter
  verify:  sh ./scripts/blender_smoke_test.sh  (CPU) + naming lint + probe
  NEVER:   commit a .blend into game/, or point a .tres at a phantom .glb
  LOCKED:  no resource packs; Blender MCP NOT adopted (prd-spherical-mvp sec 2)
---------------------------------------------------------------------------
EOF
}

# ── Run ────────────────────────────────────────────────────────────────────
log "Synmergia GPU environment bootstrap (repo: ${REPO_ROOT})"
[ "${DRY_RUN}" -eq 1 ] && log "DRY RUN -- nothing will be installed"

check_cuda
if [ "${SMOKE_ONLY}" -eq 1 ]; then
    run_smoke
    print_contract
    exit 0
fi

install_base_deps
install_blender
[ "${WITH_TRELLIS}" -eq 1 ]   && install_trellis
[ "${WITH_HUNYUAN}" -eq 1 ]   && install_hunyuan
[ "${WITH_DIFFUSION}" -eq 1 ] && install_diffusion

# ── Summary ────────────────────────────────────────────────────────────────
echo
log "toolchain summary"
for tool in python blender; do
    if have "$tool"; then
        printf '  %-8s %s\n' "$tool:" "$("$tool" --version 2>&1 | head -1)"
    else
        printf '  %-8s (not installed)\n' "$tool:"
    fi
done
printf '  %-8s trellis=%s hunyuan=%s diffusion=%s\n' \
    "suites:" "${WITH_TRELLIS}" "${WITH_HUNYUAN}" "${WITH_DIFFUSION}"

run_smoke
print_contract
