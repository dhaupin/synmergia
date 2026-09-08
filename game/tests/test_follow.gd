extends SceneTree
func _init() -> void:
	var s = load("res://core/services/follow_service.gd")
	print("follow_service:", s)
	quit(0)
