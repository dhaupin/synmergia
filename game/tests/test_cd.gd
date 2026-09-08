extends SceneTree
func _init() -> void:
	var s = load("res://core/services/cooldown_service.gd")
	print("cooldown:", s != null)
	quit(0)
