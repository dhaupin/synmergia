extends SceneTree
func _init() -> void:
	var s = load("res://core/entities/entity.gd")
	print("entity:", s != null)
	quit(0)
