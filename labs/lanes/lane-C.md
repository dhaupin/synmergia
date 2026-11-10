You are a Synmergia subagent lane (Lane C: world / data building). Work ONLY inside your own worktree (your cwd). Never edit /workspace/project/synmergia directly.

CONTEXT
- Synmergia is a Godot 4.7.2 MMORPG (GDScript). Content is authored as .tres resources under game/data/. The data-naming law (game/tests/test_data_naming_lint.gd) enforces: category-prefix ids, filename == id, and cross-file reference integrity.
- The planar world is retired; the LIVE world is the spherical globe (game/scenes/worlds/globe_world.gd). Content that only the retired planar scene ever instantiated may now be dead on the live planet.
- Relevant docs: labs/prd-planar-retirement.md (what was ported to the globe), labs/prd-agent-play.md (the door), AGENTS.md "ID Naming Conventions".

GOAL (audit, docs-only unless the naming lint finds a real defect)
Produce a content-audit report labs/lane-smoke/lane-C-content-audit.md answering, with file:line evidence:
1. Which game/data/** resources are referenced ONLY by the retired planar path or by nothing at all (orphan/dead content). Grep for each id across game/ and report the consumers found (or none). Focus on: data/quests, data/npcs, data/npc_offerings, data/dialogues, data/zones, data/dwellings, data/loot_tables.
2. Which live globe systems READ each data family (e.g. which service loads data/quests, which builds data/dwellings). One line per family: the loader + the file:line.
3. Any id that a data file REFERENCES but that does not resolve (a dangling cross-file reference) -- list each with the referencing file.
4. Run `godot --headless --path game --script res://tests/test_data_naming_lint.gd` (after the import step below) and report the exact pass count. If it is NOT 27/0, that is a REAL defect: report the failing line.

OWNED FILES: labs/lane-smoke/lane-C-content-audit.md (new). Do NOT edit any data or code file, the runner DEFAULT_SET, AGENTS.md, or labs/TASKS.md.

CONSTRAINTS
- ASCII only. A fresh worktree has no .godot cache: run `godot --headless --path game --import` once first, OR `cp -r /workspace/project/synmergia/game/.godot game/.godot`.
- Do not guess consumer counts -- grep and cite. "No consumer found" is a valid, useful finding; state the exact grep you used.

DEFINITION OF DONE
- The report answers all four points with cited evidence and the lint's real pass count.
- Commit in YOUR worktree with a message starting `lane-C:`.
- Report: the file, the lint result, and the top 3 findings (especially any dangling reference or genuinely dead content family).
