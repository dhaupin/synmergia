## probe_tree_law_census - pure-law placement census for the tree
## scatter (no globe boot, no meshes). For the streamed set around the
## boot it walks the SAME site formula _spawn_trees pays: face seed ->
## count ladder -> barycentric dir -> ground/water skip -> species
## gate -> PLANTED. Prints per-face planted counts and the band
## membership around the boot (600 / 1200 / 2400 / 5000 m) + the
## nearest planted tree, so the placement law is measurable in
## milliseconds and tunable without a full engine boot.
## Run headless:   godot --headless --path . --script res://tests/probe_tree_law_census.gd
extends SceneTree

const TerrainGen = preload("res://scenes/worlds/terrain_gen.gd")
const Faces = preload("res://core/frame/math/icosahedral_faces.gd")
const Ico = preload("res://core/frame/math/icosahedral.gd")

const BANDS := [0.03, 0.06, 0.12, 0.25]
const NEAR_FACES := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var seed_b: PackedByteArray = TerrainGen.world_seed_bytes()
	var sea: float = TerrainGen.sea_level(seed_b)
	print("SEA=", sea)
	# The boot faces the law sees: the census needs the spawn direction,
	# not a live player (the stream tree node/batch split is the mesh
	# pass's concern; the LAW census pins placement + species only).
	var spawn_center: Vector3 = TerrainGen.SPAWN_CENTER
	var per_face_planted := {}
	var band_counts := [0, 0, 0, 0]
	var nearest_ang := 999.0
	var nearest_face := -1
	var biome_counts := {}
	for face in NEAR_FACES:
		var center: Vector3 = Faces.face_center(face)
		if center.angle_to(spawn_center) > 1.0:
			continue  # the streamed near set (the boot's own hemisphere)
		var bytes: PackedByteArray = TerrainGen.face_seed_bytes(seed_b, face)
		var acc: int = 0
		for b in bytes:
			acc = (acc * 131 + b) % 9007199254740991
		var rng := RandomNumberGenerator.new()
		rng.seed = acc
		var count := 0
		var cbid: int = TerrainGen.climate_biome_id(center.normalized(), seed_b)
		if cbid == TerrainGen.BiomeId.FOREST or cbid == TerrainGen.BiomeId.TAIGA \
				or cbid == TerrainGen.BiomeId.JUNGLE:
			count = rng.randi_range(1400, 2100)
		elif cbid == TerrainGen.BiomeId.SWAMP:
			count = rng.randi_range(300, 460)
		elif cbid == TerrainGen.BiomeId.GRASSLAND:
			count = rng.randi_range(2200, 3000)
		elif cbid == TerrainGen.BiomeId.SAVANNA:
			count = rng.randi_range(400, 640)
		elif cbid == TerrainGen.BiomeId.SHORE:
			count = rng.randi_range(400, 640)
		elif cbid == TerrainGen.BiomeId.DESERT or cbid == TerrainGen.BiomeId.TUNDRA \
				or cbid == TerrainGen.BiomeId.STEPPE or cbid == TerrainGen.BiomeId.BADLANDS:
			count = rng.randi_range(80, 140)
		else:
			count = rng.randi_range(12, 24)
		var verts: PackedInt32Array = Faces.face_vertices(face)
		var planted := 0
		for _i in range(count):
			var v: Vector3 = Ico.VERTICES[verts[rng.randi_range(0, 2)]].normalized()
			var v2: Vector3 = Ico.VERTICES[verts[rng.randi_range(0, 2)]].normalized()
			var dir: Vector3 = (center * 0.25 + v * 0.35 + v2 * 0.40).normalized()
			# THE BOOT GROVE PULL (mirrors _spawn_trees's v4 law).
			if center.angle_to(spawn_center) < TerrainGen.HOMELAND_ANGULAR_REACH:
				dir = dir.slerp(spawn_center, 0.62)
			var base_h: float = TerrainGen.terrain_height(dir, seed_b)
			if base_h < sea - 0.6:
				continue
			var bid: int = TerrainGen.climate_biome_id(dir, seed_b)
			biome_counts[bid] = int(biome_counts.get(bid, 0)) + 1
			var draw: float = rng.randf()
			if bid == TerrainGen.BiomeId.FOREST or bid == TerrainGen.BiomeId.TAIGA \
					or bid == TerrainGen.BiomeId.JUNGLE:
				pass
			elif bid == TerrainGen.BiomeId.SWAMP:
				if draw > 0.5:
					continue
			elif bid == TerrainGen.BiomeId.GRASSLAND:
				if draw > 0.4:
					continue
			elif bid == TerrainGen.BiomeId.SHORE:
				if draw > 0.25:
					continue
			elif bid == TerrainGen.BiomeId.SAVANNA:
				if draw > 0.3:
					continue
			else:
				continue
			planted += 1
			var ang: float = dir.angle_to(spawn_center)
			for bi in range(BANDS.size()):
				if ang <= float(BANDS[bi]):
					band_counts[bi] += 1
					break
			if ang < nearest_ang:
				nearest_ang = ang
				nearest_face = face
		per_face_planted[face] = {"biome": cbid, "sites": count, "planted": planted}
	for face in per_face_planted:
		print("FACE=", face, " ", str(per_face_planted[face]))
	for bi in range(BANDS.size()):
		print("BAND <=%4.2f rad (boot-planted trees): %d" % [float(BANDS[bi]), band_counts[bi]])
	print("NEAREST planted: ang=", nearest_ang, " face=", nearest_face)
	print("BIOME_LADDER at plantable sites=", str(biome_counts))
	quit(0)
