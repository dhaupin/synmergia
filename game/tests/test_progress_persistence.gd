## test_progress_persistence.gd - PlayerProgress save -> restore round-trip
## through the real DictStore path. Run headless:
##
##   cd game && godot --headless --path . --script res://tests/test_progress_persistence.gd
##
## Covers:
##   1. save_player writes a snapshot (xp/gold/level/position) into the store
##   2. clear + mutate + restore_player round-trips the values back
##   3. per-character isolation: char A's save never leaks into char B
##   4. fresh character (no save) keeps defaults, restore returns false
##   5. stale snapshot applies (durable copy wins over node defaults)
##
## Exit 0 = all pass.
extends SceneTree

var _passed := 0
var _failed := 0


func _initialize() -> void:
	await process_frame
	await process_frame
	await _run()
	quit(0 if _failed == 0 else 1)


func _run() -> void:
	var PlayerScript = load("res://entities/player/player_base.gd")
	var progress_script = load("res://core/services/player_progress.gd")

	# Use a fresh PlayerProgress instance (not the autoload) so the test
	# store is private, while still exercising the real DictStore path.
	var progress = progress_script.new()
	get_root().add_child(progress)
	await process_frame

	# ------------------------------------------------------------------
	# 1. save_player writes a snapshot
	# ------------------------------------------------------------------
	var player: Node = PlayerScript.new()
	player.display_name = "PersistHero"
	player.entity_id = "test_char_A"
	get_root().add_child(player)
	await process_frame

	player.add_experience(1200)  # levels: 1 -> 2 with 200 xp left over
	player.add_gold(250)
	var saved: bool = progress.save_player(player, "test")
	_assert(saved, "save_player returns true for a valid character")
	_assert(progress.has_progress("test_char_A"), "has_progress true after save")

	var snap: Dictionary = progress.last_saved_snapshot("test_char_A")
	_assert(int(snap.get("experience", -1)) == 200, "snapshot carries xp (leftover)")
	_assert(int(snap.get("gold", -1)) == 250, "snapshot carries gold")
	_assert(int(snap.get("level", -1)) == 2, "snapshot carries level")
	_assert(snap.has("position"), "snapshot carries position (Node3D player)")

	# ------------------------------------------------------------------
	# 2. clear + mutate + restore round-trip
	# ------------------------------------------------------------------
	var original_pos: Vector3 = player.global_position
	progress.clear_progress("test_char_A")
	_assert(not progress.has_progress("test_char_A"), "clear_progress drops the save")

	player.add_experience(111)
	player.add_gold(111)
	var restored: bool = progress.restore_player(player)
	_assert(not restored, "restore after clear returns false (no snapshot)")

	# Re-save with the mutated values, then scramble the node and restore:
	# every field must come back to the SAVED point, including position.
	progress.save_player(player, "test")
	player.experience = 0
	player.gold = 0
	player.level = 1
	player.global_position = Vector3(77.0, 3.0, -13.0)
	restored = progress.restore_player(player)
	_assert(restored, "restore_player applies an existing snapshot")
	_assert(int(player.experience) == 311, "xp restored (200 + 111)")
	_assert(int(player.gold) == 361, "gold restored (250 + 111)")
	_assert(int(player.level) == 2, "level restored")
	_assert(player.global_position.distance_to(original_pos) < 0.01,
			"position restored to the saved point, not the scrambled one")

	# ------------------------------------------------------------------
	# 3. per-character isolation
	# ------------------------------------------------------------------
	var player_b: Node = PlayerScript.new()
	player_b.display_name = "PersistHeroB"
	player_b.entity_id = "test_char_B"
	get_root().add_child(player_b)
	await process_frame

	_assert(not progress.has_progress("test_char_B"),
			"char B starts with no save")
	player_b.add_experience(42)
	player_b.add_gold(7)
	progress.save_player(player_b, "test")

	# Char A's snapshot must be untouched by B's activity.
	var snap_a: Dictionary = progress.last_saved_snapshot("test_char_A")
	_assert(int(snap_a.get("gold", -1)) == 361, "char A save isolated from char B")
	_assert(int(player.experience) == 311, "char A state untouched by B")

	player_b.free()
	player.free()
	await process_frame

	# ------------------------------------------------------------------
	# 4. fresh character keeps defaults
	# ------------------------------------------------------------------
	var player_c: Node = PlayerScript.new()
	player_c.display_name = "FreshHero"
	player_c.entity_id = "test_char_C"
	get_root().add_child(player_c)
	await process_frame

	_assert(not progress.has_progress("test_char_C"), "fresh char has no save")
	var fresh_restored: bool = progress.restore_player(player_c)
	_assert(not fresh_restored, "fresh char restore returns false")
	_assert(int(player_c.experience) == 0, "fresh char xp default kept")
	_assert(int(player_c.gold) == 0, "fresh char gold default kept")

	# ------------------------------------------------------------------
	# 5. stale snapshot applies (the durable copy wins over defaults)
	# ------------------------------------------------------------------
	progress._debug_set_raw("test_char_C", {
		"experience": 5000, "gold": 999, "level": 5,
		"position": {"x": 1.0, "y": 2.0, "z": 3.0},
	})
	restored = progress.restore_player(player_c)
	_assert(restored, "stale snapshot restore returns true")
	_assert(int(player_c.level) == 5, "stale snapshot level applies")
	_assert(int(player_c.experience) == 5000, "stale snapshot xp applies")

	player_c.free()
	await process_frame

	print("ProgressPersistence: %d passed, %d failed" % [_passed, _failed])


func _assert(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("PASS: %s" % label)
	else:
		_failed += 1
		print("FAIL: %s" % label)
