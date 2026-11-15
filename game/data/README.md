# `game/data` - canonical content root

The canonical content root for authored data, models, art, branding, shaders,
and textures. `game/assets/` and `game/models/` were retired in the 2026-11-15
consolidation; do not recreate either. Runtime code and generated audio stay
beside their consumers, outside this content root.

| Path | What lives there | Runtime path |
|---|---|---|
| `game/data/enemies/`, `items/`, `skills/`, ... | gameplay `.tres` records | `res://data/...` |
| `game/data/models/` | exported `.glb` models and (target) `ModelData` records | `res://data/models/...` |
| `game/data/art/` | source `.blend`, GPU scratch, review renders; `.gdignore` hides it | not loaded |
| `game/data/brand/` | logos and wordmarks | `res://data/brand/...` |
| `game/data/shaders/` | shaders | `res://data/shaders/...` |
| `game/data/textures/` | terrain and texture maps | `res://data/textures/...` |

The five enemy GLBs and the blacksmith/block imports are a prototype pass, not
the production model system. The target schema, catalog, and source-to-runtime
pipeline are in [`labs/prd-models.md`](../../labs/prd-models.md).

The repo-root `/data` split is deliberately deferred. If it happens, this
relative layout moves as a unit; Godot's `res://data` paths do not change.
