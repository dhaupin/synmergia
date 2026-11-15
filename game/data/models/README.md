# Models

Canonical runtime model registry for the Godot project. Every runtime mesh has
a `ModelData` record beside it:

```
game/data/models/<family>/<id>.glb
game/data/models/<family>/<id>.tres
```

The `.tres` record is the only place a GLB path is named. Actors use
`model_id`; `DataService.get_model(model_id)` resolves the record.

## Registry

| Family | Model id | Asset |
|---|---|---|
| enemies | `enemy_wolf` | `enemies/enemy_wolf.glb` |
| enemies | `enemy_slime` | `enemies/enemy_slime.glb` |
| enemies | `enemy_bandit` | `enemies/enemy_bandit.glb` |
| enemies | `enemy_thistle_boar` | `enemies/enemy_thistle_boar.glb` |
| enemies | `enemy_training_dummy` | `enemies/enemy_training_dummy.glb` |
| npcs | `npc_blacksmith_village` | `npcs/npc_blacksmith_village.glb` |
| blocks | `block_ref_cube` | `blocks/block_ref_cube.glb` |

`ModelData` owns `asset_path`, `scale`, `animation_clips`, provenance, and
attachment points. `EnemyData` and `NPCData` keep gameplay fields and point at
the record with `model_id`.

Source files belong in `game/data/art/src/<id>/`; GPU scratch belongs in
`game/data/art/out/<id>/`. See [`labs/prd-models.md`](../../../labs/prd-models.md).

## Adding a model

1. Export the normalized GLB into its family directory.
2. Add `<id>.tres` with the same id and an `asset_path` pointing at the GLB.
3. Point the actor at `model_id`.
4. Run `test_data_naming_lint.gd` and the model probe.

A `.glb` without a record is a registry miss; a record with a phantom asset
fails the data gate.
