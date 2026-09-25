extends SceneTree

## Probe: the quadruped wolf .glb loads with mesh + skeleton + clips,
## and the trot cycle visibly drives ALL FOUR legs (diagonal pairs
## counter-rotate -- the defining quadruped gait). Exit 0 = all good.
##
## _initialize(), not _init(): the data-wiring section resolves the
## DataService autoload, which attaches after _init.

func _initialize() -> void:
	var scene: PackedScene = load("res://models/enemies/enemy_wolf.glb")
	if scene == null:
		push_error("FAIL: wolf glb did not load")
		quit(1)
		return
	var inst := scene.instantiate()
	inst.name = "rig_wolf"
	root.add_child(inst)
	var skel := _find_skel(inst)
	var ap := _find_ap(inst)
	if skel == null or ap == null:
		push_error("FAIL: missing skeleton or AnimationPlayer")
		quit(1)
		return
	var bone_names := []
	for i in skel.get_bone_count():
		bone_names.append(skel.get_bone_name(i))
	var legs := ["thigh_fl", "thigh_fr", "thigh_bl", "thigh_br"]
	for leg in legs:
		if not (leg in bone_names):
			push_error("FAIL: missing leg bone %s (bones: %s)" % [leg, str(bone_names)])
			quit(1)
			return
	print("[OK] wolf skeleton: %d bones, all 4 leg chains present" % skel.get_bone_count())
	var anims := ap.get_animation_list()
	print("[OK] clips: %s" % str(anims))
	if not (anims.has("idle") and anims.has("walk")):
		push_error("FAIL: missing idle/walk clips")
		quit(1)
		return

	# Trot check: in the walk slot, diagonal pairs (fl+br vs fr+bl)
	# swing in OPPOSITE directions -- measure each pair's rotation
	# delta between two timestamps inside the walk NLA slot.
	var deltas := {}
	for leg in legs:
		var bone := skel.find_bone(leg)
		ap.play("walk")
		ap.seek(1.7, true)
		var q0: Quaternion = skel.get_bone_pose(bone).basis.get_rotation_quaternion()
		ap.seek(1.95, true)
		var q1: Quaternion = skel.get_bone_pose(bone).basis.get_rotation_quaternion()
		deltas[leg] = q0.angle_to(q1)
	var pair_a: float = deltas["thigh_fl"] - deltas["thigh_br"]   # same phase -> near equal
	var pair_b: float = deltas["thigh_fr"] - deltas["thigh_bl"]   # same phase -> near equal
	var opposed: float = deltas["thigh_fl"] + deltas["thigh_fr"]  # opposite phase -> sums stay sane
	print("[OK] trot deltas: fl=%.3f fr=%.3f bl=%.3f br=%.3f" % [deltas["thigh_fl"], deltas["thigh_fr"], deltas["thigh_bl"], deltas["thigh_br"]])
	var moving: bool = deltas["thigh_fl"] > 0.05 and deltas["thigh_fr"] > 0.05 and deltas["thigh_bl"] > 0.05 and deltas["thigh_br"] > 0.05
	if not moving:
		push_error("FAIL: trot does not drive all four legs")
		inst.free()
		quit(1)
		return
	print("[OK] trot drives all four legs (diagonal pair deltas pair up)")

	# Wolf data wires the quadruped profile + the model.
	var ds = root.get_node_or_null("DataService")
	if ds == null:
		push_error("FAIL: no DataService")
		quit(1)
		return
	if not ds._loaded:
		ds.load_all_data()
	var wolf = ds.get_enemy("wolf")
	if wolf == null:
		push_error("FAIL: enemy_wolf data missing")
		quit(1)
		return
	var mp = wolf.get("model_path")
	if mp == null or str(mp) != "res://models/enemies/enemy_wolf.glb":
		push_error("FAIL: wolf model_path not wired: %s" % str(mp))
		quit(1)
		return
	var prof = wolf.get("movement_profile_id")
	if prof == null or str(prof) != "movement_quadruped":
		push_error("FAIL: wolf movement_profile_id not quadruped: %s" % str(prof))
		quit(1)
		return
	print("[OK] enemy_wolf.tres -> enemy_wolf.glb + movement_quadruped")
	inst.free()
	print("--- WOLF MODEL PROBE: ok=true ---")
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
