extends SceneTree
func _init() -> void:
	await process_frame
	var loader := CanvasLayer.new(); loader.name = "BootLoadingLayer"; root.add_child(loader)
	var hb := Button.new(); hb.text = "Invisible Action"; loader.add_child(hb)
	await process_frame; await process_frame
	print("loader.visible=", loader.visible, " hb in-tree visible=", hb.is_visible_in_tree(), " hb rect=", hb.get_global_rect(), " mf=", hb.mouse_filter)
	quit(0)
