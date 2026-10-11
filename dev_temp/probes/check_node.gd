extends SceneTree
func _init() -> void:
	var scene: PackedScene = load("res://scenes/npcs/blacksmith_village.tscn")
	var inst := scene.instantiate()
	print("ModelRoot exists: ", inst.get_node_or_null("ModelRoot") != null)
	print("ModelRoot/model exists: ", inst.get_node_or_null("ModelRoot/model") != null)
	var model := inst.get_node_or_null("ModelRoot/model")
	if model:
		print("model children: ", model.get_children().map(func(c): return c.name))
		print("model AP: ", model.get_node_or_null("AnimationPlayer") != null)
	inst.free()
	quit(0)
