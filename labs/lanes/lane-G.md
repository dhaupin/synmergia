You are a Synmergia subagent lane (Lane G: enemy model / training dummy). Work ONLY inside your own worktree (your cwd). Never edit /workspace/project/synmergia directly.

FIRST, run the lane setup (idempotent -- warms the Godot import cache a fresh worktree lacks, and links the gamestruct dep):
  sh labs/lane_setup.sh

CONTEXT
- Synmergia is a Godot 4.7.2 MMORPG. 3D assets are PROCEDURAL: a Python generator builds the mesh/rig/animations in Blender 4.3.2 and exports a .glb; the game imports it.
- Pipeline: read labs/prd-3d-pipeline.md (sec 1 + sec 6). The shared export pipeline is scripts/model_export_lib.py.
- COPY THE SHAPE OF: scripts/gen_blacksmith_model.py (the mesh helpers: box/cyl/sph/mat) and scripts/gen_slime_model.py (a simple, low-poly, deterministic build). Existing exports: enemy_wolf.glb, enemy_slime.glb.
- Export command: blender --background --factory-startup --python scripts/gen_training_dummy_model.py
- The .glb registry law: game/models/enemies/<id>.glb, filename == the enemy data id.

WHY THIS MATTERS
- enemy_training_dummy is one of only FOUR enemies that actually SPAWN in the live globe world (GLOBE_ENEMY_BATCH in scenes/worlds/globe_world.gd), and it has model_path = "" -- so it renders as a PLACEHOLDER BOX in the game right now. It is the first thing a new player hits to measure damage, so a clear dummy silhouette matters.

GOAL
Author enemy_training_dummy end-to-end.
1. Write scripts/gen_training_dummy_model.py (deterministic, NO rng). A straw practice target: a wooden post on a base, a burlap-wrapped torso (a barrel-ish body) bound with rope bands, and a simple rounded head -- the classic archery-but-melee dummy. Palette: pale straw yellow, wood brown, rope tan. A static mesh is FINE (no animation required -- the dummy never moves). Low-poly.
2. Export to game/models/enemies/enemy_training_dummy.glb.
3. Set model_path in game/data/enemies/enemy_training_dummy.tres to "res://models/enemies/enemy_training_dummy.glb" (change ONLY that one line).
4. Add game/tests/probe_training_dummy_model.gd modeled on game/tests/probe_slime_model.gd: load the .glb, assert a real mesh + material.
5. Prove it: run the export; `godot --headless --path game --import`; then run
   `godot --headless --path game --script res://tests/test_data_naming_lint.gd` (the phantom-path lint)
   and `godot --headless --path game --script res://tests/probe_training_dummy_model.gd`.

OWNED FILES (yours alone): scripts/gen_training_dummy_model.py (new), game/models/enemies/enemy_training_dummy.glb (+ its .import), game/data/enemies/enemy_training_dummy.tres (the model_path line only), game/tests/probe_training_dummy_model.gd (new). Do NOT edit any other file (not the runner DEFAULT_SET, not AGENTS.md, not labs/TASKS.md).

CONSTRAINTS
- ASCII only in scripts. Python: 4-space indent, no rng. Same input -> same .glb.
- "Done" means the .glb IMPORTS and a probe sees real geometry -- not that the render looks right.

DEFINITION OF DONE
- enemy_training_dummy.glb exists and imports cleanly; the .tres points at it.
- test_data_naming_lint PASS; probe_training_dummy_model PASS.
- Commit in YOUR worktree with a message starting `lane-G:`.
- Report: the generator, the export command, the import result, the .glb byte size, the probe result, and any limitation.
