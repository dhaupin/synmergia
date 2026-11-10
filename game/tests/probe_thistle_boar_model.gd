extends SceneTree

## Probe: the thistle boar .glb loads with a real mesh + material, a
## quadruped skeleton (spine chain + 4 leg chains), and idle + walk
## clips; the trot cycle visibly drives all four legs; the enemy data
## wires the model. Exit 0 = all good.
##
## _initialize(), not _init(): the data-wiring section resolves the
## DataService autoload, which attaches after _init.

func _initialize() -> void:
	var scene: PackedScene = load("res://models/enemies/enemy_thistle_boar.glb")
	if scene == null:
		push_error("FAIL: thistle boar glb did not load")
		quit(1)
		return
	var inst := scene.instantiate()
	inst.name = "rig_thistle_boar"
	root.add_child(inst)
	var skel := _find_skel(inst)
	var ap := _find_ap(inst)
	if skel == null or ap == null:
		push_error("FAIL: missing skeleton or AnimationPlayer")
		quit(1)
		return

	# Real geometry: a MeshInstance3D with surface(s) and a material.
	var mesh_inst := _find_mesh(inst)
	if mesh_inst == null or mesh_inst.mesh == null:
		push_error("FAIL: no MeshInstance3D with a mesh")
		quit(1)
		return
	if mesh_inst.mesh.get_surface_count() < 1:
		push_error("FAIL: mesh has no surfaces")
		quit(1)
		return
	if mesh_inst.mesh.surface_get_material(0) == null:
		push_error("FAIL: mesh surface has no material")
		quit(1)
		return
	print("[OK] mesh: %d surface(s), material=%s" % [
		mesh_inst.mesh.get_surface_count(),
		mesh_inst.mesh.surface_get_material(0).resource_name])

	# Quadruped skeleton: spine chain + all four leg chains.
	var bone_names := []
	for i in skel.get_bone_count():
		bone_names.append(skel.get_bone_name(i))
	for b in ["root", "spine", "chest", "neck", "head",
			"thigh_fl", "thigh_fr", "thigh_bl", "thigh_br"]:
		if not (b in bone_names):
			push_error("FAIL: missing bone %s (bones: %s)" % [b, str(bone_names)])
			quit(1)
			return
	print("[OK] boar skeleton: %d bones (spine chain + 4 leg chains present)" % skel.get_bone_count())

	var anims := ap.get_animation_list()
	print("[OK] clips: %s" % str(anims))
	if not (anims.has("idle") and anims.has("walk")):
		push_error("FAIL: missing idle/walk clips")
		quit(1)
		return

	# Trot check: in the walk slot the four leg bones rotate (the trot
	# drives every leg).
	var legs := ["thigh_fl", "thigh_fr", "thigh_bl", "thigh_br"]
	var deltas := {}
	for leg in legs:
		var bone := skel.find_bone(leg)
		ap.play("walk")
		ap.seek(1.7, true)
		var q0: Quaternion = skel.get_bone_pose(bone).basis.get_rotation_quaternion()
		ap.seek(1.95, true)
		var q1: Quaternion = skel.get_bone_pose(bone).basis.get_rotation_quaternion()
		deltas[leg] = q0.angle_to(q1)
	print("[OK] trot deltas: fl=%.3f fr=%.3f bl=%.3f br=%.3f" % [
		deltas["thigh_fl"], deltas["thigh_fr"], deltas["thigh_bl"], deltas["thigh_br"]])
	var moving: bool = deltas["thigh_fl"] > 0.05 and deltas["thigh_fr"] > 0.05 \
		and deltas["thigh_bl"] > 0.05 and deltas["thigh_br"] > 0.05
	if not moving:
		push_error("FAIL: trot does not drive all four legs")
		inst.free()
		quit(1)
		return
	print("[OK] trot drives all four legs")

	# Boar data wires the model.
	var ds = root.get_node_or_null("DataService")
	if ds == null:
		push_error("FAIL: no DataService")
		quit(1)
		return
	if not ds._loaded:
		ds.load_all_data()
	var boar = ds.get_enemy("thistle_boar")
	if boar == null:
		push_error("FAIL: enemy_thistle_boar data missing")
		quit(1)
		return
	var mp = boar.get("model_path")
	if mp == null or str(mp) != "res://models/enemies/enemy_thistle_boar.glb":
		push_error("FAIL: thistle boar model_path not wired: %s" % str(mp))
		quit(1)
		return
	print("[OK] enemy_thistle_boar.tres -> enemy_thistle_boar.glb")
	inst.free()
	print("--- THISTLE BOAR MODEL PROBE: ok=true ---")
	quit(0)

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

func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D and n.mesh != null:
		return n
	for c in n.get_children():
		var m := _find_mesh(c)
		if m != null:
			return m
	return null
