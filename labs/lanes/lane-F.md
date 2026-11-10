You are a Synmergia subagent lane (Lane F: enemy model / thistle boar). Work ONLY inside your own worktree (your cwd). Never edit /workspace/project/synmergia directly.

FIRST, run the lane setup (idempotent -- warms the Godot import cache a fresh worktree lacks, and links the gamestruct dep):
  sh labs/lane_setup.sh

CONTEXT
- Synmergia is a Godot 4.7.2 MMORPG. 3D assets are PROCEDURAL: a Python generator builds the mesh/rig/animations in Blender 4.3.2 and exports a .glb; the game imports it.
- Pipeline: read labs/prd-3d-pipeline.md (sec 1 + sec 6). The shared export pipeline is scripts/model_export_lib.py.
- COPY THE SHAPE OF: scripts/gen_wolf_model.py (a QUADRUPED -- spine chain + 4 legs + a trot cycle). Existing exports to study: enemy_wolf.glb, enemy_slime.glb.
- Export command: blender --background --factory-startup --python scripts/gen_thistle_boar_model.py
- The .glb registry law: game/models/enemies/<id>.glb, filename == the enemy data id.

WHY THIS MATTERS
- enemy_thistle_boar is one of only FOUR enemies that actually SPAWN in the live globe world (GLOBE_ENEMY_BATCH in scenes/worlds/globe_world.gd), and it has model_path = "" -- so it renders as a PLACEHOLDER BOX in the game right now. A real boar body is high-visibility.

GOAL
Author enemy_thistle_boar end-to-end.
1. Write scripts/gen_thistle_boar_model.py (deterministic, NO rng) modeled on gen_wolf_model.py (the quadruped rig). The boar: a low, broad body, a big wedge head with an upturned snout and two small tusks, short sturdy legs, and a THISTLE MATTING across the shoulders (a ridge of purple-green spines -- a few cones or a spiky strip). Palette: dark bristly brown, a thistle purple-green mat, pale tusks. Ship an idle + walk/trot clip.
2. Export to game/models/enemies/enemy_thistle_boar.glb.
3. Set model_path in game/data/enemies/enemy_thistle_boar.tres to "res://models/enemies/enemy_thistle_boar.glb" (change ONLY that one line).
4. Add game/tests/probe_thistle_boar_model.gd modeled on game/tests/probe_slime_model.gd: load the .glb, assert a real mesh + material (+ an AnimationPlayer if you ship clips).
5. Prove it: run the export; `godot --headless --path game --import`; then run
   `godot --headless --path game --script res://tests/test_data_naming_lint.gd` (the phantom-path lint)
   and `godot --headless --path game --script res://tests/probe_thistle_boar_model.gd`.

OWNED FILES (yours alone): scripts/gen_thistle_boar_model.py (new), game/models/enemies/enemy_thistle_boar.glb (+ its .import), game/data/enemies/enemy_thistle_boar.tres (the model_path line only), game/tests/probe_thistle_boar_model.gd (new). Do NOT edit any other file (not the runner DEFAULT_SET, not AGENTS.md, not labs/TASKS.md).

CONSTRAINTS
- ASCII only in scripts. Python: 4-space indent, no rng. Same input -> same .glb.
- "Done" means the .glb IMPORTS and a probe sees real geometry -- not that the render looks right.

DEFINITION OF DONE
- enemy_thistle_boar.glb exists and imports cleanly; the .tres points at it.
- test_data_naming_lint PASS; probe_thistle_boar_model PASS.
- Commit in YOUR worktree with a message starting `lane-F:`.
- Report: the generator, the export command, the import result, the .glb byte size, the probe result, and any limitation.
