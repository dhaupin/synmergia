extends SceneTree
func _init() -> void:
	var s = load("res://core/events/spawn_metadata.gd")
	print("OK", s != null)
	quit(0)
