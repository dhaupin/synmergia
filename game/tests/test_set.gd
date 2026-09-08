extends SceneTree
func _init() -> void:
	print("infer_variant=", ProjectSettings.get("gdscript/warnings/infer_variant"))
	print("untyped=", ProjectSettings.get("gdscript/warnings/untyped_assignment"))
	quit(0)
