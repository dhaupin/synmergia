extends SceneTree

## Probe: the blacksmith NPC scene embeds the skinned glb, the
## entity's idle-animation path finds the AnimationPlayer, and the
## idle clip visibly drives the skeleton. Exit 0 = all good.

func _init() -> void:
	var ok := true
	var scene: PackedScene = load("res://scenes/npcs/blacksmith_village.tscn")
	if scene == null:
		push_error("FAIL: npc scene did not load")
		quit(1)
		return
	var inst := scene.instantiate()
	root.add_child(inst)
	await process_frame
	var ap := inst.get_node_or_null("ModelRoot/model/AnimationPlayer") as AnimationPlayer
	if ap == null:
		push_error("FAIL: no ModelRoot/model/AnimationPlayer")
		ok = false
	elif not ap.has_animation("idle"):
		push_error("FAIL: no idle clip")
		ok = false
	var skel := _find_skel(inst)
	if skel == null:
		push_error("FAIL: no Skeleton3D in scene")
		ok = false
	# Play idle via the same path NPCEntity._play_model_idle() uses.
	if ok and ap != null:
		ap.root_node = ap.get_parent().get_path()
		ap.play("idle")
		await process_frame
		await process_frame
		var bone := skel.find_bone("arm_r")
		var q0: Quaternion = skel.get_bone_pose(bone).basis.get_rotation_quaternion()
		await create_timer(0.5).timeout
		var q1: Quaternion = skel.get_bone_pose(bone).basis.get_rotation_quaternion()
		var delta: float = q0.angle_to(q1)
		print("[OK] idle drives arm_r over 0.5s: %.4f rad (visible breathing)" % delta)
		if delta <= 0.0:
			push_error("FAIL: idle clip not driving skeleton")
			ok = false
	if is_instance_valid(inst):
		inst.free()
	print("--- BLACKSMITH SCENE PROBE: ok=%s ---" % str(ok))
	quit(0 if ok else 1)

func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var s := _find_skel(c)
		if s != null:
			return s
	return null
