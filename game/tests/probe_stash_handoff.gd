## debug cache handoff: unload -> inspect ring -> load -> inspect source of node
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
	var face := 1
	# Load fresh at 6 (like the bench pass 1)
	st._load_patch(face, 6)
	print("after load: in_tree=", st._patches.has(face), " tris=", st._patch_tris.get(face, -1), " lvl=", st._patch_lvl.get(face, -1))
	# Unload (stash expected)
	st._unload_patch(face)
	print("after unload:_patches_has=", st._patches.has(face), " ring=", st._mesh_cache_order, " stash_tris=", st._mesh_cache.get("1@6", {}).get("patch_tris", -1) if st._mesh_cache.has("1@6") else -1)
	# Reload (stock expected)
	st._load_patch(face, 6)
	var mi = st._patches.get(face)
	print("after reload: tris=", st._patch_tris.get(face, -1), " mesh_nonnull=", mi != null and mi.mesh != null, " node_name=", mi.name if mi else "null")
	quit(0)
