You are a Synmergia subagent lane (Lane D: modeling / assets / art). Work ONLY inside your own worktree (your cwd). Never edit /workspace/project/synmergia directly. This lane legitimately runs long (Blender); that is why it is its own lane.

CONTEXT
- Synmergia is a Godot 4.7.2 MMORPG. 3D assets are PROCEDURAL: a Python generator builds the mesh/rig/animations in Blender and exports a .glb; the game imports the .glb. Blender 4.3.2 is on PATH (`blender --version`).
- The pipeline is PROVEN. Read labs/prd-3d-pipeline.md (esp. sec 1 + sec 6) and DEPLOY-GPU.md sec 2 (the artifact contract).
- Working recipes to COPY THE SHAPE OF: scripts/gen_wolf_model.py (a quadruped with a trot cycle) and scripts/gen_blacksmith_model.py. The shared export pipeline is scripts/model_export_lib.py (export-once-per-clip + stdlib merge + NLA slots). Existing exports: game/models/enemies/enemy_wolf.glb, game/models/npcs/npc_blacksmith_village.glb.
- The .glb registry law: game/models/<family>/<data_id>.glb, filename == data id. A data file sets `model_path = "res://models/<family>/<data_id>.glb"`. Today ONLY enemy_wolf.glb is wired; the other 24 game/data/enemies/*.tres have `model_path = ""` (a placeholder body). Locked decisions: NO resource packs, NO Blender MCP (the python generator + probes stay the path).

GOAL
Author ONE new enemy model end-to-end: `enemy_slime`.
1. Write scripts/gen_slime_model.py modeled on gen_wolf_model.py (deterministic -- NO rng; same input -> same geometry). A slime is a simple, bounded subject: a rounded body (squashed sphere), a couple of eyes, an idle bob. Keep it low-poly and rigged enough to be useful (a simple squash/bob animation clip is a plus, not required).
2. Export to game/models/enemies/enemy_slime.glb via scripts/model_export_lib.py.
3. Set model_path in game/data/enemies/enemy_slime.tres to "res://models/enemies/enemy_slime.glb" (change ONLY that one line).
4. Prove it: run the Blender export, then `godot --headless --path game --import` (a fresh worktree has no .godot cache -- the import builds it) and confirm the .glb imports with no error. Optionally add game/tests/probe_slime_model.gd modeled on game/tests/probe_wolf_model.gd that loads the scene and asserts a real mesh + material.

RUN THE EXPORT LIKE THIS
  blender --background --factory-startup --python scripts/gen_slime_model.py

OWNED FILES (yours alone): scripts/gen_slime_model.py (new), game/models/enemies/enemy_slime.glb (+ its .import), game/data/enemies/enemy_slime.tres (the model_path line only), game/tests/probe_slime_model.gd (new, optional). Do NOT edit any other file (not the runner DEFAULT_SET, not AGENTS.md, not labs/TASKS.md).

CONSTRAINTS
- ASCII only in scripts. Python: 4-space indent, no rng.
- "Done" means the .glb IMPORTS and a probe sees real geometry -- not that the render looks right.

DEFINITION OF DONE
- enemy_slime.glb exists and imports cleanly; enemy_slime.tres points at it.
- Commit in YOUR worktree with a message starting `lane-D:`.
- Report: the generator, the export command, the import result, the .glb byte size, and any limitation (e.g. no animation yet).
