## diag_spawn_bearings - what biome lives at each bearing/reach around
## SPAWN_CENTER. The globe enemy/guard/prop batches place by
## (bearing_deg, reach_rad) on the spawn tangent frame; this reads the
## SAME frame + ground_sample so a new roster entry lands on honest
## ground. No world boot: pure climate reads.
## Run: godot --headless --path . --script res://tests/diag_spawn_bearings.gd
extends SceneTree

const TerrainGen = preload("res://scenes/worlds/terrain_gen.gd")

const BAND := {
	0: "OCEAN_DEEP", 1: "OCEAN_SHELF", 2: "SHORE", 3: "ALPINE",
	4: "TUNDRA", 5: "DESERT", 6: "SWAMP", 7: "TAIGA", 8: "FOREST",
	9: "GRASSLAND", 10: "ALPINE_MEADOW", 11: "LAKE", 12: "RIVER",
	13: "JUNGLE", 14: "SAVANNA", 15: "STEPPE", 16: "BADLANDS",
}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var seed_bytes: PackedByteArray = TerrainGen.world_seed_bytes()
	var center: Vector3 = TerrainGen.SPAWN_CENTER
	var east: Vector3 = Vector3(0, 1, 0).cross(center).normalized()
	var north: Vector3 = center.cross(east).normalized()
	print("SPAWN_CENTER=", center)
	for reach in [0.25, 0.30, 0.35, 0.40, 0.45]:
		var row := "reach %.2f rad:" % reach
		for b in range(90, 230, 10):
			var rad: float = deg_to_rad(float(b))
			var dir: Vector3 = (center + east * (reach * cos(rad)) \
				+ north * (reach * sin(rad))).normalized()
			var s = TerrainGen.ground_sample(dir, seed_bytes)
			row += " %d:%s(h=%d)" % [b, BAND.get(s.biome_id, str(s.biome_id)), int(s.height)]
		print(row)
	quit(0)
