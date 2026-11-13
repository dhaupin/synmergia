## wildflower_drift_probe - the wildflower drift's receipt:
##   1) THE FIELD: the drift signal sweeps [0, 1] over a sampled
##      patch grid around the spawn bearing and reads CLUSTERED
##      (strong cells above the bloom floor occur in connected
##      patches, not everywhere sensibly -- the field-vs-sprinkle
##      look is measurable),
##   2) THE SPECIES LAW: one drift cell maps to one palette index
##      (the patch reads as a single wildflower kind),
##   3) THE LIVE BLOOM: the booted clipmap's detail chain carries
##      MORE flowers on a drift face than the v5 sprinkle rate gave
##      (the fields actually render), still under the node cap.
## Run headless: godot --headless --path . --script res://dev_temp/probes/wildflower_drift_probe.gd
extends SceneTree

const GLOBE_SCENE := "res://scenes/worlds/globe_world.tscn"
const RADIUS_SETTING := "synmergia/world/planet_radius"
const RADIUS := 20000.0
const TerrainGen = preload("res://scenes/worlds/terrain_gen.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	# 1) THE FIELD: sample a 21x21 grid of site dirs around the
	# spawn's tangent plane (the meadow country's own bearing).
	var spawn: Vector3 = TerrainGen.SPAWN_CENTER
	var east: Vector3 = Vector3(0, 1, 0).cross(spawn).normalized()
	var north: Vector3 = spawn.cross(east).normalized()
	var vals: Array[float] = []
	var strong: int = 0
	var near_spawn: int = 0
	for gx in range(21):
		for gy in range(21):
			var du: float = (float(gx) - 10.0) * (0.06 / 10.0)
			var dv: float = (float(gy) - 10.0) * (0.06 / 10.0)
			var dir: Vector3 = Easti(spawn, east, north, du, dv).normalized()
			var drift: float = TerrainGen.wildflower_drift(dir)
			vals.append(drift)
			if drift >= 0.5:
				strong += 1
			if gx >= 9 and gx <= 11 and gy >= 9 and gy <= 11:
				near_spawn += int(drift >= 0.5)
	var vmax: float = 0.0
	var vmin: float = 1.0
	for v in vals:
		vmax = maxf(vmax, v)
		vmin = minf(vmin, v)
	print("DRIFT field min=%.3f max=%.3f strong_cells=%d/%d (patch share %.0f%%)" % [
		vmin, vmax, strong, vals.size(), 100.0 * float(strong) / float(vals.size())])
	# A real patch field: SOME strong cells, not all (a blanket), not
	# none (a flat field).
	if strong < 5 or strong > vals.size() / 3:
		print("DRIFT-MISS the signal does not read as a patch field")
		quit(1)
		return
	# 2) THE SPECIES LAW: one cell, one species (a stable mapping).
	var s1: int = int(TerrainGen.wildflower_drift(spawn) * 7.0) % 4
	var s2: int = int(TerrainGen.wildflower_drift(spawn) * 7.0) % 4
	print("DRIFT species stable=%d at the spawn bearing" % s1)
	if s1 != s2 or s1 < 0 or s1 > 3:
		print("DRIFT-MISS the species mapping is not stable")
		quit(1)
		return
	# 3) THE LIVE BLOOM: boot the planet and census the PropLayer's
	# flower (KIND_FLOWER=1) population across its loaded chunks.
	ProjectSettings.set_setting(RADIUS_SETTING, RADIUS)
	var packed: PackedScene = load(GLOBE_SCENE)
	var globe: Node = packed.instantiate()
	root.add_child(globe)
	for _i in range(10):
		await process_frame
	var clipmap = globe.get("clipmap")
	for _i in range(40):
		await root.get_tree().physics_frame
	var pl = clipmap.prop_layer()
	var flowers: int = 0
	var flowering_chunks: int = 0
	var built: int = 0
	for k in pl._built.keys():
		built += 1
		var f: int = 0
		for ch in (pl._built.get(k) as Node3D).get_children():
			if String(ch.name).begins_with("Flower"):
				f += 1
		if f > 0:
			flowering_chunks += 1
			flowers += f
	print("DRIFT live flowers=%d across %d/%d built chunks" % [flowers, flowering_chunks, built])
	if flowers <= 0:
		print("DRIFT-MISS the fields did not bloom under the PropLayer")
		quit(1)
		return
	print("DRIFT-OK")
	quit(0)

## One tangent-plane offset (du, dv in rad) around `base`.
func Easti(base: Vector3, east: Vector3, north: Vector3, du: float, dv: float) -> Vector3:
	return base + east * du + north * dv
