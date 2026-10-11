extends SceneTree
func _init() -> void:
	var b := Button.new()
	print("has accessibility_name: ", "accessibility_name" in b)
	print("has accessibility_description: ", "accessibility_description" in b)
	if "accessibility_name" in b:
		b.accessibility_name = "Start Adventure"
		print("set/get ok: ", b.accessibility_name)
	root.add_child(b)
	print("in-tree read: ", b.accessibility_name)
	quit(0)
