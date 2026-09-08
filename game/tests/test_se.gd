extends SceneTree
func _init() -> void:
	const Entity = preload("res://core/entities/entity.gd")
	var s = load("res://core/entities/status_effect.gd")
	print("OK", s != null)
	quit(0)
