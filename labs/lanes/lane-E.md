You are a Synmergia subagent lane (Lane E: enemy model / bandit). Work ONLY inside your own worktree (your cwd). Never edit /workspace/project/synmergia directly.

FIRST, run the lane setup (idempotent -- warms the Godot import cache a fresh worktree lacks, and links the gamestruct dep):
  sh labs/lane_setup.sh

CONTEXT
- Synmergia is a Godot 4.7.2 MMORPG. 3D assets are PROCEDURAL: a Python generator builds the mesh/rig/animations in Blender 4.3.2 and exports a .glb; the game imports it.
- Pipeline: read labs/prd-3d-pipeline.md (sec 1 + sec 6). The shared export pipeline is scripts/model_export_lib.py.
- COPY THE SHAPE OF: scripts/gen_blacksmith_model.py (a HUMANOID with an idle + walk clip). Existing enemy exports to study: scripts/gen_wolf_model.py -> enemy_wolf.glb, scripts/gen_slime_model.py -> enemy_slime.glb.
- Export command: blender --background --factory-startup --python scripts/gen_bandit_model.py
- The .glb registry law: game/models/enemies/<id>.glb, filename == the enemy data id.

WHY THIS MATTERS
- enemy_bandit has model_path = "" today, so it renders as a PLACEHOLDER BOX. This enemy is authored and quest-relevant; a humanoid bandit body makes it read as a person.

GOAL
Author enemy_bandit end-to-end.
1. Write scripts/gen_bandit_model.py (deterministic, NO rng) modeled on gen_blacksmith_model.py. A lean humanoid outlaw: a hooded head, a ragged tunic, worn trousers and boots, and a rusty blade held in one hand. Palette: muted browns, dirty grey cloth, a little rust-orange on the blade. Reuse the blacksmith's humanoid rig shape (spine + 2 arms + 2 legs) with an idle + walk clip.
2. Export to game/models/enemies/enemy_bandit.glb.
3. Set model_path in game/data/enemies/enemy_bandit.tres to "res://models/enemies/enemy_bandit.glb" (change ONLY that one line).
4. Add game/tests/probe_bandit_model.gd modeled on game/tests/probe_slime_model.gd: load the .glb, assert a real mesh + material (+ an AnimationPlayer if you ship clips).
5. Prove it: run the export; `godot --headless --path game --import`; then run
   `godot --headless --path game --script res://tests/test_data_naming_lint.gd` (the phantom-path lint -- it fails if model_path names a missing file)
   and `godot --headless --path game --script res://tests/probe_bandit_model.gd`.

OWNED FILES (yours alone): scripts/gen_bandit_model.py (new), game/models/enemies/enemy_bandit.glb (+ its .import), game/data/enemies/enemy_bandit.tres (the model_path line only), game/tests/probe_bandit_model.gd (new). Do NOT edit any other file (not the runner DEFAULT_SET, not AGENTS.md, not labs/TASKS.md).

CONSTRAINTS
- ASCII only in scripts. Python: 4-space indent, no rng. Same input -> same .glb.
- "Done" means the .glb IMPORTS and a probe sees real geometry -- not that the render looks right.

DEFINITION OF DONE
- enemy_bandit.glb exists and imports cleanly; enemy_bandit.tres points at it.
- test_data_naming_lint PASS; probe_bandit_model PASS.
- Commit in YOUR worktree with a message starting `lane-E:`.
- Report: the generator, the export command, the import result, the .glb byte size, the probe result, and any limitation.
