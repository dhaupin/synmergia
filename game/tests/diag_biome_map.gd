## diag_biome_map - the world-crafting scan. Samples a fibonacci sphere
## across the WHOLE planet, classifies every sample's climate band, and
## reports:
##   1) GLOBAL totals: per-band sample share (what the seed contains)
##   2) FACE matrix: per base face, which bands live there (samples
##      bucketed to the nearest face center) -- where deserts, fungal
##      groves, rivers, lakes, tundra and badlands actually are
##   3) LAND FACE ask: what the v9 face-band ask resolves per face
## No world boot needed: pure climate reads on the main thread.
## Run headless: godot --headless --path . --script res://tests/diag_biome_map.gd
extends SceneTree

const TerrainGen = preload("res://scenes/worlds/terrain_gen.gd")
const FacePatches = preload("res://core/frame/math/icosahedral_faces.gd")
const SAMPLES := 6000

const BAND_NAMES := {
	0: "OCEAN_DEEP", 1: "OCEAN_SHELF", 2: "SHORE", 3: "ALPINE",
	4: "TUNDRA", 5: "DESERT", 6: "SWAMP", 7: "TAIGA", 8: "FOREST",
	9: "GRASSLAND", 10: "ALPINE_MEADOW", 11: "LAKE", 12: "RIVER",
	13: "JUNGLE", 14: "SAVANNA", 15: "STEPPE", 16: "BADLANDS",
}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# the world seed: the same seed bytes the game and streamer boot
	# with (TerrainGen resolves the project's world law).
	var seed_bytes: PackedByteArray = TerrainGen.world_seed_bytes()
	var total := {}
	var face_hist := {}
	for f in range(20):
		face_hist[f] = {}
	var golden: float = 2.399963229728653
	for i in range(SAMPLES):
		var y: float = 1.0 - 2.0 * (float(i) + 0.5) / float(SAMPLES)
		var rad: float = sqrt(max(1.0 - y * y, 0.0))
		var th: float = golden * float(i)
		var dir := Vector3(cos(th) * rad, y, sin(th) * rad)
		var bid: int = TerrainGen.climate_biome_id(dir, seed_bytes)
		var bname: String = BAND_NAMES.get(bid, str(bid))
		total[bname] = int(total.get(bname, 0)) + 1
		# nearest face center bucket
		var best_f := 0
		var best_d := -9.9
		for f in range(20):
			var d: float = dir.dot(FacePatches.face_center(f).normalized())
			if d > best_d:
				best_d = d
				best_f = f
		var fh: Dictionary = face_hist[best_f]
		fh[bname] = int(fh.get(bname, 0)) + 1
	print("BIOME_MAP seed_bytes=", seed_bytes.size(), " loaded")
	print("GLOBAL share (n=%d):" % SAMPLES)
	var keys := total.keys()
	keys.sort()
	for k in keys:
		print("  %-14s %5d  %.1f%%" % [k, int(total[k]), 100.0 * float(total[k]) / float(SAMPLES)])
	print("FACE matrix (bands -> samples):")
	for f in range(20):
		var hk := (face_hist[f] as Dictionary).keys()
		hk.sort()
		var band_str := ""
		for k in hk:
			band_str += "%s=%d " % [k, int(face_hist[f][k])]
		print("  face=%2d  %s" % [f, band_str.strip_edges()])
	quit(0)
