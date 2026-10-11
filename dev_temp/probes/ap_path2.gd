extends SceneTree
func _init() -> void:
	var scene: PackedScene = load("res://scenes/npcs/blacksmith_village.tscn")
	var inst := scene.instantiate()
	root.add_child(inst)
	await process_frame
	var ap := inst.get_node_or_null("ModelRoot/model/AnimationPlayer") as AnimationPlayer
	ap.root_node = ap.get_parent().get_path()
	ap.play("idle")
	await process_frame
	await process_frame
	var model := ap.get_parent()
	var skel := model.get_node_or_null("rig_blacksmith/Skeleton3D") as Skeleton3D
	print("skel: ", skel)
	if skel:
		var bone := skel.find_bone("arm_r")
		var q0: Quaternion = skel.get_bone_pose(bone).basis.get_rotation_quaternion()
		await create_timer(0.5).timeout
		var q1: Quaternion = skel.get_bone_pose(bone).basis.get_rotation_quaternion()
		print("arm_r delta after 0.5s idle: ", q0.angle_to(q1))
	inst.free()
	quit(0)
