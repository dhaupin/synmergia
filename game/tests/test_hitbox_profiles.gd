extends SceneTree

## Hitbox Profile System smoke test: profiles load from
## data/hitbox_profiles/, dims resolve with scale clamping, the species
## fairness rule holds (every playable species resolves to the same
## player profile, overrides are forced back), and the entity wiring
## applies real shapes (enemy from EnemyData, player stance swap).
## Run: godot --headless --path . --script res://tests/test_hitbox_profiles.gd
##
## NOTE: _initialize(), not _init() -- autoloads attach after _init.

var _ds = null


func _initialize() -> void:
	var ok := true

	_ds = root.get_node_or_null("DataService")
	if _ds == null:
		push_error("FAIL: DataService autoload not present")
		quit(1)
		return
	if not _ds._loaded:
		_ds.load_all_data()

	ok = _test_profiles_load() and ok
	ok = _test_dims_and_stances() and ok
	ok = _test_scale_clamp() and ok
	ok = _test_species_fairness() and ok
	ok = _test_creature_resolution() and ok
	ok = (await _test_enemy_wiring()) and ok
	ok = (await _test_player_wiring()) and ok

	print("--- HITBOX PROFILES: ok=%s ---" % str(ok))
	quit(0 if ok else 1)


func _test_profiles_load() -> bool:
	var profiles: Dictionary = _ds.get_hitbox_profiles()
	if profiles.size() < 6:
		push_error("FAIL: expected >=6 hitbox profiles, got %d" % profiles.size())
		return false
	print("[OK] %d hitbox profiles loaded" % profiles.size())
	for required in ["hitbox_player", "hitbox_humanoid", "hitbox_beast_medium", "hitbox_blob", "hitbox_dummy", "hitbox_npc"]:
		if not profiles.has(required):
			push_error("FAIL: missing profile %s" % required)
			return false
	var player: HitboxProfile = _ds.get_hitbox_profile("hitbox_player")
	if not player.pvp_fair:
		push_error("FAIL: hitbox_player must be pvp_fair")
		return false
	if not is_equal_approx(player.min_scale, 1.0) or not is_equal_approx(player.max_scale, 1.0):
		push_error("FAIL: hitbox_player scale must be locked to 1.0")
		return false
	print("[OK] hitbox_player is pvp_fair with scale locked to 1.0")
	return true


func _test_dims_and_stances() -> bool:
	var player: HitboxProfile = _ds.get_hitbox_profile("hitbox_player")
	var stand: Dictionary = player.get_dims(1.0, "standing")
	var crouch: Dictionary = player.get_dims(1.0, "crouch")
	if not is_equal_approx(float(stand["height"]), 1.8):
		push_error("FAIL: standing height %s != 1.8" % stand["height"])
		return false
	if not is_equal_approx(float(crouch["height"]), 0.9):
		push_error("FAIL: crouch height %s != 0.9" % crouch["height"])
		return false
	if not is_equal_approx(float(crouch["offset"]), 0.45):
		push_error("FAIL: crouch offset %s != 0.45" % crouch["offset"])
		return false
	var shape := player.build_shape(1.0, "crouch") as CapsuleShape3D
	if shape == null or not is_equal_approx(shape.height, 0.9):
		push_error("FAIL: crouch shape not a 0.9 capsule")
		return false
	# Profile without a crouch variant falls back to standing dims.
	var wolf: HitboxProfile = _ds.get_hitbox_profile("hitbox_beast_medium")
	var wolf_crouch: Dictionary = wolf.get_dims(1.0, "crouch")
	if not is_equal_approx(float(wolf_crouch["height"]), float(wolf.get_dims(1.0)["height"])):
		push_error("FAIL: beast crouch should fall back to standing")
		return false
	print("[OK] stance dims resolve (1.8 stand / 0.9 crouch) and build real shapes")
	return true


func _test_scale_clamp() -> bool:
	var wolf: HitboxProfile = _ds.get_hitbox_profile("hitbox_beast_medium")
	# Wolf data scale 1.2 multiplies the box plan.
	var scaled: Dictionary = wolf.get_dims(1.2)
	if not is_equal_approx((scaled["size"] as Vector3).z, 1.92):
		push_error("FAIL: wolf scaled z %s != 1.92" % (scaled["size"] as Vector3).z)
		return false
	# A data typo (scale 50) clamps into the safe band.
	if not is_equal_approx(wolf.clamp_scale(50.0), wolf.max_scale):
		push_error("FAIL: scale 50 not clamped to %.1f" % wolf.max_scale)
		return false
	var tiny: Dictionary = wolf.get_dims(0.01)
	if not is_equal_approx((tiny["size"] as Vector3).z, 1.6 * wolf.min_scale):
		push_error("FAIL: tiny scale not clamped up to min")
		return false
	print("[OK] scale multiplies dims and clamps into [%.2f, %.1f]" % [wolf.min_scale, wolf.max_scale])
	return true


func _test_species_fairness() -> bool:
	# Every playable species resolves to the SAME profile.
	var seen := {}
	for sid in ["human", "akkan", "synthetic"]:
		var prof: HitboxProfile = _ds.resolve_player_hitbox_profile(sid)
		if prof == null:
			push_error("FAIL: no hitbox profile resolved for species %s" % sid)
			return false
		seen[prof.id] = true
	if seen.size() != 1:
		push_error("FAIL: species resolved to different hitboxes: %s" % str(seen.keys()))
		return false
	var shared: String = seen.keys()[0]
	if shared != "hitbox_player":
		push_error("FAIL: species share '%s' instead of hitbox_player" % shared)
		return false
	print("[OK] human/akkan/synthetic all resolve to '%s'" % shared)
	# A deviating species override is forced back to the shared profile.
	var fair_ids := {"__profile_id": "hitbox_player"}
	var forced: HitboxProfile = _ds.resolve_player_hitbox_profile("akkan", fair_ids)
	if forced == null or forced.id != "hitbox_player":
		push_error("FAIL: deviating species override not forced back to shared profile")
		return false
	print("[OK] deviating species override is forced back to the shared profile")
	return true


func _test_creature_resolution() -> bool:
	var wolf_data = _ds.get_enemy("wolf")
	if wolf_data == null:
		push_error("FAIL: wolf enemy data missing")
		return false
	var wolf_prof: HitboxProfile = _ds.get_creature_hitbox_profile(wolf_data)
	if wolf_prof == null or wolf_prof.id != "hitbox_beast_medium":
		push_error("FAIL: wolf resolved to %s" % (wolf_prof.id if wolf_prof != null else "<null>"))
		return false
	var slime_prof: HitboxProfile = _ds.get_creature_hitbox_profile(_ds.get_enemy("slime"))
	if slime_prof == null or slime_prof.id != "hitbox_blob":
		push_error("FAIL: slime resolved to %s" % (slime_prof.id if slime_prof != null else "<null>"))
		return false
	var bandit_prof: HitboxProfile = _ds.get_creature_hitbox_profile(_ds.get_enemy("bandit"))
	if bandit_prof == null or bandit_prof.id != "hitbox_humanoid":
		push_error("FAIL: bandit resolved to %s" % (bandit_prof.id if bandit_prof != null else "<null>"))
		return false
	print("[OK] creature resolution: wolf->beast, slime->blob, bandit->humanoid")
	return true


func _test_enemy_wiring() -> bool:
	# Instance the playable world: enemy _ready must apply profile shapes
	# onto the scene's Hitbox nodes (world_playable enemies are Node3D
	# Enemy scripts, not physics bodies, so assert the shape properties).
	var scene: PackedScene = load("res://scenes/world_playable.tscn")
	if scene == null:
		push_error("FAIL: world_playable.tscn did not load")
		return false
	var inst := scene.instantiate()
	root.add_child(inst)
	await process_frame

	var checks := [
		{"node": "Wolf", "profile": "hitbox_beast_medium", "kind": HitboxProfile.ShapeKind.BOX},
		{"node": "SlimeA", "profile": "hitbox_blob", "kind": HitboxProfile.ShapeKind.SPHERE},
		{"node": "Bandit", "profile": "hitbox_humanoid", "kind": HitboxProfile.ShapeKind.CAPSULE},
	]
	for c in checks:
		var enemy := inst.get_node_or_null(c["node"])
		if enemy == null:
			push_error("FAIL: %s missing from world" % c["node"])
			inst.free()
			return false
		var shape_node := enemy.get_node_or_null("StaticBody3D/Hitbox") as CollisionShape3D
		if shape_node == null or shape_node.shape == null:
			push_error("FAIL: %s has no applied hitbox shape" % c["node"])
			inst.free()
			return false
		if c["kind"] == HitboxProfile.ShapeKind.BOX and not (shape_node.shape is BoxShape3D):
			push_error("FAIL: %s shape is not a BoxShape3D" % c["node"])
			inst.free()
			return false
		if c["kind"] == HitboxProfile.ShapeKind.SPHERE and not (shape_node.shape is SphereShape3D):
			push_error("FAIL: %s shape is not a SphereShape3D" % c["node"])
			inst.free()
			return false
		if c["kind"] == HitboxProfile.ShapeKind.CAPSULE and not (shape_node.shape is CapsuleShape3D):
			push_error("FAIL: %s shape is not a CapsuleShape3D" % c["node"])
			inst.free()
			return false
		# Wolf data scale 1.2 must multiply BOTH the hitbox and the model.
		if c["node"] == "Wolf":
			var box := shape_node.shape as BoxShape3D
			if not is_equal_approx(box.size.z, 1.92):
				push_error("FAIL: wolf hitbox z %s != 1.92 (scale 1.2 applied)" % box.size.z)
				inst.free()
				return false
			var model_root := enemy.get_node_or_null("ModelRoot") as Node3D
			if model_root == null or not is_equal_approx(model_root.scale.x, 1.2):
				push_error("FAIL: wolf ModelRoot scale not 1.2")
				inst.free()
				return false
	if is_instance_valid(inst):
		inst.free()
	print("[OK] world enemies carry profile shapes (box/sphere/capsule) + scaled wolf model")
	return true


func _test_player_wiring() -> bool:
	# PlayerController stance swap via the scene-authored player (the
	# playable world's Player node -- avoids bare-.new() boot-error spam
	# from a controller instantiated outside the scene's full wiring).
	var scene: PackedScene = load("res://scenes/world_playable.tscn")
	if scene == null:
		push_error("FAIL: world_playable.tscn did not load")
		return false
	var inst := scene.instantiate()
	root.add_child(inst)
	await process_frame
	await process_frame
	var pc := inst.get_node_or_null("Player")
	if pc == null:
		push_error("FAIL: Player node missing from world")
		inst.free()
		return false
	var shape_node := pc.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null or shape_node.shape == null:
		push_error("FAIL: player hitbox not applied in _ready")
		inst.free()
		return false
	var standing_h: float = (shape_node.shape as CapsuleShape3D).height
	pc.set_hitbox_stance("crouch")
	var crouch_h: float = (shape_node.shape as CapsuleShape3D).height
	if not (crouch_h < standing_h):
		push_error("FAIL: crouch capsule %s not smaller than standing %s" % [crouch_h, standing_h])
		inst.free()
		return false
	var off := shape_node.position.y
	if not is_equal_approx(off, 0.45):
		push_error("FAIL: crouch offset %s != 0.45" % off)
		inst.free()
		return false
	pc.set_hitbox_stance("standing")
	var restored_h: float = (shape_node.shape as CapsuleShape3D).height
	if not is_equal_approx(restored_h, standing_h):
		push_error("FAIL: standing capsule not restored")
		inst.free()
		return false
	# Invalid stances are ignored.
	pc.set_hitbox_stance("flying")
	var after_invalid: float = (shape_node.shape as CapsuleShape3D).height
	if not is_equal_approx(after_invalid, standing_h):
		push_error("FAIL: invalid stance changed the capsule")
		inst.free()
		return false
	inst.free()
	print("[OK] player hitbox: species-fair capsule applies, crouch swaps, standing restores")
	return true
