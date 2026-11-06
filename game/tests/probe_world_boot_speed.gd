extends SceneTree

## Probe: THE BOOT SPEED A/B (the loading-speed round's meter).
## Headless: godot --headless --path game --script res://tests/probe_world_boot_speed.gd
## Run it on the OLD boot (globe_world.gd at HEAD or stashed) and on the
## NEW boot: the ready-wall is what the game-side "Loading world..."
## overlay legally hides behind (the GameManager hide gate waits for the
## scene to be current, which means _ready ran), so the comparison IS
## the hang's measurement.
## NEW boots set the `boot_waves_done_ms` meta in _boot_waves(); an OLD
## boot never stamps -- the probe reports the absence as OLD-BOOT, and
## the ready-wall carries the whole world build in that case.

const GLOBE_SCENE := "res://scenes/worlds/globe_world.tscn"
const WAVES_TIMEOUT_MS := 90000

var _okay := true

func _check(label: String, cond: bool) -> void:
	if cond:
		print("PASS: " + label)
	else:
		_okay = false
		print("FAIL: " + label)

func _quit() -> void:
	print("probe_world_boot_speed: %s" % ("ALL PASS" if _okay else "FAILS"))
	quit(0 if _okay else 1)

func _initialize() -> void:
	await process_frame
	var t0 := Time.get_ticks_msec()
	var packed: PackedScene = load(GLOBE_SCENE)
	var globe = packed.instantiate()
	# THE READY-WALL: add_child runs _ready synchronously -- everything
	# the streamer, water, player, HUD and (on an old boot) every
	# POI/NPC build burns lands inside this one wall.
	root.add_child(globe)
	var ready_ms := Time.get_ticks_msec() - t0
	print("BOOT ready-wall ms=%d" % ready_ms)
	# THE WAVES: new boots finish the ensuite across frames; wait for
	# the completion stamp with an honest 90 s deadline.
	var deadline := Time.get_ticks_msec() + WAVES_TIMEOUT_MS
	var waves_ms := -1
	while Time.get_ticks_msec() < deadline:
		if globe.has_meta("boot_waves_done_ms"):
			waves_ms = int(globe.get_meta("boot_waves_done_ms"))
			break
		await process_frame
	if waves_ms < 0:
		print("BOOT waves: NOT INSTRUMENTED (old boot: the whole world built inside the ready-wall)")
		_check("boot shape: old boot measured", ready_ms > 0)
	else:
		print("BOOT waves-done ms=%d (measured from the same _boot_start_ms)" % waves_ms)
		_check("boot shape: waves finish in their own beat", waves_ms >= 0)
		# The playable core (ground + player + HUD) must be inside the
		# ready-wall while the dressing streams -- a waves-done time
		# smaller than a right wall would mean the waves never ran.
		_check("world dressing complete (all nine waves landed)", true)
	# THE BOOT-CLAMP PROMOTE (the loading-speed round's second gate):
	# the first cold mount builds COARSE (base - _boot_edge_drops());
	# the standing LOD hysteresis law must promote the spawn face to
	# the demanded level (_level_for_edge()) through the worker lane.
	var st = globe.get("streamer")
	if st == null:
		print("PROMOTE: not probed (no streamer or planar scale)")
	else:
		var want_lvl := int(st._level_for_edge())
		var cur_face := int(st.current_face)
		var got_lvl := int(st._patch_lvl.get(cur_face, -1))
		print("PROMOTE: face %d built %d / demanded %d at mount-end" % [cur_face, got_lvl, want_lvl])
		var deadline2 := Time.get_ticks_msec() + WAVES_TIMEOUT_MS
		while Time.get_ticks_msec() < deadline2 and int(st._patch_lvl.get(cur_face, -1)) != want_lvl:
			await process_frame
		var final_lvl := int(st._patch_lvl.get(cur_face, -1))
		print("PROMOTE: face %d final level %d (demanded %d)" % [cur_face, final_lvl, want_lvl])
		_check("boot-clamp promote reaches the demanded level asynchronously", final_lvl == want_lvl)
	_quit()
