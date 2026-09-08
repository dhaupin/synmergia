extends SceneTree
func _init() -> void:
	ProjectSettings.set("script/warnings/infer_variant", 0)
	ProjectSettings.set("script/warnings/untyped_assignment", 0)
	var s = load("res://core/services/combat_math.gd")
	print("OK", s != null)
	quit(0)
