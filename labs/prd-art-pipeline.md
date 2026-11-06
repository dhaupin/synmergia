# PRD -- Lane D: Asset / Art Pipeline (modeling, textures, GPU generation)

> **Status:** SCOPED 2026-11-06. The provisioning + contract are shipped
> (`DEPLOY-GPU.md`, `scripts/gpu/`); the suite adapters are honest hooks
> that need their per-suite bodies filled on a real GPU box.
>
> **Law it obeys:** `labs/prd-3d-pipeline.md` (the pipeline law),
> `DEPLOY-GPU.md` (the GPU surface + artifact contract), and the locked
> decisions in `labs/prd-spherical-mvp.md` sec 2.5/2.6 (no resource
> packs; Blender MCP NOT adopted).

## 1. What Lane D is

Lane D is the asset lane: it turns a reference (concept art, a prompt, a
description) into a shipped `.glb` (or texture) in `game/models/`, and it
runs for a LONG time -- model generation and Blender batch exports are
minutes-to-hours. That unbounded runtime is exactly why it is its own
lane: it must never block the code lanes (A/B/C).

## 2. The two halves (CPU vs GPU)

| Half | Runs on | Tools | Must work with no GPU? |
|---|---|---|---|
| Deterministic: rig, UV, export, import, probes | CPU (the sandbox) | Blender + `scripts/gen_*_model.py` + `model_export_lib.py` | **YES** -- this is the proven path and the floor |
| Neural: image-to-3D, text-to-image, texture diffusion | GPU surface | `scripts/gpu/` + a suite | No -- it is an ACCELERATOR, not a dependency |

The CPU path is the contract. The GPU path only adds generation muscle;
if the GPU box is gone tomorrow, every committed asset still imports and
every probe still passes.

## 3. The GPU surface (Colab first)

Provisioning + the artifact contract live in `DEPLOY-GPU.md`. Summary:

- **First provider: Google Colab** (free T4; zero setup). Ephemeral --
  re-run `scripts/gpu/setup_gpu_env.sh` each session.
- **Later: RunPod / Vast / Lambda / cloud** -- same script, same contract.
  The script IS the interface.
- **Artifacts** flow `art/src/` (references, tracked) -> GPU -> `art/out/`
  (scratch, gitignored) -> `game/models/<data_id>.glb` (tracked).

## 4. The suites (what to reach for)

Image-to-3D: **TripoSR** (fast, ~6-8 GB), **InstantMesh** (~8 GB),
**Stable Fast 3D** (~7 GB), **TRELLIS** (~16 GB), **Hunyuan3D-2**
(~16-24 GB), **DreamGaussian** (~8 GB). Text-to-image: **SDXL**, **Flux**.

Rule: cheapest suite that clears the quality bar. TripoSR/InstantMesh to
iterate; TRELLIS/Hunyuan3D for hero assets.

## 5. What is shipped vs what is a hook

SHIPPED (works today, no GPU needed to verify):
- `DEPLOY-GPU.md` -- the provider-agnostic guide (Colab worked path).
- `scripts/gpu/setup_gpu_env.sh` -- provisioning (flags, dry-run,
  idempotent; mirrors `setup-dev.sh`). `bash -n` clean; dry-run verified.
- `scripts/gpu/gpu_smoke_test.sh` -- the box-ready proof.
- `scripts/gpu/gen_from_image.py` -- the generation helper. **The
  `--normalize` path is fully implemented and verified**: it scales a
  mesh to a target height, drops it to base-at-origin, centers X/Z, and
  writes `game/models/<name>.glb`. (Verified: a 3 m mesh floating at
  Y=5, off-center -> exactly 1.2 m tall, base at 0, centered.)
- `art/src/` (tracked) + `art/out/` (gitignored).

HOOKS (need a real GPU box to fill in):
- The suite adapters in `gen_from_image.py` (`_suite_triposr` etc.) call
  the suite's own API. Each raises an actionable install message when the
  suite is absent -- **never a silent fake**. Filling one in is the first
  GPU-box task.

## 6. The receipt

An asset is DONE when, on CPU:
1. `sh ./scripts/blender_smoke_test.sh` passes (chain healthy),
2. `tests/test_data_naming_lint.gd` passes (filename == data id, no
   phantom `.tres` refs),
3. the in-engine probe sees the mesh + skeleton + clips
   (`probe_blacksmith_model.gd` shape).
"Looks good in the render" is not a receipt.

## 7. Next steps

1. On a Colab box: `sh ./scripts/gpu/setup_gpu_env.sh --smoke-only`, then
   fill in ONE adapter (TripoSR is the cheapest) end-to-end on a real
   reference, and land a test `.glb`.
2. Add `scripts/gpu/README.md` once a suite is proven (the per-suite
   quirks belong there, next to the code).
3. Decide the first real asset to generate (a mount? a dungeon boss?).
