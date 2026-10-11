extends SceneTree
func _init() -> void:
	var scene: PackedScene = load("res://scenes/npcs/blacksmith_village.tscn")
	var inst := scene.instantiate()
	root.add_child(inst)
	await process_frame
	var ap := inst.get_node_or_null("ModelRoot/model/AnimationPlayer") as AnimationPlayer
	print("AP: ", ap)
	if ap:
		print("anims: ", ap.get_animation_list())
		print("root_node: ", ap.root_node)
		ap.root_node = ap.get_parent().get_path()
		print("root_node now: ", ap.root_node)
		ap.play("idle")
		await process_frame
		print("playing: ", ap.is_playing(), " current: ", ap.current_animation)
		var skel := ap.get_node(ap.root_node).get_node_or_null("Skeleton3D")
		print("skel via root: ", skel)
	inst.free()
	quit(0)
