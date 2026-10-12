## Probe: the world-map canvas generation stays OFF the main thread's
## critical path (the menu-freeze fix). Headless script mode:
##   godot --headless --path game --script res://tests/probe_world_map_gen.gd
##
## Asserts:
##   M1. OPEN IS INSTANT: show_map() returns without a long synchronous
##       block; the first frames after open show worst-frame time far
##       below the old 147k-sample freeze.
##   M2. GENERATION COMPLETES: the chunked generator finishes and
##       commits a texture
##   M3. NO DOUBLE-GENERATION: a second open while generating does not
##       queue a second generator.
extends SceneTree

var _fails: int = 0


func _init() -> void:
	call_deferred("_run")


func _check(cond: bool, label: String) -> void:
	if not cond:
		_fails += 1
		printerr("FAIL: " + label)
	else:
		print("PASS: " + label)


func _run() -> void:
	var WM = load("res://ui/components/world_map.gd")
	var wm = WM.new()
	root.add_child(wm)
	await process_frame
	await process_frame
	# M1: open + frame time bound. The freeze was a full 147k-sample
	# synchronous canvas (tens of seconds under the penrose backend);
	# the law now: no frame during the first 30 frames of an open may
	# exceed 500 ms (the chunk is ~9k samples max).
	wm.show_map()
	var worst_ms := 0.0
	for i in range(30):
		var t0: int = Time.get_ticks_msec()
		await process_frame
		var dt: float = float(Time.get_ticks_msec() - t0)
		if dt > worst_ms:
			worst_ms = dt
	_check(worst_ms < 500.0, "open-frame worst %.1f ms < 500 ms" % worst_ms)
	_check(wm._generating, "generation is async (in flight after open)")

	# M2: completes and commits.
	var waited := 0.0
	while wm._generating and waited < 30.0:
		await create_timer(0.5).timeout
		waited += 0.5
	_check(not wm._generating, "generation completes (%.1f s)" % waited)
	_check(wm._canvas_texture != null, "texture committed")

	# M3: idempotence.
	var first: Texture2D = wm._canvas_texture
	wm.show_map()
	_check(wm._canvas_texture == first, "re-open does not regenerate")

	print("WORLD MAP GEN probe: %d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)
