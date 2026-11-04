extends SceneTree

## Receipt: UIManager <-> GameManager wiring + TargetTooltip spawn.
##
## The defect this freezes: UIManager._ready() guarded its GameManager
## connects with has_method("game_started"/"game_ended"/"game_state_changed").
## Those are SIGNALS, so has_method() is always false and every connect was
## skipped -- UIManager never initialized and the TargetTooltip island was
## never created for the life of the project.
##
## Second defect: TargetTooltip called TargetingManager.get_local_player_id(),
## which did not exist on that class (the accessor is added now).
##
## --script mode does not load autoloads, so the test stands in a faithful
## GameManager stub (same signal names + GameState enum) on /root and
## drives the real UIManager through it.
##
## Run: godot --headless --path . --script res://tests/test_ui_manager_tooltip_wiring.gd

var _passed: int = 0
var _failed: int = 0

func _init() -> void:
	call_deferred("_run")

func _ok(msg: String) -> void:
	_passed += 1
	print("  [OK] ", msg)

func _fail(msg: String) -> void:
	_failed += 1
	print("  [FAIL] ", msg)

func _finish() -> void:
	print("--- UI MANAGER/TOOLTIP WIRING: %d passed, %d failed ---" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _run() -> void:
	# --- 0. The dead-guard idiom itself: has_method is false for a signal ---
	var ps := GDScript.new()
	ps.source_code = "extends Node\nsignal probe_sig\n"
	ps.reload()
	var probe_node = ps.new()
	if probe_node.has_method("probe_sig") == false and probe_node.has_signal("probe_sig") == true:
		_ok("has_method(signal) is false while has_signal(signal) is true (the trap)")
	else:
		_fail("has_method/has_signal signal semantics unexpected")

	var gm := root.get_node_or_null("GameManager")
	if gm == null:
		_fail("GameManager autoload not present")
		_finish()
		return

	# --- 1. Fresh UIManager instance connects to the real GameManager ---
	var um_script = load("res://core/ui/ui_manager.gd")
	if um_script == null:
		_fail("could not load ui_manager.gd")
		_finish()
		return
	var um = um_script.new()
	um.name = "UIManagerWiringProbe"
	root.add_child(um)

	var c_start: bool = gm.game_started.is_connected(Callable(um, "_on_game_started"))
	var c_end: bool = gm.game_ended.is_connected(Callable(um, "_on_game_ended"))
	var c_state: bool = gm.game_state_changed.is_connected(Callable(um, "_on_game_state_changed"))
	if c_start and c_end and c_state:
		_ok("UIManager connected to game_started/game_ended/game_state_changed")
	else:
		_fail("UIManager connects missing (start=%s end=%s state=%s)" % [c_start, c_end, c_state])

	# The shipped autoload must be wired too (production path).
	var live := root.get_node_or_null("UIManager")
	if live != null and gm.game_started.is_connected(Callable(live, "_on_game_started")):
		_ok("the live UIManager autoload is wired to game_started")
	else:
		_fail("the live UIManager autoload is not wired")

	# --- 2. game_started handler spawns the TargetTooltip island ---
	if um._tooltip == null and um._initialized == false:
		_ok("tooltip not created before game_started")
	else:
		_fail("UIManager initialized too early")

	um._on_game_started()
	if um._initialized and um._tooltip != null and is_instance_valid(um._tooltip):
		_ok("game_started initializes UIManager and spawns TargetTooltip")
	else:
		_fail("game_started did not spawn the tooltip")
	if um._tooltip != null and um._tooltip.name == "TargetTooltip":
		_ok("tooltip node is named TargetTooltip")
	else:
		_fail("tooltip node name wrong")

	# --- 3. game_state_changed handler drives show/hide ---
	um._tooltip.hide()
	um._on_game_state_changed(gm.GameState.PLAYING)
	if um._tooltip != null and um._tooltip.visible:
		_ok("PLAYING state shows the tooltip")
	else:
		_fail("PLAYING state did not show the tooltip")
	um._on_game_state_changed(gm.GameState.MAIN_MENU)
	if um._tooltip != null and not um._tooltip.visible:
		_ok("MAIN_MENU state hides the tooltip")
	else:
		_fail("MAIN_MENU state did not hide the tooltip")

	# --- 4. game_ended tears the island down; a re-start rebuilds it ---
	um._on_game_ended()
	if um._tooltip == null and um._initialized == false:
		_ok("game_ended cleans up the tooltip and resets state")
	else:
		_fail("game_ended did not clean up")
	um._on_game_started()
	if um._initialized and um._tooltip != null and is_instance_valid(um._tooltip):
		_ok("a second game_started rebuilds the tooltip (re-entry safe)")
	else:
		_fail("second game_started did not rebuild the tooltip")

	# --- 5. TargetingManager.get_local_player_id() round-trips ---
	var tm = root.get_node_or_null("TargetingManager")
	if tm == null:
		_fail("TargetingManager autoload not present")
	elif tm.has_method("get_local_player_id"):
		tm.set_local_player("player_roundtrip")
		if tm.get_local_player_id() == "player_roundtrip":
			_ok("TargetingManager.get_local_player_id() round-trips")
		else:
			_fail("get_local_player_id() returned the wrong id")
	else:
		_fail("TargetingManager is missing get_local_player_id() (the phantom call)")

	um._on_game_ended()
	um.queue_free()
	_finish()
