extends SceneTree
func _init() -> void:
	call_deferred("_go")
func _go() -> void:
	await process_frame
	var pp = root.get_node_or_null("PlayerProgress")
	if pp != null and pp._store != null:
		var keys = pp._store.get_keys("progress:char:") if pp._store.has_method("get_keys") else []
		print("KEYS: ", keys)
	quit(0)
