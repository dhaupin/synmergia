## bench_coldboot_wall - the boot-wall A/B for the v9 mesh thread.
## ONE BOOT PER PROCESS (env-keyed): the terrain sector caches are
## process-static, so a second boot in the same process is WARM and
## not comparable. The shell runs both legs and reports the pair:
##   ASYNC_MESH=off bench_coldboot_wall.gd   -> SYNC_LAW leg (cold)
##   ASYNC_MESH=on  bench_coldboot_wall.gd   -> ASYNC_LAW leg (cold)
## Reports, per leg:
##   BOOT_WALL_MS   - the main-thread block between add_child and the
##     first process frame back (globe boot is synchronous inside).
##   STEADY_FRAMES/MS - the drain to pending_derive()==0 (both async
##     lanes); SYNC law = 0 derive jobs by construction.
##   FACES/TRIS     - the world census, constant across lanes (the
##     determinism tie: same bytes, different lane).
extends SceneTree

const GLOBE_SCENE := "res://scenes/worlds/globe_world.tscn"
const RADIUS_SETTING: String = "synmergia/world/planet_radius"
const ASYNC_SETTING: String = "synmergia/world/async_mesh"
const RADIUS := 20000.0
const DRAIN_CAP := 2400


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var leg: String = OS.get_environment("ASYNC_MESH")
	var lanes_on: bool = leg != "off"
	ProjectSettings.set_setting(RADIUS_SETTING, RADIUS)
	ProjectSettings.set_setting(ASYNC_SETTING, lanes_on)
	var t0: int = Time.get_ticks_msec()
	var packed: PackedScene = load(GLOBE_SCENE)
	var globe: Node3D = packed.instantiate()
	root.add_child(globe)
	await process_frame
	var wall: int = Time.get_ticks_msec() - t0
	var st = globe.get("streamer")
	var faces_boot: int = st.patch_count()
	var drained := 0
	var t1: int = Time.get_ticks_msec()
	while st.pending_derive() > 0 and drained < DRAIN_CAP:
		await root.get_tree().physics_frame
		drained += 1
	var steady_ms: int = Time.get_ticks_msec() - t1
	# One extra frame: the final deferral round (appliers) lands before
	# the teardown, so no cross-globe corpse work fires at exit.
	var faces_steady: int = st.patch_count()
	await process_frame
	# The A/B METRIC that isolates the mesh law: the streamer's own
	# wall time -- SYNC law = 4 cold builds inside update(); ASYNC law
	# = 1 cold build (the neighbors were on the workers). The boot's
	# ~60 s of fixed non-mesh cost (villages/HUD/GLBs and the 2-core
	# worker contention) lives OUTSIDE this number.
	print("LANE=%s BOOT_WALL_MS=%d STREAMER_MS=%d STEADY_FRAMES=%d STEADY_MS=%d FACES_BOOT=%d FACES_STEADY=%d TRIS=%d" \
		% ["ASYNC" if lanes_on else "SYNC", wall, st.last_update_ms, drained, steady_ms, faces_boot, faces_steady, st.triangle_count()])
	# THE >=4-CORE PROJECTION (a MODEL, explicitly not a measurement):
	# the sync law pays 4 serial cold builds; the lane law pays the
	# boot face synchronously and the 3 neighbors on the workers. On
	# this 2-core container the worker walls are contention-inflated
	# (~2x), so the projection is an UPPER bound on serial work. On a
	# C-core host the projected boot mesh wall is
	#   t_face + (sum of neighbor derives) / (C - 1)
	# with t_face proxied by the lane's largest single derive (same
	# content class as the boot face). The REAL number is one
	# ASYNC_MESH=on call on such hardware.
	if lanes_on:
		var ls: Dictionary = st.mesh_lane_stats()
		var t_face: float = float(ls.max_ms)
		var neighbor_ms: float = maxf(0.0, float(ls.ms) - t_face)
		var jobs: int = int(ls.jobs)
		if jobs > 0:
			for c in [4, 8]:
				var proj: float = t_face + neighbor_ms / float(maxi(c - 1, 1))
				print("PROJECTION C=%d BOOT_MESH_MS=%.0f (upper-bound model; worker walls on this host sum=%.0f ms over %d jobs, max=%.0f)" \
					% [c, proj, float(ls.ms), jobs, t_face])
	globe.queue_free()
	quit(0)
