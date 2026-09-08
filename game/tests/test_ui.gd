extends SceneTree
func _init() -> void:
	var s = load("res://ui/components/skill_academy_ui.gd")
	print("OK", s != null)
	quit(0)
