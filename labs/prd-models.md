# PRD - Models: schema, catalog, and source-to-runtime pipeline

> **Status:** DESIGN 2026-11-15. This is the target contract for models; the
> current seven GLBs are a prototype pass, not the production system.
>
> **Canonical root:** `game/data/` (not `game/assets`, not repo-root `data/`).
> The later repo-root `/data` split is deferred until the frame is extracted.
>
> **Law it obeys:** [`prd-3d-pipeline.md`](./prd-3d-pipeline.md) owns the
> toolchain/import law; [`prd-art-pipeline.md`](./prd-art-pipeline.md) owns
> Lane D and GPU generation; this PRD owns the model record, runtime
> resolution, and the retirement of ad-hoc `model_path` strings.

## 1. Why this exists

The world is math-generated, but bodies, mounts, props, and set pieces still
need authored meshes. The current pass proved that Blender -> glTF -> Godot
works; it did not produce a model system.

The evidence is in the code:

- Ten schemas carry their own visual-path fields: `EnemyData.model_path`,
  `NPCData.scene_path` / `model_path`, `MountData.model_path`,
  `VehicleData.model_path`, `Species.model_path`, `Ankh.model_path`,
  `GatewayData.model_path`, `FurnishingData.model_path`,
  `HouseData.model_path`, and `Item.model_path`.
- `Enemy._mount_model()` loads a GLB directly from `EnemyData.model_path`;
  NPCs use a separate `scene_path` path. There is no shared mount layer.
- `DataService` loads enemies, NPCs, mounts, and props independently; it has
  no model catalog.
- `test_data_naming_lint.gd` checks that a path resolves. It does not check
  the model id, provenance, license, animation contract, LODs, scale, or
  attachment points.
- The five enemy GLBs under `game/data/models/enemies/` are a prototype
  pass. They are useful evidence, not the target pipeline.

The result is path duplication and per-actor loading logic. A second actor
that wants the same body has to copy a path; a model cannot carry its own
scale, clips, LODs, or provenance; and the web/editor cannot reason about a
model independently of an enemy.

## 2. Decision

### 2.1 One record per model

Add `ModelData` (`game/core/schemas/model_data.gd`) as the canonical model
record. A model is a data resource, not a filename convention.

- `game/data/models/<family>/<model_id>.tres` is the `ModelData` record.
- `game/data/models/<family>/<model_id>.glb` is the runtime mesh.
- Optional LODs live beside it as `<model_id>_lod1.glb`, etc.
- Source files live under `game/data/art/src/<model_id>/`; GPU scratch lives
  under `game/data/art/out/<model_id>/`.

The id is stable and filename-equal: `<model_id>.tres` and
`<model_id>.glb` share the id.

### 2.2 Actors reference an id, never a path

Replace the visual fields on actor/ prop schemas with:

```gdscript
@export var model_id: String = ""
```

`DataService` resolves `model_id` to the `ModelData` record. Consumers never
read a GLB path directly, and two actors can share one model without copying
a path.

This follows the existing id rules (`movement_profile_id`,
`hitbox_profile_id`, `loot_table_id`): stable string key, one owner, one
resolver. The `.tres` record is what "rides with" the actor `.tres`; the
actor keeps gameplay fields, the model record keeps presentation fields.

### 2.3 Move presentation fields out of actor data

| Actor field | New owner |
|---|---|
| `model_path` | `ModelData.asset_path` |
| `scale` | `ModelData.scale` |
| `animation_set` | `ModelData.animation_clips` |
| per-actor visual hacks | `ModelData` fields or an explicit override |

Gameplay fields stay on the actor: `hitbox_profile_id`, movement profile,
stats, loot, AI. A hitbox is gameplay fairness; a mesh scale is presentation.
They can be related by a probe, but they are not the same field.

`NPCData.scene_path` remains for composite NPC scenes (a blacksmith stall, a
vendor with props). A simple NPC uses `model_id`. A composite scene owns its
own presentation and may reference a `ModelData` record for its body.

### 2.4 Canonical tree for this phase

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
      enemy_wolf.glb          # prototype, not production
      enemy_wolf.tres         # ModelData, when authored
    npcs/
    blocks/
  brand/                      # logos, wordmarks
  shaders/
  textures/
  enemies/ items/ ...         # gameplay .tres records
```

`game/assets/` and `game/models/` are retired. Do not recreate them. Runtime
paths are `res://data/models/...`, `res://data/brand/...`,
`res://data/shaders/...`, and `res://data/textures/...`. The later repo-root
`/data` split will preserve this relative shape and is not part of this
phase.

## 3. The `ModelData` schema

The initial schema is deliberately concrete. Keep optional fields optional;
do not add a second descriptor type for a special case.

```gdscript
extends Resource
class_name ModelData

enum Kind {
    ACTOR,
    PROP,
    MOUNT,
    VEHICLE,
    DWELLING,
    GATEWAY,
    FURNISHING,
    ITEM,
    BLOCK,
    OTHER
}

enum Status {
    PROTOTYPE,
    PRODUCTION,
    DEPRECATED
}

enum Collision {
    NONE,
    BOX,
    CAPSULE,
    CONVEX,
    TRIMESH
}

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""

@export var kind: Kind = Kind.ACTOR
@export var status: Status = Status.PROTOTYPE

## Runtime mesh. For PRODUCTION this must be res://data/models/<family>/<id>.glb.
@export_file("*.glb") var asset_path: String = ""

## Provenance. PRODUCTION records require source_path, license, and either
## generator or author; PROTOTYPE records may carry the prototype marker.
@export var source_path: String = ""       # game/data/art/src/<id>/
@export var source_url: String = ""
@export var author: String = ""
@export var license: String = ""
@export var generator: String = ""         # script or suite name
@export var source_hash: String = ""       # hash of source/generator commit

## Presentation contract.
@export var scale: float = 1.0
@export var forward_axis: String = "-Z"
@export var up_axis: String = "+Y"
@export var bounds_height_m: float = 0.0

## Semantic clip map: idle/walk/run/attack/cast/hit/death -> imported clip.
## Empty means the model has no clips; consumers must not guess a clip name.
@export var animation_clips: Dictionary = {}

## LOD entries: {path, screen_ratio, triangles}. Base asset_path is LOD0.
@export var lods: Array[Dictionary] = []

## Static props only. Actors use the actor's hitbox_profile_id for gameplay.
@export var collision: Collision = Collision.NONE
@export var collision_path: String = ""
@export var collision_size: Vector3 = Vector3.ZERO

## Named sockets consumed by the shared mount layer.
## Example: {"seat_driver": "seat_driver", "head_mount": "head_mount"}.
@export var attachment_points: Dictionary = {}

@export var tags: Array[String] = []
```

`ModelData` never loads the mesh itself. It describes it. One shared
`ModelMount` helper resolves `asset_path`, applies `scale`, attaches the
semantic clips, and exposes the sockets. `Enemy`, `NPC`, mount, and prop
presentation route through that helper instead of each writing its own
`load()`/`instantiate()` block.

## 4. Actor schema changes

The fields below are the complete first migration. Do not leave a second
visual path behind "for compatibility" once a consumer is migrated.

| Schema | Add | Remove / deprecate |
|---|---|---|
| `EnemyData` | `model_id` | `model_path`, `scale`, `animation_set` |
| `NPCData` | `model_id` | `model_path`; keep `scene_path` for composite scenes |
| `MountData` | `model_id` | `model_path`; `tint` stays (instance tint) |
| `VehicleData` | `model_id` | `model_path` |
| `Species` | `model_id` | `model_path` |
| `Ankh` | `model_id` | `model_path` |
| `GatewayData` | `model_id` | `model_path` |
| `FurnishingData` | `model_id` | `model_path` |
| `HouseData` | `model_id` | `model_path` |
| `Item` | `model_id` for dropped/world meshes | `model_path`; `icon_path` stays 2D |

`icon_path` is UI art, not a 3D model. It does not become a `ModelData`
record. `NPCData.scene_path` is a composite presentation seam, not a second
model registry.

## 5. DataService and validation

`DataService` gains:

```gdscript
var _models: Dictionary = {}

func load_models() -> void:
    _models = _scan_directory(_data_path + "models", "model")

func get_model(id: String) -> ModelData:
    return _models.get(id)
```

`load_all_data()` calls `load_models()` once. `get_model_for(data)` resolves a
`model_id` and returns `null` with one warning for a missing record; consumers
must degrade to a placeholder, not crash.

The lint becomes a model gate, not only a path checker:

1. Every `ModelData.id` equals its filename stem.
2. Every actor `model_id` resolves to a `ModelData`.
3. `PRODUCTION` records have `asset_path`, `source_path`, `license`, and
   `generator` or `author`; `PROTOTYPE` records are explicitly marked.
4. `asset_path` exists and, for production, is under
   `res://data/models/`.
5. Every LOD path exists and its `screen_ratio` descends.
6. Every `animation_clips` key is one of the semantic keys; no guessed names.
7. Every `attachment_points` value names a node/ bone in the imported scene
   when the model is mounted.
8. No `.glb` is authored outside `game/data/models/`; no actor `.tres` holds
   a direct `res://...glb` path outside `ModelData`.

`test_data_naming_lint.gd` owns the data side. A new model probe loads the
record, mounts it, and asserts the clip/socket/scale contract on the
instantiated scene.

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
7. Run the model lint and the engine probe. A path that resolves is not
   enough; the record must describe what was imported.

### Runtime

`DataService.get_model(model_id)` -> `ModelData` -> `ModelMount` ->
`asset_path`. The mount helper applies scale, resolves semantic clips, and
publishes sockets. No actor owns a path.

### Web / exports

`src/data/godot_data.json` is generated from `game/data` by
`npm run sync:data`. Model metadata must be exported through that generator
once `ModelData` exists; the web side must not scrape GLB paths. The future
repo-root `/data` split changes the projection, not this contract.

## 7. The prototype pass

The following are prototypes and must stay `Status.PROTOTYPE` until replaced:

- `game/data/models/enemies/enemy_wolf.glb`
- `game/data/models/enemies/enemy_slime.glb`
- `game/data/models/enemies/enemy_bandit.glb`
- `game/data/models/enemies/enemy_thistle_boar.glb`
- `game/data/models/enemies/enemy_training_dummy.glb`

`npc_blacksmith_village.glb` is a proven import/reference, but it is still a
pre-`ModelData` asset; mark it `PROTOTYPE` rather than claiming production
quality. `block_ref_cube.glb` is a calibration block and may be
`DEPRECATED` or `PROTOTYPE`; it is not an actor.

The prototype GLBs keep working while the schema lands. They are not evidence
that the model system is finished, and no new enemy should copy their
`model_path` shape.

## 8. FOSS provenance

Because Synmergia is open source, a model record must answer: where did this
come from, who made it, and under what license?

- `author` and `license` are required for `PRODUCTION`.
- `source_url` is required when the source is external.
- `generator` names the deterministic script/suite when the mesh is generated.
- `source_hash` pins the source or generator revision used to produce the
  asset.
- A bought or borrowed asset without a compatible license is not a
  `PRODUCTION` record. It cannot ship.
- Generated assets still record the generator and the source references; "the
  script made it" is provenance, not an excuse to omit the license.

## 9. Migration phases

1. **Schema + resolver:** add `ModelData`, `DataService.load_models`, the
   shared `ModelMount`, and the lint gates. No visual change.
2. **Wrap the prototypes:** add `ModelData` records for the existing seven
   GLBs with `PROTOTYPE` status. Point actor data at `model_id`; keep a
   temporary legacy `model_path` fallback only until every consumer is
   migrated.
3. **One mount path:** move `Enemy._mount_model` and NPC idle mounting behind
   `ModelMount`; delete direct GLB loads from actors.
4. **Production assets:** author new models under `game/data/models` with
   source/art provenance; add LODs and sockets where needed.
5. **Retire the prototype path:** remove `model_path` from the schemas and
   the old `game/models` references; the only model paths left are inside
   `ModelData`.
6. **Future root split:** when the frame and content separate, move
   `game/data` to repo `/data` and keep the same relative tree. That is a
   projection change, not a model-schema change.

## 10. Acceptance

- `test_model_registry.gd` passes for every record: id/filename, asset path,
  status/provenance, LODs, clips, sockets.
- `test_model_refs.gd` passes: every `model_id` resolves; no actor data
  contains a direct GLB path.
- `probe_model_mount.gd` spawns an enemy, mounts its model, and asserts scale,
  semantic idle clip, and socket names.
- `npm run sync:data` exports model metadata without hand-edited paths.
- The five proto GLBs are explicitly `PROTOTYPE`; no doc calls them the
  production model system.
- `game/assets/` and `game/models/` do not exist; `game/data/` is the only
  authored content root.

## 11. Non-goals

- Replacing math-generated terrain, props, or world layout.
- A DCC/Blender-MCP integration; the Python generator + Blender export path
  remains the CPU floor.
- A generic asset store, resource packs, or runtime GLB downloads.
- The repo-root `/data` split. It is deliberately later.
- Migrating all seven prototypes to production quality in this PRD.
