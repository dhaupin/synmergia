extends SceneTree
func _init() -> void:
	# Wait a frame so autoloads finish _ready
	await process_frame
	var rs = get_root().get_node_or_null("RespawnService")
	print("RespawnService node:", rs)
	if rs:
		print("  has respawn_completed:", rs.has_signal("respawn_completed"))
	quit(0)
