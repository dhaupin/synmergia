extends SceneTree
func _init() -> void:
	const GameLog = preload("res://core/autoload/logger.gd")
	var s = load("res://core/services/cooldown_service.gd")
	print("cooldown:", s != null)
	quit(0)
