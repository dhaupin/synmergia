extends SceneTree
func _initialize() -> void:
	var vp := root.get_viewport() if root else null
	print("WINDOW_SIZE=", DisplayServer.window_get_size())
	print("VISIBLE_RECT=", (vp.get_visible_rect() if vp else Rect2()))
	print("CONTENT_SCALE=", (root.content_scale_factor if root else -1.0), " mode=", (root.content_scale_mode if root else -1))
	quit(0)
