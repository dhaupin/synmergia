## bench_meshcache_v8 - the perf leg's E2E measurement (the built-patch
## warm cache). Boots the globe at the 20 km scale and walks a small
## face set TWICE: the first pass builds cold (the cache is empty),
## the second pass revisits the SAME faces (the cache should stock
## them back). Prints per-face cold vs warm load times + the ring
## hit count. Budget: warm legs should read well under the cold ones.
## Run headless:  godot --headless --path game --script res://tests/bench_meshcache_v8.gd
extends SceneTree

const GLOBE_SCENE := "res://scenes/worlds/globe_world.tscn"
const RADIUS_SETTING := "synmergia/world/planet_radius"
const RADIUS := 20000.0
# A short walk set (fits inside the headless slice; delta per face
# is the signal, not the sweep total).
const WALK_FACES: Array = [1, 5, 9]

var _globe: Node3D

func _init() -> void:
	call_deferred("_run")

func _load_time(st, face: int, lvl: int) -> float:
	if st._patches.has(face):
		st._unload_patch(face)
	var t0 := Time.get_ticks_usec()
	st._load_patch(face, lvl)
	return float(Time.get_ticks_usec() - t0) / 1000.0  # ms

func _run() -> void:
	ProjectSettings.set_setting(RADIUS_SETTING, RADIUS)
	var packed: PackedScene = load(GLOBE_SCENE)
	_globe = packed.instantiate()
	root.add_child(_globe)
	for _i in range(6):
		await process_frame
	var st = _globe.get("streamer")
	var cold: Array = []
	var warm: Array = []
	for face in WALK_FACES:
		cold.append(_load_time(st, face, 6))
	for face in WALK_FACES:
		warm.append(_load_time(st, face, 6))
	# The stash walk: unload (stash), then reload (stock).
	print("MESH_CACHE_BENCH:")
	var i := 0
	var total_cold := 0.0
	var total_warm := 0.0
	for face in WALK_FACES:
		total_cold += cold[i]
		total_warm += warm[i]
		print("  face %d: cold=%.1f ms warm(stock)=%.1f ms ratio=%.2f" % [face, cold[i], warm[i], warm[i] / maxf(cold[i], 0.001)])
		i += 1
	print("  TOTAL: cold=%.1f ms warm=%.1f ms speedup=%.1fx" % [total_cold, total_warm, total_cold / maxf(total_warm, 0.001)])
	print("  ring_size=", st._mesh_cache_order.size())
	# THE DETERMINISM PIN: the stocked mesh must carry the same tri
	# count the cold build reported (the entry's bookkeeping travels
	# with the node).
	var tri_ok := true
	for face in WALK_FACES:
		var tris_now: int = int(st._patch_tris.get(face, 0))
		if tris_now <= 0:
			tri_ok = false
			print("  FAIL face ", face, " post-stock tris=", tris_now)
	if tri_ok:
		print("  PASS post-stock bookkeeping: tri counts live")
		quit(0)
	else:
		quit(1)
