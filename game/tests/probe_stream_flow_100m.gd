## Terrain streaming probe, CHUNK 1 of 2 (prototype flow laws)
## Carved from probe_terrain_stream.gd (prd-spherical-mvp.md S5) so
## CI minutes fit: this chunk runs only the 100 m prototype globe
## (cheap). The planet-scale skirt/checks live in
## probe_stream_continent_20km.gd (chunk 2, heavy).
## Run headless: godot --headless --path . --script res://tests/probe_stream_flow_100m.gd
## Run rendered: GODOT_PROBE_XVFB=1 xvfb-run -a godot --path . --script res://tests/probe_stream_flow_100m.gd
##   -> writes /tmp/play/stream_stage{1,2}.png
extends SceneTree

const GLOBE_SCENE := "res://scenes/worlds/globe_world.tscn"
const FacesScript := "res://core/frame/math/icosahedral_faces.gd"

var _globe: Node3D


func _init() -> void:
	# Reads icosa STREAMER internals (level/edge + Sundered deep beds);
	# pin the renderer so the default clipmap does not change what it inspects.
	ProjectSettings.set_setting("synmergia/world/terrain_render", "streamer")
	call_deferred("_run")


func _run() -> void:
	# PROTOTYPE-SCALE CONTRACT: streaming order/unload laws at the 100 m
	# shell (the shipped game boots 20 km with terrain; probe_terrain_planet
	# and chunk 2 cover that). Pin the prototype radius explicitly.
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
	# THE ASYNC WANT SET (planar mode removed): the prototype globe is a
	# REAL terrain globe now, so the current face mounts sync and its 3
	# neighbors ride the worker lane. The 4-patch law is a SETTLE law,
	# not a first-frame law -- wait for the lane to drain, then read.
	await _settle()
	var initial: Array = _globe.stream_active_faces()
	ok = _check("initial want set settles at 4 patches (got %d)" % initial.size(), initial.size() == 4) and ok
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
	await _settle()
	ok = _check("steady state settles at 4 patches (got %d)" % _globe.stream_active_faces().size(), \
		_globe.stream_active_faces().size() == 4) and ok

	# TERRAIN LOD (the NEAR law) -- the inverse of the old prototype pin:
	# with planar mode removed the 100 m globe IS a terrain globe, so the
	# LOD lane must be LIVE here. The near face sits at the base level and
	# every other live face sits at the base level or the floor clamp. The
	# floor is a planet-scale constant and reads FINER than the prototype
	# base; that inversion is the standing clamp law, recorded rather than
	# hidden.
	var base_lvl: int = streamer._level_for_edge()
	var floor_lvl: int = streamer.LOD_FLOOR_LEVEL
	var lvl_ok: bool = int(streamer._patch_lvl.get(streamer.current_face, -1)) == base_lvl
	for f in streamer.active_faces():
		var lv: int = int(streamer._patch_lvl.get(f, -1))
		if lv != base_lvl and lv != floor_lvl:
			lvl_ok = false
	ok = _check("terrain globe runs the LOD law (base %d, floor %d)" % [base_lvl, floor_lvl], lvl_ok) and ok
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
		# The want set never exceeds the 4-face law; its neighbors land
		# on the lane (the settle below pins the completion).
		if stats["active"].size() > 4:
			sweep_ok = false
			break
	ok = _check("all 20 faces stream (sync current face, 4-face want bound)", sweep_ok) and ok
	# The sweep drives update() by hand; the globe's own per-frame update
	# then takes the wheel back and re-demands the PLAYER's want set. Pin
	# that the streamer re-settles to exactly that set (waiting on a bare
	# pending count here would race the hand-back).
	ok = _check("post-sweep world re-settles the player's want set", await _settle_want()) and ok

	if not ok:
		push_error("TERRAIN STREAM FLOW PROBE FAILED")
	quit(0 if ok else 1)


## Bounded lane settle: cold installs land on later frames, so the
## 4-face want set is a SETTLE law. Waits on the MESH lane only (the
## prop lane is a separate, slower census) plus a few frames for the
## deferred applies to run.
func _settle(seconds: float = 30.0) -> void:
	var st = _globe.get("streamer")
	var waited: float = 0.0
	while st != null and st._mesh_pending() > 0 and waited < seconds:
		await root.get_tree().physics_frame
		waited += 1.0 / 60.0
	for _i in range(4):
		await root.get_tree().physics_frame


## Wait until the MESH lane is idle AND the live set is exactly the
## current face's want set (face + 3 neighbors). Bounded at 60 s: the
## headless VM's derives are multi-second, so this is a settle law.
func _settle_want(seconds: float = 60.0) -> bool:
	var F = load(FacesScript)
	var st = _globe.get("streamer")
	var waited: float = 0.0
	while waited < seconds:
		await root.get_tree().physics_frame
		waited += 1.0 / 60.0
		if st._mesh_pending() > 0:
			continue
		var cur: int = int(st.current_face)
		var want: Array = F.neighbors(cur)
		want.append(cur)
		var active: Array = _globe.stream_active_faces()
		if active.size() != want.size():
			continue
		var all_want := true
		for f in active:
			if not want.has(f):
				all_want = false
		if all_want:
			return true
	return false


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
