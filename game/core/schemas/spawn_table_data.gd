## SpawnTableData - Data-driven enemy placement for a zone (the "zone
## spawn rung").
##
## The globe has always placed a small hardcoded near-village roster
## (globe_world.GLOBE_ENEMY_BATCH); the authored enemy ladder (~20
## templates, biome-matched, L5..L60) had no in-world seat. This is that
## seat: designers author one .tres per zone under data/spawn_tables/,
## listing the enemies that live there, and the globe's ZoneSpawner
## streams them in as the player comes near.
##
## WHY A TABLE, NOT MORE CODE CONSTANTS
## - One authored file per zone, no scene edit to add a species.
## - The placement rides the SAME walk law everything else uses
##   (bearing + reach on the spawn tangent frame, resolved by the
##   renderer-agnostic TerrainGen surface), so it is honest under both
##   the clipmap (the default renderer) and the legacy streamer.
##
## WHY PROXIMITY (the clipmap + MMO shape)
## - The clipmap draws fine ground only near the player (a ~5 km ring;
##   coarse shell beyond). A body placed 8 km out would stand on coarse
##   ground. So a spawn table is an ACTIVATION ROSTER, not a boot dump:
##   the ZoneSpawner materialises entries only within ACTIVATE_RADIUS_M
##   of a player and retires them past DEACTIVATE_RADIUS_M. That is also
##   the honest MMO shape -- the world is not simulated everywhere at
##   once; interest is what makes a region live.
##
## Entry shape (plain Dictionary -- inner classes do not survive .tres
## sub_resource serialization, matching HordeData's wave law):
##   {
##     "template_id": "wolf",      # bare EnemyData id (data/enemies/)
##     "bearing_deg": 250.0,       # spawn-frame bearing
##     "reach_rad": 0.018,         # spawn-frame reach (planet-scale rad)
##     "count": 2,                 # bodies at this point
##     "level": 0,                 # 0 = template default
##     "radius_m": 6.0,            # scatter radius around the point
##   }
##
## Consumption: ZoneSpawner.desired_entries(player_dir) reads the table
## and returns the entries whose point lies within the activation radius.
## Respawn after a kill rides globe_world's existing GlobeSpawn record
## law, unchanged.
extends Resource
class_name SpawnTableData

## Stable id (== file stem convention: spawn_<id>.tres in
## data/spawn_tables/).
@export var id: String = ""
## The zone these enemies belong to (a ZoneData id). Used for
## registration/roster attribution; the spatial placement is the
## bearing/reach on the spawn frame.
@export var zone_id: String = ""
## Display name for the truth line / debugging ("Meadowhaven fields").
@export var display_name: String = ""
## The roster. One Dictionary per point, per the shape in the header.
@export var entries: Array = []
## Per-table override of the activation ring (metres of ground arc).
## 0 = the ZoneSpawner default. A small zone can tighten this; a
## sprawling field can widen it.
@export var activate_radius_m: float = 0.0
## Per-table override of the retire ring. Must be >= activate when set.
@export var deactivate_radius_m: float = 0.0

## The activation ring for this table (metres), honouring the override.
func activation_radius(default_m: float) -> float:
        return activate_radius_m if activate_radius_m > 0.0 else default_m

## The retire ring for this table (metres), honouring the override and
## never letting it fall below the activation ring (hysteresis).
func retirement_radius(default_m: float) -> float:
        var act: float = activation_radius(default_m)
        var ret: float = deactivate_radius_m if deactivate_radius_m > 0.0 else default_m
        return maxf(ret, act)

## Flatten the authored entries into clean records (drop malformed rows,
## clamp counts), the same defensive shape HordeData.to_config uses.
func clean_entries() -> Array:
        var out: Array = []
        for e in entries:
                if not (e is Dictionary):
                        continue
                var tid: String = str(e.get("template_id", ""))
                if tid.is_empty():
                        continue
                var count: int = int(e.get("count", 1))
                if count <= 0:
                        continue
                out.append({
                        "template_id": tid,
                        "bearing_deg": float(e.get("bearing_deg", 0.0)),
                        "reach_rad": float(e.get("reach_rad", 0.0)),
                        "count": count,
                        "level": int(e.get("level", 0)),
                        "radius_m": float(e.get("radius_m", 6.0)),
                })
        return out

## The distinct template ids this table can place (for the pack gate +
## lint census without flattening).
func template_ids() -> Array:
        var seen := {}
        for e in clean_entries():
                seen[str(e["template_id"])] = true
        return seen.keys()
