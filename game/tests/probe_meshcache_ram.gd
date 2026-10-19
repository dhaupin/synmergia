## probe_meshcache_ram - the ring's memory audit over a streaming walk.
## Boot the globe and walk a face set, stashing then RE-STOCKING each
## face (the honest ring path: build cold once, then unload/load
## through the ring) while reading the engine's allocated-memory
## monitor at each leg. Reports:
##   - ring occupancy trajectory
##   - engine memory delta per stock/hot-reload leg
##   - peak allocated memory across the walk (the bound's real price)
## Run headless:  godot --headless --path game --script res://tests/probe_meshcache_ram.gd
## (Level 6 builds cost ~9 s each cold; the set is bounded so the
## whole probe stays inside a headless slice. Deeper audits raise
## WALK_FACES deliberately.)
extends SceneTree

const GLOBE_SCENE := "res://scenes/worlds/globe_world.tscn"
const RADIUS_SETTING := "synmergia/world/planet_radius"
const RADIUS := 20000.0
const WALK_FACES: Array = [1, 5, 9]

func _mem_mb() -> float:
	return Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	ProjectSettings.set_setting(RADIUS_SETTING, RADIUS)
	var packed: PackedScene = load(GLOBE_SCENE)
	var globe = packed.instantiate()
	root.add_child(globe)
	for _i in range(6):
		await process_frame
	var st = globe.get("streamer")
	var baseline: float = _mem_mb()
	print("RAM_BASELINE=%.0f MB" % baseline)
	var peak: float = baseline
	for face in WALK_FACES:
		# Cold build once (the one the session always pays).
		if st._patches.has(face):
			st._unload_patch(face)
		st._load_patch(face, 6)
		await process_frame
		peak = maxf(peak, _mem_mb())
		# Now the RING legs: stash, then stock, then hot-reload.
		var pre: float = _mem_mb()
		st._unload_patch(face)  # stash into the ring
		var stashed_mb: float = _mem_mb() - pre
		var ring_after_stash: int = st._mesh_cache_order.size()
		st._load_patch(face, 6)  # stock back (warm)
		await process_frame
		var stocked_mb: float = _mem_mb() - pre
		peak = maxf(peak, _mem_mb())
		st._hot_reload(face, 6)  # the ping-pong leg (stash + fresh)
		await process_frame
		peak = maxf(peak, _mem_mb())
		print("  face %2d: stash=%+.1f MB (ring=%d) stock=%+.1f MB live=%d" % [
			face, stashed_mb, ring_after_stash, stocked_mb, st._patches.size()])
	var end_mb: float = _mem_mb()
	print("RAM_PEAK=%.0f MB  RAM_END=%.0f MB  WALK_DELTA=%+.1f MB" % [peak, end_mb, end_mb - baseline])
	print("RING_FINAL_SIZE=%d (bound 24)" % st._mesh_cache_order.size())
	# v9: quit with live worker lanes RACES the engine's script teardown
	# (the mid-flight calls log phantom SCRIPT ERRORs -- shutdown noise,
	# never an accounting error). The verdicts above are printed; this
	# is only the clean-exit drain so a battery run reads residue-free.
	var drain: int = 0
	while st.pending_derive() > 0 and drain < 1800:
		await root.get_tree().physics_frame
		drain += 1
	quit(0)
