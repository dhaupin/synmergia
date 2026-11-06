## test_globe_autosave_guard - THE GROUP FALLBACK MUST NOT CLOBBER SAVES.
##
## PlayerProgress._find_tracked_player falls back to the "players" group
## for its autosave tick. Two hazards: (1) saving a body whose entity_id
## is NOT the character would write the wrong progression over the real
## snapshot; (2) a body with no progression surface would fabricate a
## 0/0/1 snapshot. Since PlayerBase, the globe body HAS the progression
## surface, so identity is the honest key -- the guard matches entity_id
## and still rejects a progress-less body.
##
## Run: godot --headless --path game --script res://tests/test_globe_autosave_guard.gd
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
	print("=== GLOBE AUTOSAVE GUARD RECEIPT: %d checks, %d failed ===" % [_passed, _failed])
	if _failed == 0:
		print("GLOBE AUTOSAVE GUARD RECEIPT PASSED")
		quit(0)
	else:
		print("GLOBE AUTOSAVE GUARD RECEIPT FAILED")
		quit(1)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("--- GLOBE AUTOSAVE GUARD RECEIPT ---")
	await process_frame

	var progress = root.get_node_or_null("PlayerProgress")
	_check(progress != null, "PlayerProgress autoload is present")
	if progress == null:
		_finish()
		return

	# 1. A globe body whose entity_id is NOT the requested character must be
	#    REJECTED (no cross-body clobber), even though it now HAS progression.
	var GP: GDScript = load("res://entities/globe_player.gd")
	var globe = GP.new()
	globe.entity_id = "guard_globe"
	root.add_child(globe)
	globe.set_physics_process(false)
	await process_frame
	_check(globe.is_in_group("players"), "globe body is in 'players'")
	var resolved = progress._find_tracked_player("someone_else")
	_check(resolved == null,
		"_find_tracked_player rejects a body whose entity_id mismatches")

	# 2. The SAME body IS returned when the entity_id matches (it is a real
	#    player now).
	var resolved_self = progress._find_tracked_player("guard_globe")
	_check(resolved_self == globe,
		"_find_tracked_player returns the matching globe body")

	# 3. A progress-bearing body in "players" with a matching id is returned.
	var stub = Node.new()
	stub.name = "ProgressStub"
	stub.set_script(_make_stub_script())
	stub.set("experience", 500)
	stub.set("gold", 250)
	stub.set("level", 4)
	stub.entity_id = "guard_stub"
	globe.queue_free()
	await process_frame
	root.add_child(stub)
	stub.add_to_group("players")
	await process_frame
	var resolved2 = progress._find_tracked_player("guard_stub")
	_check(resolved2 == stub,
		"_find_tracked_player still returns a progress-bearing body")

	# 4. A body with NO progression surface is still rejected (no fabricated
	#    0/0/1 snapshot), even if its id matches.
	var bare = Node.new()
	bare.name = "BareStub"
	bare.set_script(_make_bare_stub_script())
	bare.set("entity_id", "guard_bare")
	stub.queue_free()
	await process_frame
	root.add_child(bare)
	bare.add_to_group("players")
	await process_frame
	var none = progress._find_tracked_player("guard_bare")
	_check(none == null, "a progress-less body yields no tracked player to autosave")

	bare.queue_free()
	await process_frame
	_finish()


func _make_stub_script() -> GDScript:
	var s := GDScript.new()
	s.source_code = "extends Node\nvar entity_id: String = \"\"\nvar experience: int = 0\nvar gold: int = 0\nvar level: int = 1\n"
	s.reload()
	return s


func _make_bare_stub_script() -> GDScript:
	var s := GDScript.new()
	s.source_code = "extends Node\nvar entity_id: String = \"\"\n"
	s.reload()
	return s
