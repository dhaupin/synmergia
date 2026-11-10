You are a Synmergia subagent lane (Lane J: the agent ROSTER panel). Work ONLY inside your own worktree (your cwd). Never edit /workspace/project/synmergia directly.

RUN `sh labs/lane_setup.sh` FIRST (idempotent: symlinks the gamestruct npm dep + warms the Godot import cache). A fresh worktree has no .godot/ cache; a receipt that runs before the import hangs on a type it cannot resolve.

CONTEXT (what just landed on this branch, commit "the agent BODY")
- The keystone gap is CLOSED: an agent is now a real PLAYER with its own body. The roster (game/core/services/agent_roster.gd) seats an agent's body and, per labs/prd-agent-play.md sec 17.2, exposes a MANUAL RE-ENABLE UX -- agents do NOT auto-respawn.
- AgentRoster API you will use (READ the file for exact shapes):
  - board(account_id) -> a dict of the account's agents + slot state (use it for the panel rows).
  - agents_of(account_id) -> Array of handles.
  - re_enable(account_id, handle) -> {ok, ...} ; re_enable_all(account_id) -> {ok, rows}. Refuses by name while the human is AFK ("...offline or AFK" / gate reason).
  - signals: agent_attached(account, handle, slot), agent_detached(account, handle), agent_seated(account, handle, party_id), agent_unseated(account, handle), agent_despawned(account, handle, entity_id), agent_despawn_refused(account, handle, reason).
- The panel must show the LIVE state per agent: attached, seated (in the party), and whether its body is in the world (AgentBodyService.body_for(handle) != null). The re-enable button calls re_enable.
- The human's account id comes from LoginService.get_current_account_id().

GOAL
Ship the AGENT ROSTER PANEL -- a human-facing surface to see + manage their agents' bodies:
1. NEW game/ui/components/agent_roster_ui.gd -- a UIPanel-style panel (extends Control; follow game/ui/components/ignore_book_ui.gd and premium_shop_ui.gd EXACTLY for the shell law: panel_closed signal, idempotent build, standard styling via UIStyles). It reads AgentRoster.board(account) and renders one row per attached agent: the handle, its seat state (seated / away / no body), and a "Re-enable" button that calls AgentRoster.re_enable(account, handle). It refreshes on the roster's own signals (no private polling re-read).
2. game/ui/components/menu_manager.gd -- add the panel as the "agents" row (mirror the existing "ignore" / "premium" rows: instance it in _setup, connect panel_closed, add to _panel_for + the close-all map). If a service gate is appropriate, mirror the "premium" _service_gate call (a "find an agent keeper / the roster service" gate); if not, keep it ungated and say so in your report.
3. NEW game/tests/test_agent_roster_panel.gd (SceneTree receipt): open the panel through MenuManager.open_menu("agents"), and assert it builds + shows a row for an attached agent and that pressing re-enable calls re_enable (drive the real button's pressed signal, or call the handler the button is wired to) and the row state follows. Boot the globe like game/tests/test_agent_party_bridge.gd does (it fakes a session + registers a real agent body).

READ FIRST (in this order): game/ui/components/ignore_book_ui.gd and game/ui/components/premium_shop_ui.gd (the UIPanel shell law), game/ui/components/menu_manager.gd (how a row is registered -- "ignore"/"premium"), game/core/services/agent_roster.gd (board/re_enable/signals), game/tests/test_agent_party_bridge.gd (how to mount a fake session + a real agent body in a receipt).

OWNED FILES (yours alone): game/ui/components/agent_roster_ui.gd (new), game/ui/components/menu_manager.gd (add ONLY the "agents" row), game/tests/test_agent_roster_panel.gd (new). Do NOT edit any other file -- not globe_world.gd (Lane H), not agent_body_service.gd / agent_driver.gd / agent_door.gd / agent_roster.gd (the frozen spine), not the runner DEFAULT_SET, not AGENTS.md, not labs/TASKS.md.

CONSTRAINTS
- TABS for indentation in .gd (never spaces). ASCII only (no emoji / smart quotes).
- UIPanel shell law: extends Control; emit panel_closed(); build idempotently; resolve services via get_node_or_null("/root/<Name>") at runtime (never parse-time preloads of game scripts).
- extends SceneTree in the receipt; exit 0 pass / 1 fail; print an "N/0" style summary line.

DEFINITION OF DONE
- The new receipt exits 0 with real assertions on a live boot.
- Commit in YOUR worktree with a message starting `lane-J:`.
- Report: the files, the exact run command, the pass count, and any honest gap.
