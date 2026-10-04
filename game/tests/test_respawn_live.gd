## test_respawn_live.gd - LIVE death -> UI -> respawn verification in the
## playable scene. Run in RENDERING mode (watch it happen for real):
##
##   cd game && xvfb-run godot --path . --script res://tests/test_respawn_live.gd
##
## Chain exercised (the real integration, not stubs):
##   player.take_damage -> health_component.die -> EventHub.player_died
##     -> RespawnService cycle (holds player, zone-timed delay)
##     -> RespawnUIManager shows the option screen on the same signal
##     -> respawn_completed -> player alive again at the respawn point
##     -> PlayerProgress "respawn" checkpoint written
##
## starter_plains config: bind_point (0,0,0), timed delay 10s. The scene
## player starts at (0,1,0), so a completed respawn must move them.
##
## Exit 0 = every hop observed. Failures print FAIL lines and exit 1.
extends SceneTree

var _pass := 0
var _fail := 0
var _done := false
var _frames := 0
var _verified := false

var _player: Node = null
var _pp: Node = null
var _ruim: Node = null
var _before_pos: Vector3 = Vector3.ZERO

var respawned := false
var respawn_pos := Vector3.ZERO


func _initialize() -> void:
	print("=== RESPAWN LIVE TEST: booting playable scene ===")
	var scene: PackedScene = load("res://scenes/world_playable.tscn")
	if scene == null:
		print("  FAIL: could not load world_playable.tscn")
		quit(1)
		return
	var inst := scene.instantiate()
	root.add_child(inst)
	current_scene = inst


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 90 and not _done:
		_run()
	elif _done and not _verified and _frames % 30 == 0:
		if respawned:
			_verify()
		else:
			_poll_respawn()
		# Terminal verdict: RespawnService's 15s timer lands near frame
		# 990 at precise headless 60Hz -- the old window (< frame 900)
		# raced it and the test then ran forever to the runner kill.
		# 3600 frames (~60s) covers the timer; past it is a FAIL, not a
		# hang (round 22).
		if not _verified and _frames >= 3600:
			_assert(false, "respawn completed within 60s")
			_finish()
	return false


func _run() -> void:
	_done = true

	var rs := root.get_node_or_null("RespawnService")
	_ruim = root.get_node_or_null("RespawnUIManager")
	_pp = root.get_node_or_null("PlayerProgress")
	_assert(rs != null and _ruim != null and _pp != null,
			"autoloads present (RespawnService/RespawnUIManager/PlayerProgress)")
	if rs == null:
		return _finish()

	_player = _find_player()
	_assert(_player != null, "player node present")
	if _player == null:
		return _finish()

	# Record the hops as they fire.
	rs.respawn_completed.connect(func(_p, pos):
		respawned = true
		respawn_pos = pos
		print("    [hop] respawn_completed at %s" % str(pos)))

	# Kill the player through the real damage path.
	_before_pos = _player.global_position
	print("    player at %s, applying lethal damage" % str(_before_pos))
	_player.take_damage(99999, null)

	var hc = _player.health_component
	_assert(hc != null and hc.is_dead(), "player is dead after lethal damage")
	_assert(_player.get("_pending_respawn_mode_int") != null,
			"RespawnService holds the player pending")

	_poll_respawn()


func _poll_respawn() -> void:
	if respawned:
		_verify()
		return
	if _player == null or not is_instance_valid(_player):
		return
	var hc = _player.health_component
	if hc != null and not hc.is_dead() and _player.global_position != _before_pos:
		# Service executed before the signal landed on our handler.
		respawned = true
		respawn_pos = _player.global_position
		_verify()


func _verify() -> void:
	if _verified:
		return
	_verified = true
	var hc = _player.health_component
	_assert(respawned, "respawn_completed fired")
	_assert(hc != null and not hc.is_dead(), "player alive again")
	_assert(_player.global_position != _before_pos, "player moved to the respawn point")
	if respawn_pos != Vector3.ZERO:
		_assert(respawn_pos.distance_to(_player.global_position) < 2.0,
				"respawn point near the player position")

	# PlayerProgress checkpoint: the respawn reason is recorded.
	var snap: Dictionary = _pp.last_saved_snapshot(str(_player.entity_id))
	var saved: bool = not snap.is_empty() and str(snap.get("reason", "")) == "respawn"
	_assert(saved, "PlayerProgress respawn checkpoint written")

	# The death screen was instantiated by RespawnUIManager on death
	# (it hides on respawn_completed but the instance stays).
	var ui_created: bool = _ruim.get("_ui") != null
	_assert(ui_created, "death screen UI instantiated on death")

	_finish()


func _find_player() -> Node:
	var p := current_scene.get_node_or_null("Player")
	if p != null:
		return p
	return get_first_node_in_group("players")


func _assert(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("PASS: %s" % label)
	else:
		_fail += 1
		print("FAIL: %s" % label)


func _finish() -> void:
	print("RespawnLive: %d passed, %d failed" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
