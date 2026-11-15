extends SceneTree
func _init() -> void:
	call_deferred("_go")
func _go() -> void:
	await process_frame
	var reg = root.get_node_or_null("AdapterRegistry")
	if reg == null:
		print("NO REGISTRY")
		quit(0)
		return
	var store = reg.get_persistence("characters")
	print("STORE: ", store)
	if store != null and store.has_method("get_kv"):
		var v = store.get_kv("progress:char:player_1")
		print("player_1 progress: ", v)
	quit(0)
