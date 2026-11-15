extends SceneTree
func _init() -> void:
	var s = "hello"
	print("typeof=", typeof(s), " has_get_type=", s.has_method("get_type"))
	if s.has_method("get_type"):
		print("get_type=", s.get_type())
	quit(0)
