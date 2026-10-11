extends SceneTree
func _init() -> void:
	var scene: PackedScene = load("res://scenes/npcs/blacksmith_village.tscn")
	var inst := scene.instantiate()
	root.add_child(inst)
	await process_frame
	print("AP direct: ", inst.get_node_or_null("ModelRoot/model/AnimationPlayer"))
	print("script: ", inst.get_script())
	inst.free()
	quit(0)
