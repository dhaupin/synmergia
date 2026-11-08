## test_player_base - THE SHARED PLAYER SURFACE (planar-retirement Step 0,
## extended in Step 5).
##
## The player body (GlobeWorldPlayer) and the shared base (PlayerBase) exist
## so ~20 shared systems gate on `is PlayerBase` instead of a concrete body.
## This receipt proves PlayerBase exists, the globe body is `is PlayerBase`,
## a bare PlayerBase carries the shared surface (progression, gold voice,
## health, death signal, combat, the walk-up dock seam), and the globe body
## inherits it. Planar-retirement Step 5 removed the planar PlayerController,
## so PlayerBase is now the SOLE shared surface.
##
## Run: godot --headless --path game --script res://tests/test_player_base.gd
extends SceneTree

var _passed := 0
var _failed := 0


func _ok(msg: String) -> void:
	_passed += 1
	print("   PASS  %s" % msg)


func _fail(msg: String) -> void:
	_failed += 1
	print("   FAIL  %s" % msg)


func _check(cond: bool, msg: String) -> void:
	if cond:
		_ok(msg)
	else:
		_fail(msg)


func _finish() -> void:
	print("=== PLAYER BASE RECEIPT: %d checks, %d failed ===" % [_passed, _failed])
	if _failed == 0:
		print("PLAYER BASE RECEIPT PASSED")
		quit(0)
	else:
		print("PLAYER BASE RECEIPT FAILED")
		quit(1)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("--- PLAYER BASE RECEIPT ---")
	await process_frame

	var PB: GDScript = load("res://entities/player/player_base.gd")
	var GP: GDScript = load("res://entities/globe_player.gd")
	_check(PB != null and GP != null, "the player scripts load")
	if PB == null or GP == null:
		_finish()
		return

	# Instantiated OFF-TREE on purpose: no _ready side effects, and the
	# inherited surface must stand on its own.
	var base = PB.new()
	var globe = GP.new()
	_check(base != null and globe != null, "both bodies instantiate")

	# 1. The shared type (the whole point of the keystone).
	_check(base is PlayerBase, "bare PlayerBase is PlayerBase")
	_check(globe is PlayerBase, "globe body is PlayerBase")
	_check(globe is GlobeWorldPlayer, "globe body still is GlobeWorldPlayer")

	# 2. Progression surface inherited from the base.
	base.experience_to_next_level = 10
	base.add_experience(10)
	_check(base.level == 2, "bare PlayerBase add_experience levels up")
	globe.experience_to_next_level = 10
	globe.add_experience(10)
	_check(globe.level == 2, "globe add_experience levels up (inherited)")

	# 3. Gold voice -- standalone bodies keep their own speak lane.
	var seen := [0]
	base.gold_changed.connect(func(v: int) -> void: seen[0] = v)
	base.add_gold(25)
	_check(base.gold == 25 and seen[0] == 25, "bare PlayerBase gold field + gold_changed voice")
	globe.add_gold(40)
	_check(globe.gold == 40, "globe gold field (inherited)")

	# 4. Health surface inherited from the base.
	base._ensure_health_component()
	_check(base.health_component != null, "bare PlayerBase health component ensured")
	globe._ensure_health_component()
	_check(globe.health_component != null, "globe health component ensured")
	var dealt: int = globe.take_damage(30)
	_check(dealt == 30 and globe.current_health == 70, "globe take_damage -> mirror 70")
	globe.heal(10)
	_check(globe.current_health == 80, "globe heal -> mirror 80")
	_check(not globe.is_dead(), "globe is_dead false while alive")

	# 5. The player-death signal lives on the shared base (health_component
	#    emits player_died for `is PlayerBase` bodies now).
	_check(base.has_signal("player_died"), "bare PlayerBase has player_died")
	_check(globe.has_signal("player_died"), "globe has player_died")
	_check(globe.has_signal("leveled_up") and globe.has_signal("experience_changed"),
			"globe has progression signals")

	# 6. The gate: a globe body passes `is PlayerBase`, which is what
	#    resurrection targeting + the death/PvP emits check.
	_check(globe is PlayerBase, "globe body passes the is-PlayerBase gate")

	# 7. Combat surface inherited from the base. The ActionBar casts through
	#    player.use_skill and the hitbox sweep calls target.apply_status_effect;
	#    both live on PlayerBase now. The walk-up dock seam moved here in Step 5.
	_check(base.has_method("use_skill"), "bare PlayerBase has use_skill")
	_check(globe.has_method("use_skill"), "globe has use_skill")
	_check(base.has_method("apply_status_effect"), "bare PlayerBase has apply_status_effect")
	_check(globe.has_method("apply_status_effect"), "globe has apply_status_effect")
	_check(globe.has_method("_setup_starting_skills"), "globe has _setup_starting_skills")
	_check(globe.has_method("_ensure_effect_stack"), "globe has _ensure_effect_stack")
	_check(base.has_method("_dock_vehicle_for_pin"), "bare PlayerBase has the walk-up dock seam")

	# The effect stack attaches real components on the bodies.
	globe._ensure_effect_stack(true)
	_check(globe.aura_component != null, "globe aura component attached")
	_check(globe.combat_component != null, "globe combat component attached")
	base._ensure_effect_stack(true)
	_check(base.combat_component != null, "bare PlayerBase combat component attached")

	# A cast with an empty skillbar is a safe no-op on the globe body
	# (the ActionBar's exact call path), never a crash.
	globe.use_skill(0)
	_check(true, "globe use_skill(0) on empty skillbar is a safe no-op")

	base.free()
	globe.free()
	_finish()
