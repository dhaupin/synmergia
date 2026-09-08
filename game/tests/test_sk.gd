extends SceneTree
func _init() -> void:
	var s = load("res://core/schemas/skill.gd")
	print("skill:", s != null)
	quit(0)
