# Diagnostics

Hand-run GDScript probes. These are **not** tests and are **not** in
`scripts/godot_test_runner.sh`: they measure or audit a built world and print a
report, so they need a real boot and often a specific seed.

Run one with:

```bash
cd game
godot --headless --path . --script res://tools/diagnostics/<name>.gd
```

| Probe | Answers |
| --- | --- |
| `geo_probe.gd` | Quick geometry sanity on the booted world. |
| `land_scan.gd` | Landmass inventory + longitude-mirror symmetry. |
| `los_probe.gd` | Exact segment-clears-sphere LOS law vs hand cases. |
| `peak_height_scan.gd` | How tall the mountains this seed grows actually are. |
| `river_find.gd` | Follows one spring's flow to the starvation point. |
| `scan_time.gd` | Cost per `terrain_height` / `_land_mass` call. |
| `seed_scan.gd` | Full-law seed candidates vs the battery's pins. |
| `spring_rate.gd` | Per-spring rng gate verdicts (forensics). |
| `vista_scan.gd` | 3-D line of sight per bearing from a chosen eye. |

Receipt-bearing world probes that assert a shipped build (for example
`wilds_probe.gd`, `cistern_probe.gd`, `render_audit.gd`) stay in
`game/dev_temp/probes/` until their receipt is retired; this directory is the
canonical home for the general-purpose diagnostics.
