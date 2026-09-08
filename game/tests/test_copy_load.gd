extends SceneTree
func _init() -> void:
	var s = preload("res://tests/test_copy.gd")
	print("loaded copy:", s)
	quit(0)
