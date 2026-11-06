# Synmergia — GPU Compute Guide (asset generation)

> **Scope:** provisioning a GPU compute surface for **asset generation**
> (3D models, textures, concept art) — the work Lane D does. This is NOT
> the game server or the web deploy; those are `DEPLOY.md` and
> `DEPLOY_WEB.md`.
>
> **Provider order:** **Google Colab first** (free, zero-setup, ships a
> GPU), then the rented-GPU providers (RunPod / Vast.ai / Lambda) as a
> later drop-in. The artifact contract in sec 2 is provider-independent —
> that is the whole point: the same generation step runs anywhere and
> the output lands the same way.

---

## 1. What actually needs a GPU (and what does not)

Do not rent a GPU for work a CPU does fine. The split:

| Task | Needs GPU? | Where it runs |
|---|---|---|
| Blender rigging / UV / export (`.blend` -> `.glb`) | **No** (CPU) | the sandbox, `blender --background` |
| The proven generator scripts (`scripts/gen_*_model.py`) | **No** (CPU) | the sandbox |
| **Image-to-3D** (concept art -> mesh: TRELLIS, Hunyuan3D-2, TripoSR, InstantMesh) | **Yes** | a GPU surface |
| **Text-to-image** (prompts -> concepts / textures: SDXL, Flux) | **Yes** | a GPU surface |
| Texture diffusion / upscaling / PBR baking | **Yes** | a GPU surface |
| Heavy **batch** Blender exports (dozens of clips) | Optional | GPU box is convenient, not required |

So the GPU surface exists for the *neural* half of the pipeline. The
deterministic half (rig, export, import, probes) stays on CPU in the
sandbox and must keep working with no GPU at all.

## 2. The artifact contract (provider-independent — read this first)

Whatever GPU box you use, the output must enter the repo the SAME way.
This is the law from `labs/prd-3d-pipeline.md` sec 2; the GPU surface
does not get to change it:

1. **Source files live outside `game/`**: `art/src/` holds `.blend`,
   source textures, and reference images. Versioned with the repo.
2. **Only exported `.glb` enters `game/models/`** — never a `.blend`,
   never a raw `.obj`/`.fbx`/`.ply`.
3. **The `.glb` filename IS the registry entry** — it must equal the
   data id (`npc_village_elder.glb`, `mount_plains_runner.glb`). No
   mapping code, ever.
4. **Pivot + scale law**: origin at the base, +Y up, 1 unit = 1 meter.
   Breaking this breaks housing grid placement.
5. **Textures**: packed into the `.glb` for props (2k max), external for
   hero assets.
6. **Rigs**: one skeleton per creature family (biped, quadruped, bird,
   fish); animations swap by skeleton id.
7. **`model_path` on the `.tres` stays EMPTY until the `.glb` exists** —
   the data-naming lint fails any `.tres` pointing at a phantom path.
8. **`labs/prd-spherical-mvp.md` sec 2.5/2.6 are locked**: no resource
   packs (the `.glb` registry + pck flow stays), and **Blender MCP is
   NOT adopted** — the python generator + `model_export_lib.py` +
   in-engine probes remain the asset path. A GPU surface that reaches
   for Blender MCP violates a locked owner decision.

**"Done" means imported and probed in-engine**, not "the render looks
good." A new model is finished when `scripts/blender_smoke_test.sh`
passes, the naming lint passes, and the in-engine probe
(`probe_blacksmith_model.gd` etc.) sees the mesh + skeleton + clips.

## 3. Google Colab (the first provider — zero setup)

Colab gives a free GPU (T4 16 GB on the free tier; L4/A100 on paid) with
CUDA + PyTorch preinstalled. It is the fastest way to *try* a suite
before renting anything.

### 3.1 The honest caveats (know these before you rely on it)

- **Free tier is ephemeral**: ~12 h session cap, disconnects on idle, and
  the VM is wiped between sessions. Nothing persists unless you mount
  **Google Drive** or clone the repo fresh each session.
- **Re-install every session**: pip installs do not survive a restart.
  The provisioning script (sec 3.3) is written to be re-run.
- **VRAM limits**: a 16 GB T4 runs TripoSR / InstantMesh / Stable Fast 3D
  comfortably; TRELLIS and Hunyuan3D-2 want more headroom and may need
  the paid L4/A100 tier or 4-bit / low-memory flags.
- **Not for secrets**: never put a token in the notebook cell text. Use
  Colab's **Secrets** pane (key icon) and read it with
  `google.colab.userdata`, so the token never lands in the `.ipynb`.

### 3.2 The workflow (concept -> mesh -> repo)

```
   prompts / concept art                .glb
        |                                |
        v                                v
  +-------------+   GPU: image-to-3D  +--------------+
  | art/src/    | ------------------> | art/out/     |
  | (refs)      |   (TRELLIS/Hunyuan) | (.glb + tex) |
  +-------------+                     +------+-------+
                                             |  download / git
                                             v
                                     game/models/<id>.glb
                                             |
                                             v
                        blender_smoke_test.sh + naming lint + in-engine probe
```

Steps:

1. **Author the reference** (an image or a text prompt) into `art/src/`.
2. **Provision** the Colab env: run `scripts/gpu/setup_gpu_env.sh`
   (sec 3.3).
3. **Generate**: run the chosen suite on the reference -> a `.glb`
   (+ textures) into `art/out/` on the GPU box.
4. **Bring it back**: download to the sandbox (or commit `art/out/` to a
   scratch branch). Land the final `.glb` in `game/models/<data_id>.glb`.
5. **Verify on CPU**: `sh ./scripts/blender_smoke_test.sh`, then the
   naming lint, then the in-engine probe. Fix the pivot/scale/naming
   here if the generator got it wrong (sec 2).
6. **Declare it**: only now set `model_path` on the `.tres`.

### 3.3 Provisioning script

`scripts/gpu/setup_gpu_env.sh` installs the GPU-side toolchain and runs a
smoke check. Mirrors `scripts/setup-dev.sh` conventions (flags, dry-run,
idempotent, re-runnable):

```bash
# on the Colab box (or any GPU host)
sh ./scripts/gpu/setup_gpu_env.sh                 # torch check + blender + base deps
sh ./scripts/gpu/setup_gpu_env.sh --with-trellis  # + TRELLIS (image-to-3D)
sh ./scripts/gpu/setup_gpu_env.sh --with-hunyuan  # + Hunyuan3D-2
sh ./scripts/gpu/setup_gpu_env.sh --with-diffusion # + SDXL/Flux (textures)
sh ./scripts/gpu/setup_gpu_env.sh --dry-run       # print the plan, install nothing
sh ./scripts/gpu/setup_gpu_env.sh --smoke-only    # just the GPU + Blender smoke check
```

The script ends by printing the **artifact contract** (sec 2) so the
person on the GPU box cannot forget where the output goes.

### 3.4 The modeling suites (what to reach for)

Image-to-3D (a picture -> a mesh):

| Suite | Best for | VRAM | Notes |
|---|---|---|---|
| **TripoSR** | fast single-image mesh | ~6–8 GB | feedforward, seconds; MIT; great first try |
| **InstantMesh** | single-image mesh | ~8 GB | fast, clean topology |
| **Stable Fast 3D** | fast textured mesh | ~7 GB | Stability; good texture bake |
| **TRELLIS** | high-quality textured mesh | ~16 GB+ | Microsoft; radiance-field based; needs headroom |
| **Hunyuan3D-2** | high-quality textured mesh | ~16–24 GB | Tencent; excellent textures; heavier |
| **DreamGaussian** | fast splat -> mesh | ~8 GB | quick previews |

Text-to-image (prompts -> concepts / texture sources): **SDXL**, **Flux**.

Pick the cheapest suite that clears the quality bar. TripoSR/InstantMesh
for iteration; TRELLIS/Hunyuan3D for hero assets.

### 3.5 Colab notebook skeleton (safe pattern)

```python
# Cell 1 — secrets (NEVER inline the token)
from google.colab import userdata
import os
os.environ["HF_TOKEN"] = userdata.get("HF_TOKEN")  # gated model downloads

# Cell 2 — repo + provisioning
!git clone https://github.com/dhaupin/synmergia.git
%cd synmergia
!sh ./scripts/gpu/setup_gpu_env.sh --with-trellis

# Cell 3 — generate (example shape; the suite's own API goes here)
!python scripts/gpu/gen_from_image.py --suite trellis \
    --image art/src/concept_wolf.png --out art/out/wolf.glb

# Cell 4 — fetch the artifact back to the sandbox, then verify on CPU
#   (download art/out/wolf.glb -> game/models/enemy_wolf.glb,
#    then: sh ./scripts/blender_smoke_test.sh + naming lint + probe)
```

## 4. Other providers (drop in later — same contract)

The artifact contract (sec 2) does not change. Only the provisioning
differs:

| Provider | Model | Why you'd pick it | Provisioning delta |
|---|---|---|---|
| **Google Colab** | free T4 / paid L4,A100 | zero setup, first try | `setup_gpu_env.sh` as-is |
| **RunPod** | per-hour pods | persistent volume, no session cap | same script; mount the volume at `/workspace` |
| **Vast.ai** | marketplace | cheapest per-hour | same script; pick a CUDA image |
| **Lambda** | on-demand A100/H100 | heavy batches, big VRAM | same script |
| **AWS / GCP** | EC2 `g5`/`g6`, GCE `L4`/`A100` | if already in that cloud | same script; you own the image |

The rule: **the script is the interface.** A new provider needs no repo
change beyond pointing `setup_gpu_env.sh` at a CUDA base image. That is
why Colab comes first — it proves the contract with zero spend.

## 5. Secrets and hygiene

- **Hugging Face token** (gated model weights): store as a Colab Secret /
  provider secret; read via env; never commit it. The repo's `.gitignore`
  should ignore any local `.env` and large scratch output.
- **`art/out/` is scratch** — the final `.glb` lands in `game/models/`;
  `art/out/` may be gitignored or pruned. Keep the repo lean.
- **Large binaries**: prefer `.glb` under a few MB; if a hero asset is
  large, note it — this repo deliberately avoids Git LFS (see
  `AGENTS.md` "No Git LFS — and why").
- **Bound the logs**: a generation run's stdout goes to a capped file,
  never an uncapped pipe (the disk-bomb lesson).

## 6. Smoke test

`sh ./scripts/gpu/gpu_smoke_test.sh` proves a GPU box is ready:

1. a CUDA GPU is visible (`torch.cuda.is_available()`),
2. Blender runs headless and exports a `.glb`,
3. the artifact-contract banner prints.

Exit 0 = the box can generate and land an asset. Same shape as
`scripts/blender_smoke_test.sh`, which stays the CPU-side proof.

## 7. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `CUDA out of memory` | model too big for the T4 | use TripoSR/InstantMesh, or a 4-bit/low-mem flag, or a bigger tier |
| pip install lost after restart | Colab is ephemeral | re-run `setup_gpu_env.sh` (it is idempotent) |
| gated model 401 | missing HF token | set the Colab Secret and `HF_TOKEN` env |
| `.glb` imports at the wrong scale/pivot | generator ignored the law | fix in Blender (origin at base, +Y up, 1m), re-export — sec 2.4 |
| naming lint fails | filename != data id | rename the `.glb` to the data id before committing |
| "Unable to open a display" | EEVEE/Workbench in headless Blender | use CYCLES + CPU (prd-3d-pipeline sec 6.5) |

---

**See also:** `labs/prd-3d-pipeline.md` (the pipeline law),
`labs/prd-art-pipeline.md` (the Lane D PRD), `DEPLOY.md` (server),
`DEPLOY_WEB.md` (web), `labs/prd-openhands-canvas.md` (Lane D's lane).
