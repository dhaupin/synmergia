# Web probe rig: playwright-core + chromium against the live WASM export

The acceptance vehicle for the Accessibility + Agent-Action layer
(`labs/prd-accessibility.md`). The probes boot the REAL web export in a
real chromium, consume the A11yService `[A11Y]` JSON stream from the
browser console, and act by action name at the rects the game itself
reports -- zero hardcoded coordinates; the oracles are the game's own
log marks.

Built and proven across R32-R33 (engine boot + sandbox GL recipe), R35
(the full menu -> world journey by action name), and R37 (in-world
entity entries).

## Layout

| File | What it does |
|------|--------------|
| `probe_boot.js` | Boot smoke: serves `web/`, launches chromium, waits for canvas + cross-origin isolation + the Godot banner. Exit 0 = the engine booted. |
| `probe_a11y.js` | Full journey: Start -> Guest -> Create New -> species -> class -> Enter World (each hop verified by log marks), pause/resume, then the in-world entity step (spawn-dependent, reported not hard-failed). |

## Setup

1. Node 18+ (22 tested).
2. `bun install` (or `npm install`) in this directory for
   `playwright-core`.
3. A chromium build. playwright-core resolves its browser cache
   automatically (`~/.cache/ms-playwright`); override with
   `PROBE_CHROME=/path/to/chrome`.
4. Headless sandboxes need software GL (the R32/R33 recipe):
   `apt-get install -y xvfb mesa-vulkan-drivers` -- lavapipe gives
   ANGLE/SwiftShader a working Vulkan ICD; run chrome headed under
   Xvfb with the flags the probes pass
   (`--no-sandbox --disable-dev-shm-usage --disable-gpu-sandbox
   --enable-unsafe-swiftshader`). Forcing `--use-angle=swiftshader` is
   what BROKE it; do not add it.

## Run (from the repo root)

    sh scripts/pack_web.sh                           # refresh web/game.pck
    xvfb-run -a node scripts/web_probe/probe_boot.js
    xvfb-run -a node scripts/web_probe/probe_a11y.js

## Env vars

| Var | Default | Purpose |
|-----|---------|---------|
| `PROBE_CHROME` | playwright browser cache | chromium binary to launch |
| `PROBE_PORT` | 8134 (boot: 8123) | local static server port |
| `PROBE_WEB` | `<cwd>/web` | export directory to serve |

## What PASS means

- **boot**: canvas created + `window.crossOriginIsolated` +
  `Godot Engine v` banner in the console.
- **a11y journey**: every hop verified by the game's own marks
  (`Click: StartButton`, `Click: GuestButton`, `Linked new character`,
  world registration) plus zero SCRIPT ERROR / pageerror lines; the
  `[A11Y]` stream announced the actions that were clicked. The entity
  step reports whether `kind=entity` entries ("Attack <name>") were
  announced and activates one if so; the damage path itself is pinned
  by `game/tests/test_a11y_service.gd` with hard assertions.

## Known sandbox limitation

At 2-4 fps software GL the world-registration mark can land outside the
wait window (wasm stdout batching); screenshots in `/tmp/syn_a1_*.png`
and `/tmp/syn_wasm*.png` are the forensics. On a GPU-capable machine
the same commands complete the full journey.

`scripts/serve_web.py` is the repo's manual static server (same COOP/
COEP headers) for browsing the export by hand.
