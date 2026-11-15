# World receipts

These 13 hand-run probes were moved from `game/dev_temp/probes/` so the Godot
project has one diagnostics home. They are receipts for shipped world builds,
not tests, and they are not in `scripts/godot_test_runner.sh`.

Run one from the repository root:

```bash
cd game
godot --headless --path . --script res://tools/diagnostics/receipts/<name>.gd
```

| Probe | What it receipts |
|---|---|
| `cistern_probe.gd` | The Glow Cistern's water, stone, and glow laws. |
| `concord_shrine_probe.gd` | The Concord shrine and herald placement in Nexus Central. |
| `deck_ride_probe.gd` | The Pans deck ride and its piece colliders. |
| `deep_commons_probe.gd` | The Deep Commons lava frame and seating. |
| `field2_salt_probe.gd` | The Field 2 salt split and anchored `PropLayer` detail. |
| `harbor_lights_probe.gd` | Harbor lights at dusk. |
| `lane_l_load.gd` | The Lane L equipment corpus loads. |
| `pans_builds_probe.gd` | The Pans build set. |
| `pans_pair_probe.gd` | The Pans gateway pair. |
| `pans_render_probe.gd` | The Pans render path through the clipmap. |
| `render_audit.gd` | The main world and underworld live seams in one pass. |
| `wildflower_drift_probe.gd` | Wildflower drift through the clipmap. |
| `wilds_probe.gd` | The Deep Wilds bands and their counts. |

Each file's header carries its exact assertions and any seed or boot caveat.
