extends SceneTree
## bench_coldboot_hose - A/B monitor for the async-mesh boot law.
##
## The sharding split did not shrink the cold derive cost: it moved
## WHEN the cost lands. Each face still derive-costs the same wall-ms
## on this 2-core host; the question this probe answers is the shape
## of the cost stream the player experiences during the boot:
##
##  - sync mode (default): every face derive runs inside the frame
##    loop, so the wall cost arrives as visible frame stalls around
##    the cold build burst. Peak frame ms ~ per-face derive ms.
##  - async mode (ASYNC_MESH=1): the mesh derives move to worker
##    threads; the main thread should show flat periodic frames with
##    no per-face spike while the tail checks drain. Any spike left in
##    async mode is honestly reported too — that is the part the
##    leg still pays on this host (grass/props/water still derive
##    on the main thread, and apply passes still run there).
##
## Honesty mode: NOTHING is skipped. The clipmap law is left to its
## natural behavior; neither mesh work nor prop work is hand-waved.
## This host is 2-core: async can only re-schedule, not parallelize,
## so the honest EXPECTATION on sync-vs-async total wall time here
## is parity-or-worse — the claim deferred to the >=4-core bench is
## that the win appears on machines with more cores. This probe
## measures and reports both numbers plainly.
##
## Run A: godot --headless --path game --script res://tests/bench_coldboot_hose.gd
## Run B: ASYNC_MESH=1 godot --headless --path game --script res://tests/bench_coldboot_hose.gd
## Output: one MODE=... line per run with the measured totals.

const GLOBE := "res://scenes/worlds/globe_world.tscn"
const PLANET_RADIUS_SET := "synmergia/world/planet_radius"

# Settle-window after boot before the timings start: lets the first
# stream update run but does not pre-cache face meshes (patch count
# starts at 0 the moment we start counting).
const WATCH_MAX_MS := 30000
const WATCH_DECIDE_INTERVAL_MS := 500

var globe = null
var clipmap = null

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var mode := "async" if OS.get_environment("ASYNC_MESH") == "1" else "sync"
	await process_frame
	# The A/B law: the probe owns the setting so the env truly flips
	# the gate (the project default is ON; a passive "sync" label
	# without the off flip would measure the async law twice).
	ProjectSettings.set_setting("synmergia/world/async_mesh", mode == "async")

	if not await _boot_globe():
		push_error("HOSE__FAIL__MODE=%s reason=boot-broken" % mode)
		quit(1)
		return

	# Baseline: after the boot loop, clipmap naturally starts the
	# cold face build. I start the clock the FIRST frame AFTER the
	# scene tree has registered the globe so nothing pre-paid is
	# counted.
	var t_start := Time.get_ticks_msec()

	var peak_frame_ms := 0.0
	var frame_count := 0
	var frame_ms_total := 0.0

	# Watch the stream settle: patch count stops growing AND both
	# pending counters hit zero.
	var prev_patch_count := 0
	var stable_since_msec := 0
	var settled := false

	while true:
		var now := Time.get_ticks_msec()
		if now - t_start > WATCH_MAX_MS:
			break
		var t_frame_us := Time.get_ticks_usec()
		await process_frame
		var dt := float(Time.get_ticks_usec() - t_frame_us)
		var frame_ms := dt / 1000.0
		frame_count += 1
		frame_ms_total += frame_ms
		if frame_ms > peak_frame_ms:
			peak_frame_ms = frame_ms

		if now - t_start > 1000:
			var pc: int = clipmap.patch_count()
			var pend_m: int = clipmap.pending_jobs()
			var pend_p: int = clipmap.prop_pending()
			if pc == prev_patch_count and pc > 0 and pend_m == 0 and pend_p == 0:
				if stable_since_msec == 0:
					stable_since_msec = now
				elif now - stable_since_msec >= WATCH_DECIDE_INTERVAL_MS:
					settled = true
					break
			else:
				stable_since_msec = 0
				prev_patch_count = pc

	var wall_ms := Time.get_ticks_msec() - t_start
	var avg_frame_ms := frame_ms_total / maxf(1.0, float(frame_count))
	var lane: Dictionary = clipmap.lane_stats() if clipmap.has_method("lane_stats") else {}

	print("HOSE__MODE=%s PANELS=" % mode)
	print("  wall_ms=", wall_ms, " settled=", settled)
	print("  patch_count=", clipmap.patch_count())
	print("  frame_n=", frame_count, " peak_frame_ms=", peak_frame_ms, " avg_frame_ms=", avg_frame_ms)
	print("  pending_mesh=", clipmap.pending_jobs(), " pending_props=", clipmap.prop_pending())
	print("  lane_stats=", lane)

	# Bounded drain before quit: with workers still in flight Godot
	# waits for the threads at exit; on a contended host that wait can
	# exceed the probe's budget and hang. Drain here (bounded 40 s),
	# printing nothing on failure but staying honest via a flag.
	var drained := true
	var drain_deadline := Time.get_ticks_msec() + 40000
	while clipmap.pending_jobs() > 0:
		await process_frame
		if Time.get_ticks_msec() > drain_deadline:
			drained = false
			break
	print("  drained=", drained, " lane_stats_after_drain=", (clipmap.lane_stats() if clipmap.has_method("lane_stats") else {}))

	_teardown()
	quit(0)

func _boot_globe() -> bool:
	ProjectSettings.set_setting(PLANET_RADIUS_SET, 20000.0)
	await process_frame
	var packed = load(GLOBE)
	if packed == null or not packed.can_instantiate():
		return false
	globe = packed.instantiate()
	root.add_child(globe)
	# The scene's `clipmap` var only resolves after the ready pass;
	# leave it untyped so whatever the property holds passes through.
	await process_frame
	clipmap = globe.get("clipmap")
	if clipmap == null:
		return false
	await physics_frame
	return is_instance_valid(globe)

func _teardown() -> void:
	if globe and is_instance_valid(globe):
		globe.queue_free()
		await process_frame
	globe = null
