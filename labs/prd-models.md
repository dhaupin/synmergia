# PRD - Models: record, registry, and source-to-runtime pipeline

> **Status:** ACTIVE 2026-11-15. `ModelData` is the canonical model record.
> The seven committed GLBs have records under `game/data/models/`; actors
> resolve a stable `model_id` through `DataService`, never a GLB path.
>
> **Canonical root:** `game/data/` (not `game/assets`, not repo-root `data/`).
> The later repo-root `/data` split is deferred until the frame is extracted.
>
> **Law it obeys:** [`prd-3d-pipeline.md`](./prd-3d-pipeline.md) owns the
> toolchain/import law; [`prd-art-pipeline.md`](./prd-art-pipeline.md) owns
> Lane D and GPU generation; this PRD owns the model record and runtime
> resolution.

## 1. Why this exists

The world is math-generated, but bodies, mounts, props, and set pieces still
need authored meshes. A model is a data resource, not a filename convention:
one record owns the mesh path, presentation scale, animation mapping, and
provenance. Actors point at that record by id.

That keeps the model reusable across actors and makes the asset inspectable by
the engine, the editor, and the web data export without any consumer scraping
a GLB path.

## 2. Decision

### 2.1 One record per model

- `game/data/models/<family>/<model_id>.tres` is the `ModelData` record.
- `game/data/models/<family>/<model_id>.glb` is the runtime mesh.
- The id is stable and filename-equal: `<model_id>.tres` and
  `<model_id>.glb` share the id.
- Source files live under `game/data/art/src/<model_id>/`; GPU scratch lives
  under `game/data/art/out/<model_id>/`.

### 2.2 Actors reference an id

```gdscript
@export var model_id: String = ""
```

`DataService.get_model(model_id)` returns the record. Consumers use
`model.asset_path`; they do not own a path. Two actors can share one model
without copying anything.

This follows the existing id rules (`movement_profile_id`,
`hitbox_profile_id`, `loot_table_id`): stable string key, one owner, one
resolver.

### 2.3 Presentation and body data

`ModelData` owns the mesh path, model scale, semantic clips, and attachment
points. `EnemyData` and `NPCData` own gameplay fields: stats, hitbox profile,
movement profile, loot, AI, and interaction surface.

`EnemyData.scale` remains the body size for an enemy without a model record.
When a model record resolves, `ModelData.scale` is the body and visual scale.
This keeps placeholder bodies correctly sized while every modeled actor has
one presentation owner.

`NPCData.scene_path` remains for composite NPC scenes (a stall, a vendor with
props). The scene owns its composition; a `model_id` supplies its body.

### 2.4 Canonical tree

```
game/data/
  README.md
  art/                         # source, scratch, renders (gdignore)
    src/<model_id>/           # .blend, references, textures
    out/                      # GPU scratch (gitignored)
    screenshots/              # review renders
  models/
    README.md
    enemies/
      enemy_wolf.glb
      enemy_wolf.tres         # ModelData
    npcs/
      npc_blacksmith_village.glb
      npc_blacksmith_village.tres
    blocks/
      block_ref_cube.glb
      block_ref_cube.tres
  brand/                      # logos, wordmarks
  shaders/
  textures/
  enemies/ items/ ...         # gameplay .tres records
```

`game/assets/` and `game/models/` are retired. Do not recreate them. Runtime
paths are `res://data/models/...`, `res://data/brand/...`,
`res://data/shaders/...`, and `res://data/textures/...`. The later repo-root
`/data` split preserves this relative shape.

## 3. The `ModelData` schema

```gdscript
extends Resource
class_name ModelData

enum Kind {
    ACTOR,
    PROP,
    BLOCK
}

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var kind: Kind = Kind.ACTOR
@export_file("*.glb") var asset_path: String = ""
@export var scale: float = 1.0
@export var animation_clips: Dictionary = {}
@export var source_path: String = ""
@export var generator: String = ""
@export var license: String = ""
@export var attachment_points: Dictionary = {}
```

`ModelData` describes the mesh; it never loads it. The mount site resolves the
record, loads `asset_path`, applies `scale`, and maps the semantic clip keys
it needs.

The record is deliberately one type. A block, an actor, and a prop differ by
`kind` and fields, not by a second descriptor class.

## 4. Actor wiring

| Schema | Field | Contract |
|---|---|---|
| `EnemyData` | `model_id` | Optional. Resolves to a `ModelData`; absent means the scene placeholder body. |
| `EnemyData` | `scale` | Body scale when no model record resolves. |
| `NPCData` | `model_id` | Optional body record for a composite scene. |
| `NPCData` | `scene_path` | Composite NPC scene. |

The registry currently covers the five enemy models, the blacksmith NPC, and
the calibration block. It is the only model registry.

## 5. DataService and validation

`DataService` loads the recursive model directory once:

```gdscript
func load_models() -> void:
    _models = _scan_directory(_data_path + "models", "model")

func get_model(id: String) -> ModelData:
    return _models.get(id)
```

`load_all_data()` calls `load_models()`. A missing actor model id logs once and
the actor keeps its placeholder body; a missing asset logs and does not crash
the spawn.

`test_data_naming_lint.gd` enforces the registry:

1. Every `ModelData.id` equals its filename stem.
2. Every `asset_path` exists and is under `res://data/models/`.
3. Every `.glb` under `game/data/models/` has a record.
4. Every actor `model_id` resolves to a record.
5. Actor data contains no direct GLB path.
6. Every `scene_path` resolves to a real file.

## 6. Pipeline

### Authoring

1. Choose a stable `<model_id>` and a family (`enemies`, `npcs`, `blocks`,
   `mounts`, ...).
2. Put the source and references in `game/data/art/src/<model_id>/`.
3. Add the model brief: shape, scale, forward axis, clips, sockets, collision
   needs, and license.
4. Generate or hand-author the mesh. GPU output lands in
   `game/data/art/out/<model_id>/`; this is scratch and may be pruned.
5. Export the normalized GLB to
   `game/data/models/<family>/<model_id>.glb`. Pivot at base, +Y up,
   -Z forward, 1 unit = 1 meter; riders pivot at `seat_driver`.
6. Author `game/data/models/<family>/<model_id>.tres` as `ModelData`.
7. Run the data lint and the engine probe.

### Runtime

`DataService.get_model(model_id)` -> `ModelData` -> `asset_path`. The mount
site applies `scale`, resolves clips from `animation_clips`, and lets the actor
keep its gameplay fields.

### Web / exports

`src/data/godot_data.json` is generated from `game/data` by
`npm run sync:data`. The generator exports the `models` category alongside the
gameplay records; the web side never scrapes GLB paths.

## 7. Current registry

| Model id | Asset | Used by |
|---|---|---|
| `enemy_wolf` | `data/models/enemies/enemy_wolf.glb` | `EnemyData wolf` |
| `enemy_slime` | `data/models/enemies/enemy_slime.glb` | `EnemyData slime` |
| `enemy_bandit` | `data/models/enemies/enemy_bandit.glb` | `EnemyData bandit` |
| `enemy_thistle_boar` | `data/models/enemies/enemy_thistle_boar.glb` | `EnemyData thistle_boar` |
| `enemy_training_dummy` | `data/models/enemies/enemy_training_dummy.glb` | `EnemyData training_dummy` |
| `npc_blacksmith_village` | `data/models/npcs/npc_blacksmith_village.glb` | `NPCData npc_blacksmith_village` scene |
| `block_ref_cube` | `data/models/blocks/block_ref_cube.glb` | Calibration block |

## 8. FOSS provenance

Because Synmergia is open source, a model record answers: where did this come
from, who made it, and under what license?

- `generator` names the deterministic script/suite when the mesh is generated.
- `source_path` names the tracked source directory when one exists.
- `license` is required. A bought or borrowed asset without a compatible
  license cannot ship.
- Generated assets still record the generator and license; "the script made
  it" is provenance, not an excuse to omit either.

## 9. Operating rules

- A model asset enters through a `ModelData` record; no actor, scene, or
  service carries a GLB path.
- The id is filename-equal. Renaming a model renames both files and every
  actor reference in the same change.
- A shared model is edited once in its record; actors do not fork the path.
- The record is the source for scale and clip mapping. Consumers do not guess
  clip names.
- The data lint is the gate. A file that exists but has no record is a
  registry miss.

## 10. Non-goals

- Replacing math-generated terrain, props, or world layout.
- A DCC/Blender-MCP integration; the Python generator + Blender export path
  remains the CPU floor.
- A generic asset store, resource packs, or runtime GLB downloads.
- The repo-root `/data` split. It is deliberately later.
