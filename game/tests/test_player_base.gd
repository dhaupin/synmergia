## test_player_base - THE SHARED PLAYER SURFACE (planar-retirement Step 0).
##
## The two player bodies (PlayerController + GlobeWorldPlayer) were
## siblings with no shared base, so ~20 shared systems gated on
## `is PlayerController` and the globe body fell outside them. This
## receipt proves PlayerBase exists, both bodies are `is PlayerBase`,
## and the shared surface (progression, gold voice, health, death
## signal) works through inheritance on BOTH bodies -- including the
## globe body, which never had it before.
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
	var PC: GDScript = load("res://entities/player/player_controller.gd")
	var GP: GDScript = load("res://entities/globe_player.gd")
	_check(PB != null and PC != null and GP != null, "all three player scripts load")
	if PB == null or PC == null or GP == null:
		_finish()
		return

	# Instantiated OFF-TREE on purpose: no _ready side effects, and the
	# inherited surface must stand on its own.
	var planar = PC.new()
	var globe = GP.new()
	_check(planar != null and globe != null, "both bodies instantiate")

	# 1. The shared type (the whole point of the keystone).
	_check(planar is PlayerBase, "planar body is PlayerBase")
	_check(planar is PlayerController, "planar body still is PlayerController")
	_check(globe is PlayerBase, "globe body is PlayerBase (the fix)")
	_check(globe is GlobeWorldPlayer, "globe body still is GlobeWorldPlayer")

	# 2. Progression surface inherited by BOTH (the globe never had it).
	planar.experience_to_next_level = 10
	planar.add_experience(10)
	_check(planar.level == 2, "planar add_experience levels up (inherited)")
	globe.experience_to_next_level = 10
	globe.add_experience(10)
	_check(globe.level == 2, "globe add_experience levels up (inherited)")

	# 3. Gold voice -- standalone bodies keep their own speak lane.
	var seen := [0]
	planar.gold_changed.connect(func(v: int) -> void: seen[0] = v)
	planar.add_gold(25)
	_check(planar.gold == 25 and seen[0] == 25, "planar gold field + gold_changed voice")
	globe.add_gold(40)
	_check(globe.gold == 40, "globe gold field (inherited)")

	# 4. Health surface inherited by BOTH.
	planar._ensure_health_component()
	_check(planar.health_component != null, "planar health component ensured")
	globe._ensure_health_component()
	_check(globe.health_component != null, "globe health component ensured")
	var dealt: int = globe.take_damage(30)
	_check(dealt == 30 and globe.current_health == 70, "globe take_damage -> mirror 70")
	globe.heal(10)
	_check(globe.current_health == 80, "globe heal -> mirror 80")
	_check(not globe.is_dead(), "globe is_dead false while alive")

	# 5. The player-death signal lives on the shared base (health_component
	#    emits player_died for `is PlayerBase` bodies now).
	_check(planar.has_signal("player_died"), "planar has player_died")
	_check(globe.has_signal("player_died"), "globe has player_died")
	_check(globe.has_signal("leveled_up") and globe.has_signal("experience_changed"),
		"globe has progression signals")

	# 6. The retargeted gate: a globe body passes `is PlayerBase`, which is
	#    what resurrection targeting + the death/PvP emits now check.
	_check(globe is PlayerBase, "globe body passes the retargeted is-PlayerBase gate")

	planar.free()
	globe.free()
	_finish()
