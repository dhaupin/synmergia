extends SceneTree

func _init() -> void:
	var scene: PackedScene = load("res://models/npcs/npc_blacksmith_village.glb")
	var inst := scene.instantiate()
	root.add_child(inst)
	var skel: Skeleton3D = _find_skel(inst)
	var ap: AnimationPlayer = _find_ap(inst)
	if skel == null or ap == null:
		print("FAIL: missing skel/ap")
		quit(1)
		return
	var bone: int = skel.find_bone("thigh_l")
	print("thigh_l bone idx: ", bone, " of ", skel.get_bone_count())
	var rest: Transform3D = skel.get_bone_pose(bone)
	# play walk and sample mid-cycle
	ap.play("walk")
	ap.seek(0.0, true)
	var p0: Transform3D = skel.get_bone_pose(bone)
	ap.seek(0.33, true)
	var p1: Transform3D = skel.get_bone_pose(bone)
	var angle_diff: float = p0.basis.get_euler().angle_to(p1.basis.get_euler())
	print("walk rot delta @0.33s: %.3f rad" % angle_diff)
	# idle: barely moves
	ap.play("idle")
	ap.seek(0.0, true)
	var i0: Transform3D = skel.get_bone_pose(bone)
	ap.seek(0.8, true)
	var i1: Transform3D = skel.get_bone_pose(bone)
	print("idle rot delta @0.8s: %.3f rad" % i0.basis.get_euler().angle_to(i1.basis.get_euler().angle_to(p0.basis.get_euler()) * 0.0 + i0.basis.get_euler().angle_to(i1.basis.get_euler())))
	print("ANIM_PLAY_OK walk=%s" % ("yes" if angle_diff > 0.1 else "NO"))
	inst.free()
	quit(0)

func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var s := _find_skel(c)
		if s:
			return s
	return null

func _find_ap(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var a := _find_ap(c)
		if a:
			return a
	return null
