extends SceneTree

## Probe: verify the blacksmith .glb animations actually DRIVE the
## skeleton. Samples thigh_l rotation at two timestamps in each clip.
## Exit 0 = walk visibly moves the bone (delta > 0.1 rad).
##
## NOTE: the glb's AnimationPlayer uses an ABSOLUTE track root
## ("/rig_blacksmith/Skeleton3D"), so the scene must be inside the tree
## under the matching node name before play/seek resolves anything.

func _init() -> void:
	var scene: PackedScene = load("res://models/npcs/npc_blacksmith_village.glb")
	if scene == null:
		push_error("FAIL: glb did not load")
		quit(1)
		return
	var inst := scene.instantiate()
	inst.name = "rig_blacksmith"
	root.add_child(inst)
	var skel := _find_skel(inst)
	var ap := _find_ap(inst)
	if skel == null or ap == null:
		push_error("FAIL: missing skeleton or AnimationPlayer")
		quit(1)
		return
	print("[OK] ap.root_node = %s" % str(ap.root_node))
	var bone := skel.find_bone("thigh_l")
	print("[OK] thigh_l bone idx: %d of %d" % [bone, skel.get_bone_count()])

	# The fix_clip_ranges post-processor places clips in NLA slots:
	# idle [0, 1.6]s, walk [1.6, 2.667]s. Sample inside the walk slot.
	var walk_delta := _sample_delta(ap, skel, bone, "walk", 1.7, 2.1)
	print("[OK] walk thigh_l delta in-slot: %.3f rad" % walk_delta)
	var idle_delta := _sample_delta(ap, skel, bone, "idle", 0.0, 0.8)
	print("[OK] idle thigh_l delta @0.8s: %.4f rad (near-static expected)" % idle_delta)

	var ok := walk_delta > 0.1
	if not ok:
		push_error("FAIL: walk clip does not move thigh_l (delta %.4f)" % walk_delta)
	print("--- BLACKSMITH ANIM PLAY PROBE: ok=%s ---" % str(ok))
	inst.free()
	quit(0 if ok else 1)

func _sample_delta(ap: AnimationPlayer, skel: Skeleton3D, bone: int, clip: String, t0: float, t1: float) -> float:
	ap.play(clip)
	ap.seek(t0, true)
	var p0: Transform3D = skel.get_bone_pose(bone)
	ap.seek(t1, true)
	var p1: Transform3D = skel.get_bone_pose(bone)
	# glTF axis conversion maps bone-local X rotations onto other quat
	# components -- measure the FULL quaternion angle, not one axis.
	return p0.basis.get_rotation_quaternion().angle_to(p1.basis.get_rotation_quaternion())

func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var s := _find_skel(c)
		if s != null:
			return s
	return null

func _find_ap(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var a := _find_ap(c)
		if a != null:
			return a
	return null
