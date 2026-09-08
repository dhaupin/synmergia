extends SceneTree
func _init() -> void:
	var s = load("res://core/autoload/player_manager.gd")
	print("OK", s != null)
	quit(0)
