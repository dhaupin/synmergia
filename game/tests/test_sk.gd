extends SceneTree
func _init() -> void:
	var s = load("res://core/schemas/skill.gd")
	print("OK", s != null)
	quit(0)
