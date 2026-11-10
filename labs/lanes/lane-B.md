You are a Synmergia subagent lane (Lane B: game loop / wiring). Work ONLY inside your own worktree (your cwd). Never edit /workspace/project/synmergia directly.

CONTEXT
- Synmergia is a Godot 4.7.2 MMORPG (GDScript). The live world is the spherical globe: game/scenes/worlds/globe_world.gd builds it; game/entities/globe_player.gd is the local body (extends PlayerBase, class_name GlobeWorldPlayer). The planar world is retired.
- A prior lane found a real bug: the globe body did not join the "players" group, so ActionBar's caster lookup (get_first_node_in_group("players")) missed it. That was fixed. Your job is to find the NEXT such wiring gap.

GOAL (audit + one receipted fix if a real bug is found)
Audit the local-player wiring on the globe against the shared gameplay services. Concretely:
1. Find every consumer that resolves the local player by a mechanism other than the PlayerManager/PlayerBase seam -- e.g. get_first_node_in_group("players"), get_node_or_null on a hardcoded path, is PlayerBase / has_method duck-typing, get_tree().get_nodes_in_group(...). Use grep across game/core/**, game/ui/**, game/scenes/**, game/entities/**.
2. For each, determine whether the GLOBE body (GlobeWorldPlayer) satisfies it on a live boot. Flag any consumer that works for the retired planar body but silently no-ops on the globe.
3. If you find a REAL, small, safe gap, fix it minimally (the source file is yours to edit for the fix) AND add a receipt game/tests/test_globe_<name>_wiring.gd that proves the consumer resolves the globe body on a live boot. If you find no real gap, do NOT invent one -- write the audit only.

READ game/tests/test_globe_player_players_group.gd and game/tests/test_globe_input_parity.gd FIRST -- they are the existing receipts for exactly this class of wiring; do not duplicate them.

OWNED FILES: your audit report labs/lane-smoke/lane-B-wiring-audit.md (new); if (and only if) you find a real bug, the minimal source fix plus game/tests/test_globe_<name>_wiring.gd (new). Do NOT edit the runner DEFAULT_SET, AGENTS.md, or labs/TASKS.md.

CONSTRAINTS
- TABS in .gd. ASCII only. extends SceneTree receipts; exit 0 pass / 1 fail.
- A fresh worktree has no .godot cache: `godot --headless --path game --import` once first, OR `cp -r /workspace/project/synmergia/game/.godot game/.godot`. Live-driver receipts use xvfb-run.

DEFINITION OF DONE
- The report lists every consumer checked, its mechanism, and its globe verdict (satisfied / gap / n-a), with file:line evidence.
- If a bug was found: the minimal fix + a receipt that exits 0 on a live boot, committed `lane-B:`.
- Report the exact commands you ran and their pass counts. Be honest about anything you could not verify.
