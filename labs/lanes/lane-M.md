You are a Synmergia subagent lane (Lane M: the Sundered Strait -- re-verify + install the authored terrain backend). Work ONLY inside your own worktree (your cwd). Never edit /workspace/project/synmergia directly.

FIRST, run the lane setup (idempotent -- warms the Godot import cache a fresh worktree lacks, and links the gamestruct dep):
  sh labs/lane_setup.sh

Godot is NOT on PATH. Use it via:
  export PATH=/workspace/.tools/godot:$PATH
  godot --version   # expect 4.7.2.stable

CONTEXT
- Synmergia is a Godot 4.7.2 MMORPG on a 20 km sphere. The ground is an analytic heightfield law `TerrainGen` (game/scenes/worlds/terrain_gen.gd). There is an EXTERNAL TERRAIN BACKEND SEAM: a WorldData may declare `terrain_backend_id`, and globe_world.gd loads `res://scenes/worlds/backend_<id>.gd` and installs its Callable as the raw heightfield. The backend COMPOSES over `TerrainGen._natural_raw(dir, seed)` (the home geology) rather than reimplementing it.
- `game/scenes/worlds/backend_sundered.gd` (`class_name TerrainBackendSundered`) AUTHORS the Sundered Strait: a navigable channel from the ferry moat ring out to open water, two headlands, a wreck-shoal ford. It is the S14.7 "Sundered Sea" content pass.
- THE DRIFT (documented in labs/TASKS.md + labs/prd-terrain.md): the backend is AUTHORED BUT DORMANT. `game/data/worlds/world_main.tres` has `terrain_backend_id = ""` (empty), so the strait never carves -- yet the world's CONTENT still references it: `game/data/zones/zone_sundered_sea.tres`, `game/data/gateways/waypoint_strait_seaward.tres`, `game/data/gateways/waypoint_shipwreck_quay.tres`, `game/core/services/strait_chart.gd`, `game/entities/harbor_lights.gd`, `game/entities/ferry_vessel.gd`, `quest_tide_markers`, `quest_shoal_freight`, and more.
- IMPORTANT: the parent lane just changed `terrain_gen.gd` (added v12 polar caps + a `_cove_window` reach-gate). The backend composes over `_natural_raw`, so your FIRST job is to re-verify it still composes cleanly at the current HEAD.

TASK (verify first, then install -- do NOT install blindly)
1. RE-VERIFY `backend_sundered.gd` at the current HEAD: does `TerrainBackendSundered`'s Callable still return finite, sane raw heights over the whole sphere (a fibonacci sweep)? Does the strait actually carve (the corridor floor below sea, the headlands above, the shoal mid-channel)? Write a probe `game/tests/probe_sundered_backend.gd` that installs the backend via the real seam (`TerrainGen` install path used by globe_world.gd -- read it), samples the strait chart, and asserts: corridor is navigable (below sea), headlands are dry, the shoal is a wet ford, the field is finite everywhere, and the spawn dome + polar caps are UNCHANGED by the backend (the compose law: a far strait must not move the home continent or the poles). Exit 0 = pass.
2. INSTALL it: set `terrain_backend_id = "sundered"` in `game/data/worlds/world_main.tres`. Confirm the boot still resolves (the boot's own face, the spawn plaza, the ground law) with the backend live.
3. RECONCILE the content: the strait's zone/gateways/quests should reference a strait that now EXISTS. Check `zone_sundered_sea.tres` (its `zone_center` -- the data-naming law says zones are bare `zone_` ids; verify any center/bounds now land on the carved strait) and the two gateways. Fix ONLY what is broken (do not redesign). If a fix needs a schema field that does not exist, REPORT it instead of inventing it.
4. If -- and only if -- measurement shows the backend BREAKS something (e.g. it moves the home continent, breaks the ground-law audit, or carves through the spawn), then DO NOT install: revert the .tres change, write your findings, and report the blocker with numbers. Honest "it does not compose cleanly yet" is a valid, valuable outcome.

CONSTRAINTS (avoid file collisions with the parent lane)
- The PARENT owns `game/scenes/worlds/terrain_gen.gd`. Do NOT edit it -- read it freely. If you believe it needs a change, REPORT the exact change; do not make it.
- Do NOT edit `game/scenes/worlds/globe_terrain_streamer.gd`, `game/scenes/worlds/globe_world.gd`, or `game/entities/*.gd` (another lane owns those this round).
- Do NOT edit `labs/TASKS.md`, `AGENTS.md`, `labs/lanes/*`, or the runner DEFAULT_SET.
- YOUR files: `game/scenes/worlds/backend_sundered.gd`, `game/data/worlds/world_main.tres`, `game/data/zones/zone_sundered_sea.tres`, `game/data/gateways/waypoint_strait_*.tres`, and a NEW probe `game/tests/probe_sundered_backend.gd`.

THE GATE (must stay green)
  export PATH=/workspace/.tools/godot:$PATH
  cd game
  godot --headless --path . --script res://tests/probe_sundered_backend.gd > /tmp/m_sundered.log 2>&1; echo "exit $?"; tail -6 /tmp/m_sundered.log
  godot --headless --path . --script res://tests/probe_ground_law_audit.gd > /tmp/m_audit.log 2>&1; echo "exit $?"; tail -4 /tmp/m_audit.log
  godot --headless --path . --script res://tests/probe_starter_village.gd > /tmp/m_village.log 2>&1; echo "exit $?"; tail -4 /tmp/m_village.log
  godot --headless --path . --script res://tests/test_data_naming_lint.gd > /tmp/m_lint.log 2>&1; echo "exit $?"; tail -4 /tmp/m_lint.log
All four MUST exit 0. Model your probe on probe_ground_law_audit.gd (drain the derive lane before quitting -- the shutdown-fence law).

DEFINITION OF DONE
- The strait composes cleanly and is installed (or a measured blocker is reported, with the .tres left uninstalled).
- The four gates above exit 0.
- Commit in YOUR worktree with a message starting `lane-M:`.
- Report: whether the backend composes cleanly at HEAD (with numbers), what you installed/changed, the gate results, and anything you could NOT verify headless. Be honest.
