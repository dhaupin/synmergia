# DEVCODE.md — reconstructing the agent dev environment (post-teardown)

This file exists so a future session/tooling can rebuild a working
Synmergia dev loop from the repo alone, with no inherited /tmp state,
Freebuff legacy-cloud Linux install, or prior chat history. It picks up
where AGENTS.md (conventions) and README.md (product/architecture)
stop: the mechanics of actually RUNNING things.

## 1. Toolchain

- **Godot 4.7.2 (official build)** — not guaranteed on PATH in a fresh
  container. Docker pull or grab from godotengine.org; the version pin
  matters (4.7.2 matches `Dockerfile:33` and the .tres format=3 writer
  used across `game/data/`).
- **Node 20** — only needed for the web-export probes (`scripts/web_probe/*.js`,
  playwright-core).
- **Python 3** — for `srv/noaa_kp_sidecar.py` and model-pipeline scripts
  like `scripts/fix_clip_ranges.py` (stdlib-only, no pip installs).
- **systemctl, julia, release tools NOT needed** for the code-side dev
  loop (Julia is a sidecar only; skip it during code-only repair rounds).

## 2. Golden-path commands (from `game/`)

```bash
# single probe (the only reliable unit-test idiom in this repo)
cd game && godot --headless --path . --script res://tests/probe_crafting.gd

# full default regression set (~140 probes/tests, serial)
sh ./scripts/godot_test_runner.sh            # from repo root
sh ./scripts/godot_test_runner.sh probe_crafting probe_terrain_stream  # named
sh ./scripts/godot_test_runner.sh --all      # every test_*.gd

# charset lint
godot --headless --path . --script res://tests/lint/test_lint_charset.gd
```

Non-zero exit = failure. Ignore benign `WARNING: 14 ObjectDB instances
were leaked` / `ERROR: 1 resources still in use` noise in probe tails —
that's SceneTree teardown hygiene, not a regression.

## 3. Path conventions for probes

- Headless probes live in `game/tests/probe_*.gd` and
  `game/tests/test_*.gd`. They all extend `SceneTree`, call
  `call_deferred("_run")` in `_init`, walk the autoload tree via
  `root.get_node_or_null(...)`, and `quit(0/1)` at the end.
- Frame primitives keep co-located tests at `game/core/frame/**/test_*.gd`
  (e.g. `game/core/frame/srv/test_weather.gd`) — that's an AGENTS.md
  rule, not a stray file.
- `scripts/godot_test_runner.sh` handles both (checks
  `game/tests/${t}.gd`, falls back to `game/core/frame/...`).

## 4. /tmp conventions (pre-teardown)

Probes/calibration writes go under `/tmp/syn_probe_<name>.log` and
`/tmp/<topic>_<n>.gd`. On a fresh session after any container reset,
`/tmp` is empty — that's why `dev_temp/probes/` and `dev_temp/logs/`
exist in this repo: they are the last committed snapshot of ad-hoc
scripts and probe logs for archaeology, NOT a live test directory.
Don't add run new probes there going forward; add them to
`game/tests/` instead if they turn out to be load-bearing.

## 5. Known maintenance traps (see TASKS.md for full lore)

- The data scanner (`core/frame/srv/resource_scan.gd`) is the ONE
  export-safe loader; do not reintroduce raw `ends_with(".tres")`
  scans anywhere.
- `.tres` files MUST carry `script = ExtResource("1")` under
  `[resource]` — a missing script line loads as bare Resource with
  id=null (glider_weaver_kite round proved this digs in silently).
- Any data file riding the .tres pipeline also needs to survive
  `.godot/exported/` remap in the web export; the charset lint makes
  the editorial side of this lint-safe.

## 6. If a future session finds the workspace wiped

Recovery order:
1. `git clone` the repo (any machine), `cd game/`.
2. `sh ./scripts/godot_test_runner.sh probe_startup_flow` — this one
   boots the whole autoload tree end-to-end; if it passes, the soil's
   good and everything else is recoverable from code + TASKS.md.
3. Read `labs/TASKS.md` tail for recent history/lore; read
   `dev_temp/probes/` only if a specific prior fix needs re-deriving.
4. The horcrux is at `horcrux/cairn-p_windtheclock2026.svg` — restore
   into vant axolotl to recover agent memory/state (its README spells
   out the exact vant restore command and stack pinning).
