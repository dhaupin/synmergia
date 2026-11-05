# DEVCODE.md — reconstructing the agent dev environment (post-teardown)

This file exists so a future session/tooling can rebuild a working
Synmergia dev loop from the repo alone, with no inherited /tmp state,
Freebuff legacy-cloud Linux install, or prior chat history. It picks up
where AGENTS.md (conventions) and README.md (product/architecture)
stop: the mechanics of actually RUNNING things.

## 1. Toolchain

- **One-command bootstrap:** `sh ./scripts/setup-dev.sh` installs the
  whole base toolchain (system libs, Godot 4.7.2, Node 20, bun) from the
  repo alone. Add `--with-templates` (web export), `--with-blender`
  (3D pipeline) or `--with-web-probe` (chromium) as needed, or `--all`
  for everything. `--dry-run` prints the resolved plan without touching
  anything. The script reads its apt package list and the Godot / Node
  version pins straight out of the `Dockerfile`, so the two never drift.
- **Godot 4.7.2 (official build)** — the version pin matters (4.7.2
  matches the `Dockerfile` build arg and the .tres format=3 writer used
  across `game/data/`). `setup-dev.sh` installs it to `~/.local/bin/godot`;
  the test runners resolve `godot` from PATH.
- **Node 20** — needed for the web-export probes (`scripts/web_probe/*.js`,
  playwright-core) and the web build (`npm run build`).
- **bun** — the repo tracks `bun.lock`; use `bun install` for deps
  (`npm install` also works). `setup-dev.sh` installs it.
- **Python 3** — for `srv/noaa_kp_sidecar.py` and model-pipeline scripts
  like `scripts/fix_clip_ranges.py` (stdlib-only, no pip installs).
- **systemctl, julia, release tools NOT needed** for the code-side dev
  loop (Julia is a sidecar only; skip it during code-only repair rounds).

### Running as a shard (multi-container)

The image runs a dev env and a single server out of the box. To run a
container as one shard of a mesh, set per container:

```bash
SHARD_ID=shard_2 SHARD_NAME=Beta IS_PRIMARY=false \
STORAGE_BACKEND=postgres CACHE_BACKEND=redis \
PG_BACKEND=postgres REDIS_BACKEND=redis \
POSTGRES_HOST=postgres REDIS_HOST=redis \
docker compose --profile headless up
```

Unset -> `shard_1`/"Alpha" and in-process memory (the single-node
default). The bridges' real backends need `python3-psycopg` /
`python3-redis` (baked into the image). See `labs/prd-shard-mesh.md`
for the intent-vs-reality audit and the phased path (cross-shard bus
and the edge transport are Phase 1+).

## 2. Golden-path commands (from `game/`)

```bash
# single probe (the only reliable unit-test idiom in this repo)
cd game && godot --headless --path . --script res://tests/probe_crafting.gd

# full default regression set (~140 probes/tests, serial)
sh ./scripts/godot_test_runner.sh            # from repo root
sh ./scripts/godot_test_runner.sh probe_crafting probe_stream_flow_100m  # named
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
1. `git clone` the repo (any machine).
2. `sh ./scripts/setup-dev.sh` — rebuilds Godot 4.7.2, Node 20, bun and
   the system libraries from the repo alone (add `--with-templates`
   / `--with-blender` / `--with-web-probe` for the optional pieces).
3. `cd game && sh ./scripts/godot_test_runner.sh probe_startup_flow` —
   this one boots the whole autoload tree end-to-end; if it passes, the
   soil's good and everything else is recoverable from code + TASKS.md.
4. Read `labs/TASKS.md` tail for recent history/lore; read
   `dev_temp/probes/` only if a specific prior fix needs re-deriving.
5. The horcrux is at `horcrux/cairn-p_windtheclock2026.svg` — restore
   into vant axolotl to recover agent memory/state (its README spells
   out the exact vant restore command and stack pinning).
