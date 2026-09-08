extends SceneTree
func _init() -> void:
	var s = load("res://core/services/spawn_service.gd")
	print("OK", s != null)
	quit(0)
