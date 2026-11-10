You are a Synmergia subagent lane (Lane I: the agent body over the DOOR). Work ONLY inside your own worktree (your cwd). Never edit /workspace/project/synmergia directly.

RUN `sh labs/lane_setup.sh` FIRST (idempotent: symlinks the gamestruct npm dep + warms the Godot import cache). A fresh worktree has no .godot/ cache; a receipt that runs before the import hangs on a type it cannot resolve.

CONTEXT (what just landed on this branch, commit "the agent BODY")
- The keystone gap is CLOSED: an agent is now a real PLAYER with its own body in the same world. The spine:
  - game/entities/globe_player.gd: per-body VIRTUAL INPUT. set_virtual_input(move: Vector2, sprint: bool), clear_virtual_input(), has_virtual_input(). When live, the body's movement + sprint read the virtual stick instead of the global Input singleton, so two bodies share one process without steering each other. Convention: x = strafe right, y = forward.
  - game/core/services/agent_driver.gd: act() and observe() are PRINCIPAL-aware. act(action_id, {"principal": <handle>, ...}) routes verbs to the body owned by that handle; observe(principal) reports that body (and echoes "principal" in the snapshot). A principal-less act still drives the human's seat (the global Input path).
  - game/core/services/agent_door.gd: /act and /observe pass a "principal" through to the driver.
  - game/core/services/agent_body_service.gd (autoload AgentBodyService): owns agent bodies. spawn(account_id, handle, opts) -> {ok, entity_id}; body_for(handle); despawn(handle). Bodies are real GlobeWorldPlayer nodes parented to the human's world and registered with EntityService.
  - game/core/services/agent_roster.gd: seat_agent spawns a body when none; re_enable(account_id, handle) is the manual re-enable UX.
- The live receipt that proves all this IN-PROCESS is game/tests/test_agent_body_lifecycle.gd (30/0). READ IT FIRST -- it boots the globe and exercises the driver directly. Your job is the SAME proof over the HTTP DOOR (the gamestruct wire), which the in-process receipt does not cover.

GOAL
Add ONE new receipt game/tests/test_agent_body_door_spec.gd (a SceneTree script) that boots the real globe with the door enabled (SYN_AGENT=1) and proves the body is reachable over the gamestruct wire:
1. /observe with no principal -> the snapshot's player node is the HUMAN's body id.
2. Seat an agent through the real services (AgentRoster + AgentBodyService), then /observe?principal=<handle> (or the door's observe principal arg) -> the snapshot's player node is the AGENT's body id, distinct from the human's.
3. POST /act {"id":"move","value":{...,"principal":"<handle>"}} (match the door's real arg shape -- READ agent_door.gd _act_args) -> ok:true; then the AGENT body reports has_virtual_input() true and the human body reports it false (the two-input law over the wire).
4. POST /act {"id":"stop","value":{"principal":"<handle>"}} -> ok:true; the agent body's virtual input is cleared.
5. An unknown principal is refused by name (ok:false + reason), never a throw.
Report honestly any SPEC leg the door does NOT yet satisfy; do NOT fix outside your owned file.

READ FIRST (in this order): game/tests/test_agent_body_lifecycle.gd (the harness + the service calls), game/tests/test_agent_driver.gd (the door-over-HTTP helper + SYN_AGENT boot), game/core/services/agent_door.gd (_act_args: the exact principal key + value shape), game/core/services/agent_driver.gd (act/observe/_principal/_body_for).

OWNED FILES (yours alone): game/tests/test_agent_body_door_spec.gd (new). Do NOT edit any other file -- not the runner DEFAULT_SET, not AGENTS.md, not labs/TASKS.md, not globe_world.gd (owned by Lane H).

CONSTRAINTS
- TABS for indentation in .gd (never spaces). ASCII only (no emoji / smart quotes).
- extends SceneTree; exit 0 pass / 1 fail; print an "N/0" style summary line.
- The live-driver convention is xvfb: `xvfb-run -a godot --headless --path game --script res://tests/test_agent_body_door_spec.gd`. If xvfb is unavailable, run plain headless and note the 2 known display-only see() legs do not apply to your file.
- Autoloads are real in a full boot; resolve services via get_node_or_null("/root/<Name>") (do NOT preload game scripts at parse time -- autoload names register after parse).

DEFINITION OF DONE
- The new receipt exits 0 with real assertions on a live boot.
- Commit in YOUR worktree with a message starting `lane-I:`.
- Report: the file, the exact run command, the pass count, and any honest gap.
