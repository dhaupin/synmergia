## probe_walk_mesh_gap - the play-day clipping measurement.
## Within a small angular window around the player at the 20 km
## planet scale, pair the DRAWN patch triangles (mesh truth) with the
## ANALYTIC walk law the player pad / props / spawns ride, and report
## the gap: positive = the drawn surface sits ABOVE where placements
## land ("player under the terrain"), negative = placements float.
## Run headless:   godot --headless --path . --script res://tests/probe_walk_mesh_gap.gd
extends SceneTree

const GLOBE_SCENE := "res://scenes/worlds/globe_world.tscn"
const RADIUS_SETTING: String = "synmergia/world/planet_radius"
const RADIUS := 20000.0
const NEAR_ANG := 0.05  # ~1 km ground arc around the player dir

var _globe: Node3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	ProjectSettings.set_setting(RADIUS_SETTING, RADIUS)
	var packed: PackedScene = load(GLOBE_SCENE)
	_globe = packed.instantiate()
	root.add_child(_globe)
	for _i in range(6):
		await process_frame
	for _i in range(60):
		await root.get_tree().physics_frame

	var streamer = _globe.get("streamer")
	var player = _globe.get("player")
	var planet_center: Vector3 = _globe.get("planet_center")
	var radius_pl: float = _globe.get("planet_radius")
	var pdir: Vector3 = (player.global_position - planet_center).normalized()

	print("player r-planet=", (player.global_position - planet_center).length() - radius_pl)
	print("player dir=", pdir)

	var n_shown := 0
	var worst := 0.0
	for face in streamer.active_faces():
		var mi: MeshInstance3D = streamer._patches.get(face)
		if mi == null or mi.mesh == null:
			continue
		var xf: Transform3D = mi.global_transform
		var mesh: Mesh = mi.mesh
		for si in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(si)
			if arrays == null:
				continue
			var verts_v = arrays[Mesh.ARRAY_VERTEX]
			if verts_v == null:
				continue
			var verts: PackedVector3Array = verts_v
			var idx_v = arrays[Mesh.ARRAY_INDEX]
			var idx: PackedInt32Array = PackedInt32Array(idx_v) if idx_v != null \
				else PackedInt32Array()
			var faces: PackedInt32Array = PackedInt32Array(idx) if idx.size() > 0 \
				else PackedInt32Array(range(verts.size()))
			for t in range(0, faces.size() - 2, 3):
				var wp: Vector3 = xf * verts[faces[t]]
				var dir: Vector3 = (wp - planet_center).normalized()
				var ang: float = dir.angle_to(pdir)
				if ang > NEAR_ANG:
					continue
				var drawn_h: float = (wp - planet_center).length() - radius_pl
				var law_h: float = streamer.walk_surface_h(dir)
				var gap: float = drawn_h - law_h
				worst = maxf(worst, absf(gap))
				if n_shown < 24:
					n_shown += 1
					print("  face=%d dir=%v drawn=%8.2f law=%8.2f gap=%+8.2f" \
						% [face, dir, drawn_h, law_h, gap])
	print("NEAR_TRIANGLES compared; worst |gap| = %0.2f m" % worst)
	quit(0)
