extends SceneTree

## Movement Design System smoke test: profiles load from
## data/movement_profiles/, values resolve, and the archetypes differ in
## the ways gameplay depends on (ambient NPCs can't sprint; mechanical
## can't jump). Run: godot --headless --path . --script res://tests/test_movement_profiles.gd
##
## NOTE: use _initialize(), not _init() -- _init runs before autoloads
## are attached to root, so DataService would not be resolvable yet.

var _ds = null


func _initialize() -> void:
	var ok := true

	# Resolve autoload via root (script mode still loads autoloads; they
	# just are not attached during _init).
	_ds = root.get_node_or_null("DataService")
	if _ds == null:
		push_error("FAIL: DataService autoload not present")
		quit(1)
		return
	if not _ds._loaded:
		_ds.load_all_data()

	var profiles: Dictionary = _ds.get_movement_profiles()
	if profiles.size() < 6:
		push_error("FAIL: expected >=6 movement profiles, got %d" % profiles.size())
		ok = false
	else:
		print("[OK] %d movement profiles loaded" % profiles.size())

	var standard = _ds.get_movement_profile("movement_standard")
	var quadruped = _ds.get_movement_profile("movement_quadruped")
	var mechanical = _ds.get_movement_profile("movement_mechanical")
	var ambient = _ds.get_movement_profile("movement_npc_ambient")

	for p in [standard, quadruped, mechanical, ambient]:
		if p == null:
			push_error("FAIL: a canonical profile is missing")
			ok = false

	# New rideable classes resolve and gate like the originals.
	var aerial = _ds.get_movement_profile("movement_aerial")
	var aquatic = _ds.get_movement_profile("movement_aquatic")
	if aerial == null or aquatic == null:
		push_error("FAIL: aerial/aquatic profiles missing")
		ok = false
	else:
		if not (aerial.sprint_speed > standard.sprint_speed and aerial.allow_jump):
			push_error("FAIL: aerial profile should be fast and fly-capable")
			ok = false
		elif not (aquatic.swim_speed > standard.walk_speed and not aquatic.allow_jump):
			push_error("FAIL: aquatic profile should swim well and never jump")
			ok = false
		else:
			print("[OK] aerial (fast, jump-capable) + aquatic (swim, no jump) profiles sane")

	# Mount/vehicle resolution path: explicit override wins, kind
	# derives otherwise, vehicles fall to mechanical.
	var mount_data_script := load("res://core/schemas/mount_data.gd")
	var gullwing = mount_data_script.new()
	gullwing.id = "mount_test"
	gullwing.kind = 1  # FLYING
	var resolved = _ds.get_mount_movement_profile(gullwing)
	if resolved == null or resolved.id != "movement_aerial":
		push_error("FAIL: flying mount should resolve movement_aerial, got %s" % (resolved.id if resolved else "null"))
		ok = false
	else:
		print("[OK] flying mount kind-derives to movement_aerial")
	gullwing.movement_profile_id = "movement_npc_ambient"
	resolved = _ds.get_mount_movement_profile(gullwing)
	if resolved == null or resolved.id != "movement_npc_ambient":
		push_error("FAIL: explicit mount override lost")
		ok = false
	else:
		print("[OK] explicit mount profile override wins over kind")
	# gullwing is Resource (RefCounted): no manual free.
	var vehicle_resolved = _ds.get_mount_movement_profile({"movement_profile_id": ""})
	if vehicle_resolved == null or vehicle_resolved.id != "movement_mechanical":
		push_error("FAIL: vehicle fallback should be movement_mechanical")
		ok = false
	else:
		print("[OK] vehicle fallback resolves movement_mechanical")

	if ok:
		# 1. standard matches the historical hard-coded player defaults
		#    so this change cannot silently retune movement feel.
		if not is_equal_approx(standard.walk_speed, 5.0):
			push_error("FAIL: standard walk_speed %s != 5.0" % standard.walk_speed)
			ok = false
		if not is_equal_approx(standard.sprint_speed, 10.0):
			push_error("FAIL: standard sprint_speed %s != 10.0" % standard.sprint_speed)
			ok = false
		if not is_equal_approx(standard.jump_force, 10.0):
			push_error("FAIL: standard jump_force %s != 10.0" % standard.jump_force)
			ok = false
		if ok:
			print("[OK] standard profile preserves historical player tuning")

		# 2. quadruped is faster than standard (mounts should feel it)
		if not (quadruped.sprint_speed > standard.sprint_speed):
			push_error("FAIL: quadruped sprint %s should beat standard %s" % [quadruped.sprint_speed, standard.sprint_speed])
			ok = false
		else:
			print("[OK] quadruped outpaces standard (%.1f vs %.1f)" % [quadruped.sprint_speed, standard.sprint_speed])

		# 3. capability gates: ambient NPCs never sprint/jump; machines never jump
		if ambient.allow_sprint or ambient.allow_jump:
			push_error("FAIL: ambient NPC profile must disable sprint+jump")
			ok = false
		elif mechanical.allow_jump:
			push_error("FAIL: mechanical profile must disable jump")
			ok = false
		else:
			print("[OK] capability gates correct (ambient: no sprint/jump; mechanical: no jump)")

		# 4. speeds resolve through the stance helper
		var walk: float = standard.get_ground_speed("walk")
		var sprint: float = standard.get_ground_speed("sprint")
		if not (sprint > walk):
			push_error("FAIL: sprint %.1f should beat walk %.1f" % [sprint, walk])
			ok = false
		else:
			print("[OK] get_ground_speed() resolves walk=%.1f sprint=%.1f" % [walk, sprint])

		# 5. backward multipliers apply
		var back: float = standard.get_ground_speed("walk", true)
		if not back < walk:
			push_error("FAIL: backward walk %.1f should be slower than %.1f" % [back, walk])
			ok = false
		else:
			print("[OK] backward modifier applies (%.1f < %.1f)" % [back, walk])

	print("--- MOVEMENT PROFILES TEST: ok=%s ---" % str(ok))
	quit(0 if ok else 1)
