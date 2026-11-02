## Terrain streaming probe, CONTINENT SHARD d of 4 (faces 15..19)
## The former probe_stream_continent_20km tie-together walk (itself
## carved from probe_terrain_stream.gd, prd-spherical-mvp.md S5/S8)
## sharded by icosa-face range so each process fits a wall-clock cap:
## boot at 20 km costs ~76 s and one streamed face ~50 s (measured,
## dev_temp/probes/face_time_diag.gd), so 5 faces + boot ~= 5.5 min.
## Each shard boots its own globe and walks ITS FIVE faces through the
## live update() one frame apart: cold spawns, cross-face hot swaps
## (demote+promote), the skirt taper, and the prop-holder graft with
## the REAL heightfield. Per-stop assertions: the walk law the faces
## serve equals the analytic law at that face's center (one ground
## truth with no cracks), and the props that streamed in SURVIVE
## their own face's unload/reload cycles (no corpses in the audit).
## Siblings: _a (0..4), _b (5..9), _c (10..14).
## Run headless: godot --headless --path . --script res://tests/probe_stream_continent_d.gd
extends SceneTree

const GLOBE_SCENE := "res://scenes/worlds/globe_world.tscn"
const FacesScript := "res://core/frame/math/icosahedral_faces.gd"
const PLANET_RADIUS_20KM: float = 20000.0
## This shard's face range (the icosa has 20 faces, swept in order).
const FACE_LO: int = 15
const FACE_HI: int = 19

var _globe: Node3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok := true
	ProjectSettings.set_setting("synmergia/world/planet_radius", PLANET_RADIUS_20KM)

	var packed_big: PackedScene = load(GLOBE_SCENE)
	var globe_big: Node3D = packed_big.instantiate()
	root.add_child(globe_big)
	await root.get_tree().process_frame
	await root.get_tree().physics_frame
	var st_big = globe_big.get("streamer")
	var F = load(FacesScript)
	var Gen = load("res://scenes/worlds/terrain_gen.gd")
	var seed_big: PackedByteArray = st_big.world_seed
	var tie_ok := true
	var live_rocks := 0
	var stale_refs := 0
	for f in range(FACE_LO, FACE_HI + 1):
		var cdir: Vector3 = F.face_center(f)
		st_big.update(cdir * PLANET_RADIUS_20KM)
		await root.get_tree().physics_frame
		# One ground truth: the streamed walk law at this face's center
		# equals the analytic heightfield + its rocks (LOD or not).
		var streamed_h: float = st_big.walk_surface_h(cdir)
		var law_h: float = Gen.terrain_height(cdir, seed_big) + Gen.rock_top_height(cdir, seed_big, f, PLANET_RADIUS_20KM)
		if absf(streamed_h - law_h) > 0.01:
			tie_ok = false
			print("TIE-FAIL face=%d streamed=%.3f law=%.3f" % [f, streamed_h, law_h])
		# Audit the whole walk so far: no freed refs anywhere.
		for fa in st_big.active_faces():
			for r in (st_big._patch_rocks.get(fa, []) as Array):
				live_rocks += 1
				if not is_instance_valid(r):
					stale_refs += 1
	var totals: Array = [live_rocks, stale_refs]
	ok = _check("continent walk faces %d..%d: analysis == streamed ground law" % [FACE_LO, FACE_HI], tie_ok) and ok
	ok = _check("continent walk faces %d..%d: %d live rocks, %d stale refs after the hot-path window" % ([FACE_LO, FACE_HI] + totals), \
		stale_refs == 0 and live_rocks > 0) and ok
	var surfaces_ok := true
	for fa in st_big.active_faces():
		var mi_f: MeshInstance3D = st_big._patches.get(fa)
		if mi_f == null or mi_f.mesh == null or mi_f.mesh.get_surface_count() < 2:
			surfaces_ok = false
	ok = _check("continent walk faces %d..%d: ground + skirt surfaces on every streamed face" % [FACE_LO, FACE_HI], surfaces_ok) and ok
	globe_big.queue_free()
	await root.get_tree().process_frame
	if not ok:
		push_error("TERRAIN STREAM CONTINENT SHARD d FAILED")
	quit(0 if ok else 1)


func _check(label: String, cond: bool) -> bool:
	print("  %s %s" % ["PASS" if cond else "FAIL", label])
	return cond
