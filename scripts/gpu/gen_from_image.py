#!/usr/bin/env python3
"""GPU-side asset generation helper (Lane D).

Two honest modes:

  1. SUITE MODE -- run an image-to-3D suite on a reference image:
       python scripts/gpu/gen_from_image.py --suite triposr \
           --image art/src/concept_wolf.png --name enemy_wolf --height 1.2

     The suite adapters are thin; each calls the suite's own API. If the
     suite is not installed, the adapter says exactly how to install it
     (never a silent fake). The produced mesh is then normalized (below).

  2. NORMALIZE MODE -- fix an already-generated mesh to the artifact
     contract (this is the part generators get wrong, and it is fully
     implemented here):
       python scripts/gpu/gen_from_image.py --normalize art/out/raw.glb \
           --name enemy_wolf --height 1.2

     Law (DEPLOY-GPU.md sec 2 / labs/prd-3d-pipeline.md sec 2):
       - origin at the base (min Y == 0)
       - +Y up, 1 unit == 1 meter
       - output filename == the data id, written as .glb into game/models/
         (or --out for a scratch path)

Nothing here downloads model weights automatically; a suite's first run
will fetch them (set HF_TOKEN for gated ones).
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    import trimesh
except ImportError:
    print("[gen] trimesh is required: pip install trimesh", file=sys.stderr)
    sys.exit(1)


REPO_ROOT = Path(__file__).resolve().parents[2]
MODELS_DIR = REPO_ROOT / "game" / "models"
SCRATCH_DIR = REPO_ROOT / "art" / "out"


# --------------------------------------------------------------------------
# Suite adapters. Each returns a path to a raw mesh on disk (any format
# trimesh can load); normalization happens after. Adapters raise a clear,
# actionable error if their suite is missing -- no silent fallback.
# --------------------------------------------------------------------------
def _suite_triposr(image: Path) -> Path:
    try:
        from tsr.system import TSR  # type: ignore
    except ImportError as exc:
        raise RuntimeError(
            "TripoSR not installed. On the GPU box run:\n"
            "  pip install git+https://github.com/VAST-AI-Research/TripoSR.git\n"
            "then re-run. (TripoSR wants ~6-8 GB VRAM.)"
        ) from exc
    # The suite's own call goes here (model load + image -> mesh export).
    raise RuntimeError(
        "TripoSR adapter is a hook: wire model = TSR.from_pretrained(...) and "
        "export the mesh to art/out/, then call this script in --normalize mode. "
        "See DEPLOY-GPU.md sec 3.4."
    )


def _suite_instantmesh(image: Path) -> Path:
    raise RuntimeError(
        "InstantMesh not wired. Install per DEPLOY-GPU.md sec 3.4, export a mesh "
        "to art/out/, then run --normalize."
    )


def _suite_trellis(image: Path) -> Path:
    raise RuntimeError(
        "TRELLIS not wired. Install with "
        "'sh ./scripts/gpu/setup_gpu_env.sh --with-trellis', export a mesh to "
        "art/out/, then run --normalize. (TRELLIS wants ~16 GB VRAM.)"
    )


def _suite_hunyuan(image: Path) -> Path:
    raise RuntimeError(
        "Hunyuan3D-2 not wired. Install with "
        "'sh ./scripts/gpu/setup_gpu_env.sh --with-hunyuan', export a mesh to "
        "art/out/, then run --normalize. (Wants ~16-24 GB VRAM.)"
    )


SUITES = {
    "triposr": _suite_triposr,
    "instantmesh": _suite_instantmesh,
    "trellis": _suite_trellis,
    "hunyuan": _suite_hunyuan,
}


# --------------------------------------------------------------------------
# Normalization -- the artifact contract, implemented for real.
# --------------------------------------------------------------------------
def normalize_to_contract(mesh_path: Path, name: str, height: float,
                          out: Path | None) -> Path:
    """Load a mesh, apply the pivot/scale/axis law, write game/models/<name>.glb.

    - scale so the mesh's height (Y extent) == `height` meters
    - drop it so min Y == 0 (origin at the base)
    - center X/Z at 0
    - export as .glb (Y-up; trimesh writes glTF Y-up by default)
    """
    loaded = trimesh.load(str(mesh_path), force="mesh")
    if isinstance(loaded, trimesh.Scene):
        # flatten a scene into a single mesh for a prop/creature export
        loaded = trimesh.util.concatenate(
            [g for g in loaded.geometry.values()]
        )
    mesh = loaded
    if mesh.is_empty:
        raise RuntimeError(f"loaded mesh is empty: {mesh_path}")

    bounds = mesh.bounds
    extent = bounds[1] - bounds[0]
    if extent[1] <= 1e-9:
        raise RuntimeError("mesh has zero height; cannot scale to meters")

    scale = height / float(extent[1])
    mesh.apply_scale(scale)

    bounds = mesh.bounds
    # origin at the base, centered on X/Z
    mesh.apply_translation([
        -(bounds[0][0] + bounds[1][0]) / 2.0,
        -bounds[0][1],
        -(bounds[0][2] + bounds[1][2]) / 2.0,
    ])

    target = out if out is not None else (MODELS_DIR / f"{name}.glb")
    target.parent.mkdir(parents=True, exist_ok=True)
    mesh.export(str(target), file_type="glb")
    print(f"[gen] normalized -> {target}  (height {height} m, base at origin)")
    return target


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------
def main() -> int:
    ap = argparse.ArgumentParser(description="Lane D asset generation helper.")
    ap.add_argument("--suite", choices=sorted(SUITES),
                    help="image-to-3D suite to run on --image")
    ap.add_argument("--image", type=Path, help="reference image (art/src/...)")
    ap.add_argument("--normalize", type=Path,
                    help="normalize an existing mesh to the artifact contract")
    ap.add_argument("--name", required=True, help="data id (filename == id)")
    ap.add_argument("--height", type=float, default=1.0,
                    help="target height in meters (default 1.0)")
    ap.add_argument("--out", type=Path,
                    help="output path (default game/models/<name>.glb)")
    args = ap.parse_args()

    if args.normalize is not None:
        normalize_to_contract(args.normalize, args.name, args.height, args.out)
        return 0

    if args.suite is None or args.image is None:
        ap.error("either --normalize MESH, or --suite + --image, is required")
    if not args.image.exists():
        print(f"[gen] reference image not found: {args.image}", file=sys.stderr)
        return 2

    SCRATCH_DIR.mkdir(parents=True, exist_ok=True)
    try:
        raw = SUITES[args.suite](args.image)
    except RuntimeError as exc:
        print(f"[gen] {exc}", file=sys.stderr)
        return 1
    normalize_to_contract(raw, args.name, args.height, args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
