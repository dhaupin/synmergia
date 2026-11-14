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

### Multi-iso orchestrator (Julia sidecar)

`srv/julia-bridge/` is a non-Godot HTTP service the engine reaches over
the network, exactly like the pg/redis bridges. `MultiIsoService` (autoload)
mirrors the entity roster into it and runs multi-axis intersection queries.
In a container the entrypoint starts the stdlib-only `server_lite.jl` on
`127.0.0.1:8090` automatically (dev/prod/headless/coordinator); to run it
by hand:

```bash
julia --startup-file=no --compile=min --project=srv/julia-bridge \
      srv/julia-bridge/server_lite.jl --port 8090 &
MULTI_ISO_URL=http://127.0.0.1:8090 godot --path game
```

Port 8090 (NOT 8080/8081, which are pg-bridge/redis-bridge). Fails soft:
no julia -> the engine degrades to empty results. Receipt
`game/tests/test_julia_orchestrator_live.gd` boots its own sidecar and
drives the real register -> query -> unregister cycle.

The index carries TWO spatial axes: the coarse 0..11 icosahedral VERTEX
(near-uniform, ~1/12 of the planet) AND the EXACT canonical clipmap
CHUNK (`PropChunk`: terrain face 0..19 + a barycentric cell at depth 6,
`core/frame/geometry/prop_chunk.gd`). `MultiIsoService` registers every
positioned body at both; `query_chunk(key)` / `query_chunk_at_dir(dir)`
read the fine axis and `/intersect` accepts a `chunk_key`. The chunk is
the unit "the whole online pipeline wants" (`labs/prd-clipmap.md`
sec. 12) -- player-independent, deterministic, the same cell a client
derives -- so the index answers "who is in THIS cell", not just "who is
in this twelfth of the world". Admin `/chunk` prints the sender's
canonical cell + the bodies the index holds there. Receipts:
`test_julia_orchestrator_live` (chunk legs) + `test_chunk_command`.

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
`python3-redis` (baked into the image).

The cross-shard bus (Phase 1) picks its transport from
`SHARD_BUS_BACKEND` (default: follow `CACHE_BACKEND`), so the mesh
above gets the Redis bus automatically; `SHARD_BUS_BACKEND=memory`
forces the process-local bus. A failed Redis connect falls back to
memory rather than failing the boot.

To exercise the Redis bus on ONE dev box (no Docker, no `redis-server`
-- the sidecar's default `InMemoryBackend` is stdlib-only), start the
redis-bridge and point the engine at it:

```bash
python3 srv/redis-bridge/main.py &          # listens on 127.0.0.1:8081
SHARD_BUS_BACKEND=redis \
REDIS_BRIDGE_URL=http://127.0.0.1:8081 \
godot --path game
```

`npm run preview:with-bridges` starts both bridges for you. The
receipt `game/tests/test_redis_shard_bus.gd` proves the path end to end
(it spawns its own sidecar and drives a TRUE cross-process round-trip:
one godot process subscribes and exits, another drains the message that
survived it). The `mesh` profile's real deploy uses the Redis-backed
sidecar (`REDIS_BACKEND=redis`, `redis` service) -- same engine env,
only the sidecar's backend differs.

The edge transport (Phase 2) picks the server transport from
`EDGE_TRANSPORT`: `enet` (default -- the raw UDP server, unchanged) or
`websocket` (aliases `ws`/`wss`), which lets nginx front the shard over
one L7 entry for browser + native clients. Unknown values fall back to
`enet`. The nginx `godot` upstream carries `ip_hash` (sticky routing),
and `GODOT_UPSTREAM` accepts a comma/space list of shard hosts (one
`server` line per shard).

The topology (Phase 3) is an opt-in `mesh` compose profile: a
`coordinator` service + N `shard` services over shared Postgres/Redis.

```bash
docker compose --profile mesh up --build --scale shard=4
```

The role is resolved from the env by `core/mesh/mesh_role.gd`:
`START_MODE=coordinator` -> coordinator (no game port); `SHARD_ID` set
(or `START_MODE` in prod/headless/server) -> shard; otherwise
`standalone`. Each shard derives a unique id from its container
`HOSTNAME` when `MESH_AUTOSHARD=true` and `SHARD_ID` is unset, so
`--scale shard=N` needs no per-replica id (set `SHARD_ID` to pin one).
The registry spans processes: a shard announces on the bus's
`coordinator:mesh` topic and a coordinator in another process ingests
it. See `labs/prd-shard-mesh.md` for the intent-vs-reality audit and
the phased path.

The edge proxy (Phase 3.1) is `START_MODE=edge`: nginx only, no Godot
and no game port of its own. It fronts the shard replicas with the
`ip_hash` upstream (`GODOT_UPSTREAM`, default `shard:9000`), so a
WebSocket upgrade and the client's follow-up requests stay on one
shard. The `mesh` profile defines an `edge` service publishing
`${EDGE_HTTP_PORT:-8088}` / `${EDGE_HTTPS_PORT:-8443}`.

Per-shard tuning (Phase 3.1) is a LOCAL read, never a shared write.
Set the shard parameter on that shard's state tree:
`level_cap_override` (int) or `xp_ratio_override` (float). `LevelCurve`
reads it through `ShardTuning` at boot (and re-applies on the param's
`param_applied`), so a running shard's numbers flip without a reboot.
Absent an override every shard runs the uniform curve.

## 2. Golden-path commands (from `game/`)

```bash
# single probe (the only reliable unit-test idiom in this repo)
cd game && godot --headless --path . --script res://tests/probe_crafting.gd

# full default regression set (concurrent when it helps, serial when faster)
sh ./scripts/godot_test_runner.sh            # from repo root
sh ./scripts/godot_test_runner.sh probe_crafting probe_stream_flow_100m  # named
sh ./scripts/godot_test_runner.sh --all      # every test_*.gd (tests/ + core/frame/), parallel
sh ./scripts/godot_test_runner.sh --all -j 8 # more workers (capped at 2x cores / RAM)
sh ./scripts/godot_test_runner.sh --resume /tmp/led  # carry a killed run on

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
  `game/tests/${t}.gd`, falls back to `game/core/frame/...`). It is the
  ONE runner: `scripts/godot_test_parallel.sh` is now a deprecated shim
  that forwards here (the parallel engine -- warm import, JOBS, the
  timing-sensitive serial phase, `--resume` -- lives in the one script).

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

---

**See also:** [README.md](./README.md) (product + architecture) ·
[AGENTS.md](./AGENTS.md) (code conventions) · [CONTRIBUTING.md](./CONTRIBUTING.md)
(setup, tests, PRs) · [DEPLOY.md](./DEPLOY.md) (server) ·
[DEPLOY_WEB.md](./DEPLOY_WEB.md) (web) · [CREDITS.md](./CREDITS.md) ·
[LICENSE](./LICENSE).
