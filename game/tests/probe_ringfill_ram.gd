## One-shot: fill the ring with stashes only (no reload), measure held cost.
extends SceneTree
const S := "res://scenes/worlds/globe_world.tscn"
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	ProjectSettings.set_setting("synmergia/world/planet_radius", 20000.0)
	var globe = load(S).instantiate()
	root.add_child(globe)
	await process_frame
	var st = globe.get("streamer")
	var base := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	print("BASE=%.0f MB ring=%d" % [base, st._mesh_cache_order.size()])
	for face in [1, 5, 9, 13, 17, 2, 6, 10, 14, 18]:
		if st._patches.has(face):
			st._unload_patch(face)
		print("  stashed face %d: ring=%d m=%.1f MB" % [face, st._mesh_cache_order.size(), Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0 - base])
	var held := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0 - base
	print("HELD_TOTAL=%.1f MB over ring=%d -> %.1f MB/entry" % [held, st._mesh_cache_order.size(), held / maxf(st._mesh_cache_order.size(), 1)])
	quit(0)
