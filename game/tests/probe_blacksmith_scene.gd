extends SceneTree

## Probe: the blacksmith NPC scene embeds the skinned glb, the
## entity's idle-animation path finds the AnimationPlayer, and the
## idle clip visibly drives the skeleton. Exit 0 = all good.

func _initialize() -> void:
	var ok := true
	var ds = root.get_node_or_null("DataService")
	if ds == null:
		push_error("FAIL: no DataService")
		quit(1)
		return
	if not ds._loaded:
		ds.load_all_data()
	var npc_data = load("res://data/npc/npc_blacksmith_village.tres")
	if npc_data == null:
		push_error("FAIL: blacksmith NPCData did not load")
		quit(1)
		return
	var scene: PackedScene = load("res://scenes/npcs/blacksmith_village.tscn")
	if scene == null:
		push_error("FAIL: npc scene did not load")
		quit(1)
		return
	var inst = scene.instantiate()
	inst.npc_data = npc_data
	root.add_child(inst)
	await process_frame
	var model_root := inst.get_node_or_null("ModelRoot") as Node3D
	if model_root == null:
		push_error("FAIL: no mounted ModelRoot")
		quit(1)
		return
	var ap := _find_ap(model_root)
	if ap == null:
		push_error("FAIL: no AnimationPlayer under ModelRoot")
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

func _find_ap(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var found := _find_ap(c)
		if found != null:
			return found
	return null

func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var s := _find_skel(c)
		if s != null:
			return s
	return null
