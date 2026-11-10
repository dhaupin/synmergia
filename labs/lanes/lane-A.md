You are a Synmergia subagent lane (Lane A: high-level systems). Work ONLY inside your own worktree (your cwd). Never edit /workspace/project/synmergia directly.

CONTEXT
- Synmergia is a Godot 4.7.2 MMORPG (GDScript). The live world is the spherical globe (game/scenes/worlds/globe_world.gd); the planar world is retired.
- The "door" is the game<->agent control surface: game/core/services/agent_door.gd (HTTP listener) + game/core/services/agent_driver.gd (verbs). It serves gamestruct SPEC v1.1 routes: GET /health, GET /observe, GET /events?since=N, POST /act {id,verb,value}, POST /wait_for {predicate,timeoutMs}, GET|POST /see {label}, POST /coord.
- gamestruct (npm, 1.1.0) owns the SPEC. Read node_modules/gamestruct/SPEC.md and node_modules/gamestruct/lib/adapters/synmergia.mjs (doorNodes folds the door's /observe snapshot into SPEC nodes). SPEC rules that matter: a refusal is a value {ok:false, reason} never a throw (N21); act refuses by stable handle (N1/N2); wait_for times out honestly (N3); events carry a monotonic frame cursor (N4); an interactive node has a non-empty accessible name (N6).

GOAL
Add ONE new receipt game/tests/test_agent_door_spec.gd (a SceneTree script) that boots the real globe with the door enabled (SYN_AGENT=1) and asserts SPEC conformance:
1. /health -> ok:true
2. /observe -> a snapshot whose nodes satisfy the doorNodes contract (every interactive node has a non-empty id + non-empty name)
3. /act with an unknown handle -> ok:false with a reason (refusal by stable handle)
4. /wait_for with an unsatisfiable predicate -> ok:false reason 'timeout' within the timeout (never hangs)
5. /events?since=N -> a monotonic frame cursor
6. /see -> ok + a path, or an honest refusal (never base64 on the wire)

READ game/tests/test_agent_driver.gd FIRST -- it already boots the globe and hits the door over HTTP; reuse its harness pattern (the boot, the HTTP helper, the SceneTree convention).

OWNED FILES (yours alone): game/tests/test_agent_door_spec.gd (new). Do NOT edit any other file (not the runner DEFAULT_SET, not AGENTS.md, not labs/TASKS.md).

CONSTRAINTS
- TABS for indentation in .gd (never spaces). ASCII only (no emoji / smart quotes).
- extends SceneTree; exit 0 pass / 1 fail; print an "N/0" style line.
- A fresh worktree has no .godot cache: run `godot --headless --path game --import` once first, OR `cp -r /workspace/project/synmergia/game/.godot game/.godot`. The live-driver convention is xvfb: `xvfb-run -a godot --headless --path game --script res://tests/test_agent_door_spec.gd`.

DEFINITION OF DONE
- The new receipt exits 0 with real assertions on a live boot.
- Commit in YOUR worktree with a message starting `lane-A:`.
- Report: the file, the exact run command, the pass count, and any honest gap (a SPEC leg the door does NOT yet satisfy -- report it, do not fix outside your owned file).
