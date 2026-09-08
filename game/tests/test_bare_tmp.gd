extends SceneTree

func _init() -> void:
	print("has GameLog:", has_node("/root/GameLog"))
	if has_node("/root/GameLog"):
		var n = get_node("/root/GameLog")
		print("type:", n.get_class())
	quit(0)
