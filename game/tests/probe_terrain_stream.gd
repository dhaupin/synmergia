## Terrain streaming probe (prd-spherical-mvp.md S5)
## Run headless: godot --headless --path . --script res://tests/probe_terrain_stream.gd
## Run rendered: GODOT_PROBE_XVFB=1 xvfb-run -a godot --path . --script res://tests/probe_terrain_stream.gd
##   -> writes /tmp/play/stream_stage{1,2}.png
extends SceneTree

const GLOBE_SCENE := "res://scenes/worlds/globe_world.tscn"
const FacesScript := "res://core/frame/math/icosahedral_faces.gd"

var _globe: Node3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# PROTOTYPE-SCALE CONTRACT: streaming order/unload laws at the 100 m
	# shell (the shipped game boots 20 km with terrain; probe_terrain_planet
	# covers that). Pin the prototype radius explicitly.
	ProjectSettings.set_setting("synmergia/world/planet_radius", 100.0)
	var ok := true
	var packed: PackedScene = load(GLOBE_SCENE)
	if packed == null or not packed.can_instantiate():
		push_error("FAIL: globe scene did not load")
		quit(1)
		return
	_globe = packed.instantiate()
	root.add_child(_globe)

	var player = _globe.get("player")
	if player == null or player.get_script() == null:
		push_error("FAIL: player missing (parse error upstream?)")
		quit(1)
		return
	await root.get_tree().physics_frame
	await root.get_tree().physics_frame

	var streamer = _globe.get("streamer")
	if streamer == null:
		push_error("FAIL: streamer missing (stream_terrain off?)")
		quit(1)
		return

	# --- Invariant 1: initial active set = spawn face + 3 neighbors.
	var F0 = load(FacesScript)
	var spawn_face: int = F0.face_for_direction(_globe.player.global_position)
	var initial: Array = _globe.stream_active_faces()
	ok = _check("initial active == 4 patches (got %d)" % initial.size(), initial.size() == 4) and ok
	ok = _check("spawn face %d active" % spawn_face, streamer.is_loaded(spawn_face)) and ok
	var tris: int = _globe.stream_triangle_count()
	ok = _check("patch geometry present (%d tris)" % tris, tris > 500) and ok
	_shoot("stream_stage1")

	# --- Invariant 2: crossing a face border swaps stale patches.
	# Relocate to the face whose center is at lat 19.4712, lon 0 (id
	# derived from the primitive, never hardcoded).
	var F1 = load(FacesScript)
	var Sph = load("res://core/frame/math/spherical.gd")
	var target_dir: Vector3 = Sph.spherical_to_cartesian(19.4712, 0.0, 0.0, _globe.planet_radius)
	var target_face: int = F1.face_for_direction(target_dir)
	var spawn: Vector3 = target_dir.normalized() * (_globe.planet_radius + 1.0)
	player.global_position = spawn
	player.velocity = Vector3.ZERO
	player.begin_loop()
	await root.get_tree().physics_frame
	await root.get_tree().physics_frame
	await root.get_tree().physics_frame

	var start_face: int = streamer.current_face
	ok = _check("relocated to face %d (got %d)" % [target_face, start_face], start_face == target_face) and ok
	var before_set: Array = _globe.stream_active_faces()

	player.auto_walk = true
	var waited: float = 0.0
	var crossed := false
	var walked_to_cross: float = 0.0
	# SEED-ROBUST LAW (the v3 ruleset re-derives rocks/trees, so a re-
	# rolled boulder CAN sit in the straight path on a 30 m prototype
	# face): the walk tries a small fan of headings, one after another,
	# until the face boundary swaps under the player OR the clock runs
	# out. The pin is the FLOW LAW (crossing swaps the stale set), not
	# "the seed placed no tree at lat 19.4712".
	for _heading in range(9):
		# Steer: the prototype walker walks its own facing; nudge it by
		# rotating the target around the planet axis via a position
		# teleport to a heading-perturbed point INSIDE the same face.
		if _heading > 0:
			var cur: Vector3 = player.global_position
			var perturbed: Vector3 = cur.rotated(Vector3(0, 1, 0), float(_heading) * 0.18) \
				.normalized() * cur.length()
			player.global_position = perturbed
			player.velocity = Vector3.ZERO
			await root.get_tree().physics_frame
		player.auto_walk = true
		var last_face: int = streamer.current_face
		waited = 0.0
		while streamer.current_face == last_face and waited < 6.0:
			await root.get_tree().physics_frame
			waited += 1.0 / 60.0
		walked_to_cross += player.path_walked
		if streamer.current_face != last_face:
			crossed = true
			break
	player.auto_walk = false
	ok = _check("face crossed within %d m across heading fan (face %d -> %d)" % [int(walked_to_cross), start_face, streamer.current_face], crossed) and ok

	# The stale set changed: old face far from the new one is gone.
	var after_set: Array = _globe.stream_active_faces()
	var changed: bool = false
	for f in before_set:
		if not after_set.has(f):
			changed = true
	ok = _check("stale patch unloaded on crossing", changed) and ok
	ok = _check("steady state holds 4 patches (got %d)" % _globe.stream_active_faces().size(), \
		_globe.stream_active_faces().size() == 4) and ok

	# TERRAIN LOD (the NEAR law): after a mid-face crossing point on a
	# 100 m prototype knob... the prototype is TERRAIN OFF, so the
	# lean must be level-neutral there. The planet-scale demotion is
	# pinned by probe_terrain_planet via the mesh-vertex spacing; here
	# we pin that terrain_off keeps every patch at the base level.
	var base_lvl: int = streamer._level_for_edge()
	var lvl_ok := true
	for f in streamer.active_faces():
		if int(streamer._patch_lvl.get(f, -1)) != base_lvl:
			lvl_ok = false
	ok = _check("terrain-off globe keeps uniform detail (LOD dormant)", lvl_ok) and ok
	ok = _check("current face is loaded", streamer.is_loaded(streamer.current_face)) and ok
	_shoot("stream_stage2")

	# --- Invariant 3: all 20 faces individually loadable/unloadable.
	var F = load(FacesScript)
	var sweep_ok := true
	for f in range(F.face_count()):
		var center: Vector3 = F.face_center(f) * 101.0
		var stats: Dictionary = streamer.update(center)
		if streamer.current_face != f or not streamer.is_loaded(f):
			sweep_ok = false
			break
		if stats["active"].size() != 4:
			sweep_ok = false
			break
	ok = _check("all 20 faces stream (4-patch steady state)", sweep_ok) and ok

	ProjectSettings.set_setting("synmergia/world/planet_radius", 20000.0)

	# --- Tie-together: the seeded continent walks the FULL LOD path. --
	# Boot a planet-scale globe (terrain on), then traverse ALL 20 face
	# centers through the live update() one frame apart: this drives
	# cold spawns, cross-face hot swaps (demote+promote), the skirt
	# taper, and the prop-holder graft in one pass with the REAL
	# heightfield. Assertions per stop: the walk law the faces serve
	# equals the analytic law at that face's center (one ground truth
	# with no cracks), and the props that streamed in SURVIVE their
	# own face's unload/reload cycles (no corpses in the audit).
	var packed_big: PackedScene = load(GLOBE_SCENE)
	var globe_big: Node3D = packed_big.instantiate()
	root.add_child(globe_big)
	await root.get_tree().process_frame
	await root.get_tree().physics_frame
	var st_big = globe_big.get("streamer")
	var Gen = load("res://scenes/worlds/terrain_gen.gd")
	var seed_big: PackedByteArray = st_big.world_seed
	var tie_ok := true
	var live_rocks := 0
	var stale_refs := 0
	for f in range(F.face_count()):
		var cdir: Vector3 = F.face_center(f)
		st_big.update(cdir * 20000.0)
		await root.get_tree().physics_frame
		# One ground truth: the streamed walk law at this face's center
		# equals the analytic heightfield + its rocks (LOD or not).
		var streamed_h: float = st_big.walk_surface_h(cdir)
		var law_h: float = Gen.terrain_height(cdir, seed_big) + Gen.rock_top_height(cdir, seed_big, f, 20000.0)
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
	ok = _check("continent walk: analysis == streamed ground law on all 20 faces", tie_ok) and ok
	ok = _check("continent walk: %d live rocks, %d stale refs after the full hot-path traversal" % totals, \
		stale_refs == 0 and live_rocks > 0) and ok
	var surfaces_ok := true
	for fa in st_big.active_faces():
		var mi_f: MeshInstance3D = st_big._patches.get(fa)
		if mi_f == null or mi_f.mesh == null or mi_f.mesh.get_surface_count() != 2:
			surfaces_ok = false
	ok = _check("continent walk: ground + skirt surfaces on every streamed face", surfaces_ok) and ok
	globe_big.queue_free()
	await root.get_tree().process_frame
	if not ok:
		push_error("TERRAIN STREAM PROBE FAILED")
	quit(0 if ok else 1)


func _check(label: String, cond: bool) -> bool:
	print("  %s %s" % ["PASS" if cond else "FAIL", label])
	return cond


func _shoot(stage: String) -> void:
	if OS.get_environment("GODOT_PROBE_XVFB") == "":
		return
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	if img == null:
		push_error("no screenshot for %s" % stage)
		return
	var dir: String = "/tmp/play"
	DirAccess.make_dir_recursive_absolute(dir)
	img.save_png("%s/%s.png" % [dir, stage])
	print("  shot: %s/%s.png" % [dir, stage])
