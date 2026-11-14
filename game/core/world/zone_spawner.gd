## ZoneSpawner - the proximity roster engine (the "zone spawn rung").
##
## The globe used to place a fixed near-village roster once at boot. This
## turns a SpawnTableData into a LIVING roster: entries materialise when a
## player comes within ACTIVATE_RADIUS_M and retire past
## DEACTIVATE_RADIUS_M, so the world stays honest under the player-centred
## clipmap (fine ground exists only near the player) and under the MMO
## interest model (a region is simulated because someone is in it, not
## because it exists).
##
## PURE + DETERMINISTIC. This helper owns no nodes and touches no scene
## tree: it answers "which entries should be live right now" and
## "which live ids should retire", and the scene does the node work. That
## keeps it testable headless and keeps the placement law in one place.
##
## The distance is measured in GROUND ARC (metres) via the angle between
## the player direction and the entry direction times the planet radius
## -- the same arc the clipmap's rings and the spawn frame already use.
##
## Frame-primitive rules (matching the repo's other core helpers): no
## autoload, no class_name, preload-only. Returning plain Dictionaries
## keeps it usable from --script test mode.
extends RefCounted

const TerrainGen = preload("res://scenes/worlds/terrain_gen.gd")

## Default rings (metres of ground arc). A spawn table may override per
## table; a caller may override per call. The gap between them is the
## hysteresis that stops a player pacing a boundary from thrashing the
## roster.
const ACTIVATE_RADIUS_M: float = 900.0
const DEACTIVATE_RADIUS_M: float = 1200.0

var _sites: Array = []           # Array of { center: Vector3, table: SpawnTableData }
var _center: Vector3 = Vector3.ZERO
var _radius: float = 20000.0
var _activate_m: float = ACTIVATE_RADIUS_M
var _deactivate_m: float = DEACTIVATE_RADIUS_M

## Live set bookkeeping: key -> true. A key is "<table_id>:<index>" so
## two entries of the same template at different points are distinct.
var _live: Dictionary = {}


func configure(center: Vector3, planet_radius: float, activate_m: float = -1.0, deactivate_m: float = -1.0) -> void:
        _center = center
        _radius = maxf(planet_radius, 1.0)
        if activate_m > 0.0:
                _activate_m = activate_m
        if deactivate_m > 0.0:
                _deactivate_m = maxf(deactivate_m, _activate_m)


## Register a spawn table at an anchor. The anchor defaults to the spawn
## centre; a far landmass (the island, the pans) passes its own world dir
## so its bearing/reach frame is honest to that place.
func add_table(table, center: Vector3 = Vector3.ZERO) -> void:
        if table == null or not table.has_method("clean_entries"):
                return
        var anchor: Vector3 = center if center.length_squared() > 0.000001 else _center
        _sites.append({"center": anchor.normalized(), "table": table})


func clear_tables() -> void:
        _sites.clear()
        _live.clear()


func table_count() -> int:
        return _sites.size()


func live_count() -> int:
        return _live.size()


## The tangent frame at an anchor direction (identical math to
## globe_world._globe_enemy_surface / _spawn_town_npc).
func _frame(center: Vector3) -> Array:
        var east: Vector3 = Vector3(0, 1, 0).cross(center).normalized()
        var north: Vector3 = center.cross(east).normalized()
        return [east, north]


## The direction for a bearing/reach on an anchor's tangent frame.
func _dir_for(center: Vector3, bearing_deg: float, reach: float) -> Vector3:
        var frame := _frame(center)
        var rad: float = deg_to_rad(bearing_deg)
        return (center + frame[0] * (reach * cos(rad)) \
                + frame[1] * (reach * sin(rad))).normalized()


## The world-space surface point for a bearing/reach on an anchor
## (renderer-agnostic: reads the shared walk law, so it is honest under
## the clipmap and the retired streamer alike).
func surface_point(bearing_deg: float, reach: float, center: Vector3 = Vector3.ZERO) -> Vector3:
        var anchor: Vector3 = center.normalized() if center.length_squared() > 0.000001 else _center
        var dir: Vector3 = _dir_for(anchor, bearing_deg, reach)
        var h: float = TerrainGen.terrain_height(dir, TerrainGen.world_seed_bytes())
        return dir * (_radius + h + 0.4)


## The `i`th of `count` body positions at a point: a deterministic ring
## scatter seeded by `key`, so server and every client derive identical
## positions for the same spawn (no RNG drift across peers). A single
## body sits on the point; more ring out at radius_m.
func body_position(point: Vector3, key: String, i: int, count: int, radius_m: float) -> Vector3:
        if count <= 1 or radius_m <= 0.0:
                return point
        var h: int = hash(key + ":" + str(i))
        var ang: float = float(h % 3600) / 3600.0 * TAU
        var r: float = radius_m * (0.35 + 0.65 * float((h / 3600) % 1000) / 1000.0)
        # Scatter in the point's tangent plane, then re-project to the sphere.
        var up: Vector3 = point.normalized()
        var east: Vector3 = Vector3(0, 1, 0).cross(up)
        if east.length_squared() < 0.000001:
                east = Vector3(1, 0, 0).cross(up)
        east = east.normalized()
        var north: Vector3 = up.cross(east).normalized()
        var offset_dir: Vector3 = (point + east * (r * cos(ang)) + north * (r * sin(ang))).normalized()
        var surf: float = TerrainGen.terrain_height(offset_dir, TerrainGen.world_seed_bytes())
        return offset_dir * (_radius + surf + 0.4)


## Ground-arc distance (metres) between a player direction and an entry
## direction. Pure angle * radius, the same arc the clipmap rings use.
func arc_distance_m(player_dir: Vector3, entry_dir: Vector3) -> float:
        if player_dir.length_squared() < 0.000001 or entry_dir.length_squared() < 0.000001:
                return 1.0e18
        return player_dir.normalized().angle_to(entry_dir.normalized()) * _radius


## The key for one entry of one table.
static func key_of(table_id: String, index: int) -> String:
        return "%s:%d" % [table_id, index]


## Which entries should be LIVE, given the set of tracked player
## directions. Returns { "spawn": [record...], "retire": [key...] }.
##
## MMO interest shape: an entry is live if ANY tracked player is within
## its activation ring (a region lives because someone is in it, not
## because one client looked). The scene passes every player it tracks;
## a solo client passes its own direction.
##
## Spawn: an entry within activation of some player AND not already live.
## Retire: a live key no longer within the retire ring of ANY player
## (hysteresis), or whose table is gone.
##
## Deterministic: positions come from the shared walk law + a scatter
## seeded by the entry key, so every client (and the server) derives the
## SAME body positions from the same inputs.
func reconcile(player_dirs: Array) -> Dictionary:
        var spawn: Array = []
        var retire: Array = []
        var still_live := {}

        for site in _sites:
                var table = site["table"]
                var anchor: Vector3 = site["center"]
                var tid: String = str(table.id)
                var act_m: float = table.activation_radius(_activate_m)
                var ret_m: float = table.retirement_radius(_deactivate_m)
                var entries: Array = table.clean_entries()
                for i in range(entries.size()):
                        var e: Dictionary = entries[i]
                        var key: String = key_of(tid, i)
                        var dir: Vector3 = _dir_for(anchor, float(e["bearing_deg"]), float(e["reach_rad"]))
                        var near: bool = false
                        var near_retire: bool = false
                        for pd in player_dirs:
                                var dist: float = arc_distance_m(pd, dir)
                                if dist <= act_m:
                                        near = true
                                if dist <= ret_m:
                                        near_retire = true
                                if near and near_retire:
                                        break
                        var is_live: bool = _live.has(key)
                        if is_live:
                                if near_retire:
                                        still_live[key] = true
                                else:
                                        retire.append(key)
                        elif near:
                                still_live[key] = true
                                spawn.append({
                                        "key": key,
                                        "table_id": tid,
                                        "zone_id": str(table.zone_id),
                                        "template_id": str(e["template_id"]),
                                        "position": surface_point(float(e["bearing_deg"]), float(e["reach_rad"]), anchor),
                                        "level": int(e["level"]),
                                        "count": int(e["count"]),
                                        "radius_m": float(e["radius_m"]),
                                })
        # Any live key not refreshed above is stale (its table vanished).
        for key in _live:
                if not still_live.has(key) and not retire.has(key):
                        retire.append(key)

        # Commit the new live set now so callers can query live_count().
        _live = still_live
        return {"spawn": spawn, "retire": retire}


## Mark a live key as retired (called after the scene frees the bodies).
func forget(key: String) -> void:
        _live.erase(key)


func is_live(key: String) -> bool:
        return _live.has(key)
