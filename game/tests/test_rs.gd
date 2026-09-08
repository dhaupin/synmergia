extends SceneTree
func _init() -> void:
	var s = load("res://core/services/respawn_service.gd")
	print("respawn_service:", s != null)
	quit(0)
