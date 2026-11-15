# Archived agent probes (2026-10-11)

This is the former root `dev_temp/` snapshot, moved out of the repository root
so staging has no stray probe directory. It is provenance, not a live test
suite.

- `probes/` holds the ad-hoc GDScript, shell, and Python probes from the
  2026-10-11 session.
- No `logs/` directory was present when the snapshot was retired.

These probes are not in `scripts/godot_test_runner.sh`; they are hand-run. Many
of their comments still say `res://dev_temp/...`. Adjust the path if you revive
one. The current, runnable world receipts live in
[`game/tools/diagnostics/receipts/`](../../../game/tools/diagnostics/receipts/).

Historical notes in `labs/AGENTS_LOG.md` and `labs/TASKS_ARCHIVE.md` that name
`dev_temp/probes/` refer to this snapshot.
