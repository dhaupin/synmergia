# Models

Canonical runtime model registry for the Godot project. Files are id-named and
family-sorted:

```
game/data/models/<family>/<id>.glb
```

## Prototype pass

The current GLBs are prototypes and proof-of-import assets, not the target
model system:

- `enemies/enemy_wolf.glb`
- `enemies/enemy_slime.glb`
- `enemies/enemy_bandit.glb`
- `enemies/enemy_thistle_boar.glb`
- `enemies/enemy_training_dummy.glb`
- `npcs/npc_blacksmith_village.glb`
- `blocks/block_ref_cube.glb`

They may be used by the current gameplay data, but they do not define the
production contract. Do not copy their `model_path` shape into new content.

## Target

`ModelData` (`game/core/schemas/model_data.gd`) will own `asset_path`, scale,
semantic animation clips, LODs, collision, sockets, provenance, and status.
Actor data references a stable `model_id`; it never hardcodes a GLB path.

Source files belong in `game/data/art/src/<id>/`; GPU scratch belongs in
`game/data/art/out/<id>/`. See [`labs/prd-models.md`](../../../labs/prd-models.md).
