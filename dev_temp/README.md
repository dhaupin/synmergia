# dev_temp — scrape-the-tmp snapshot (2026-10-11)

Ad-hoc scripts generated inside the agent coding session while working
in /tmp survive a session teardown ONLY because of this directory:
everything dated gets committed here as provenance + re-use material.
If a future session re-opens this workspace and /tmp is EMPTY, the
fastest-recovery path is reading these files: they are load-bearing
(godot --headless --path game/debug/foo.gd runs them directly).

Subdirs:
- probes/  207 *.gd/.sh/.py one-shot debug + calibration scripts
- logs/    probe stdout runs (for anyone debugging regressions to compare against)
