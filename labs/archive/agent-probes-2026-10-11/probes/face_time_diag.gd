## DIAG (2026-10-18, updated after 1st run): per-face streaming cost at
## 20 km — sizes the probe_stream_continent chunk split (CI/sandbox
## wall-clock caps). Run from a scratch copy inside game/tests (res://
## cannot reach dev_temp): cd game && godot --headless --path . --script
## res://tests/_scratch_face_time.gd after copying this file there.
## 1st-run verdict: BOOT_MS=76517, FACE=0 MS=57075, warm faces did not
## finish in the remaining ~37s => ~50 s/face steady => 20-face walk
## ~= 15-20 min single-process; shards must be small and few.
extends SceneTree

const GLOBE_SCENE := "res://scenes/worlds/globe_world.tscn"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	ProjectSettings.set_setting("synmergia/world/planet_radius", 20000.0)
	var t0: int = Time.get_ticks_msec()
	var packed_big: PackedScene = load(GLOBE_SCENE)
	var globe_big: Node3D = packed_big.instantiate()
	root.add_child(globe_big)
	await root.get_tree().process_frame
	await root.get_tree().physics_frame
	var t1: int = Time.get_ticks_msec()
	print("BOOT_MS=%d" % (t1 - t0))
	var st_big = globe_big.get("streamer")
	var F = load("res://core/frame/math/icosahedral_faces.gd")
	var total := 0
	for f in range(F.face_count()):
		var ts: int = Time.get_ticks_msec()
		var cdir: Vector3 = F.face_center(f)
		st_big.update(cdir * 20000.0)
		await root.get_tree().physics_frame
		var dt: int = Time.get_ticks_msec() - ts
		total += dt
		print("FACE=%d MS=%d" % [f, dt])
	print("WALK_TOTAL_MS=%d ALL_MS=%d" % [total, Time.get_ticks_msec() - t0])
	quit(0)
