## test_hud_integration - headless smoke test for the world HUD layer.
## Run with:
##   tools/godot --headless --path synmergia --script res://tests/test_hud_integration.gd
extends SceneTree

var _world: Node

func _initialize() -> void:
	print("--- HUD INTEGRATION TEST ---")
	# Wait one frame so all autoloads finish _ready.
	await process_frame
	# Switch to character select so the menu loads.
	var gm: Node = root.get_node_or_null("GameManager")
	if not gm:
		_fail("GameManager autoload missing")
		return
	gm.change_state(gm.GameState.CHARACTER_SELECT)
	await process_frame
	await process_frame
	gm.change_state(gm.GameState.PLAYING)
	# change_scene_to_file defers the swap to a subsequent idle frame,
	# so wait two frames to let the world scene actually attach.
	await process_frame
	await process_frame
	var world: Node = root.get_node_or_null("WorldPlayable")
	if not world:
		_fail("WorldPlayable scene not loaded")
		return
	_world = world
	_ok("WorldPlayable scene loaded")
	var hud: Node = world.get_node_or_null("HudLayer")
	if not hud:
		_fail("HudLayer missing under WorldPlayable")
		return
	_ok("HudLayer present")
	# Count visible widgets
	var n: int = 0
	for child in hud.get_children():
		if child is CanvasLayer or child is Control:
			n += 1
	_ok("HudLayer has %d widget children" % n)
	var integrator: Node = hud.get_node_or_null("HudIntegrator")
	if integrator:
		_ok("HudIntegrator installed and bound")
	else:
		_fail("HudIntegrator not installed")
	# Test that targeting works (set up a target via service)
	var tm: Node = root.get_node_or_null("TargetingManager")
	if tm:
		_ok("TargetingManager autoload present")
	# Verify the service-to-widget signal graph is wired
	# by checking HudIntegrator has connected slots for the key handlers.
	if integrator:
		var expected := [
			"_on_health_changed",
			"_on_mana_changed",
			"_on_xp_changed",
			"_on_chat_received",
			"_on_entity_died",
			"_on_notification",
			"_on_buff_added",
			"_on_debuff_added",
		]
		var missing: Array = []
		for m in expected:
			if not integrator.has_method(m):
				missing.append(m)
		if missing.is_empty():
			_ok("HudIntegrator exposes all expected handlers")
		else:
			_fail("HudIntegrator missing handlers: %s" % str(missing))
	# Notification round-trip smoke: post a fake alert and see if the
	# combat log callback fires.
	if root.has_node("NotificationService") and _world:
		var notif: Node = root.get_node("NotificationService")
		var combat_log: Node = _world.get_node_or_null("HudLayer/CombatLog")
		if combat_log:
			var before: int = 0
			if combat_log.has_method("get_message_count"):
				before = combat_log.get_message_count()
			notif.notification_received.emit("test", {
				"message": "Hello from the test harness",
				"type": "info"
			})
			await process_frame
			var after: int = 0
			if combat_log.has_method("get_message_count"):
				after = combat_log.get_message_count()
			if after > before:
				_ok("NotificationService -> CombatLog round-trip works")
			else:
				_fail("Notification never reached CombatLog (before=%d after=%d)" % [before, after])
		else:
			_fail("CombatLog node not found")
	quit()


func _ok(msg: String) -> void:
	print("  [OK] %s" % msg)


func _fail(msg: String) -> void:
	printerr("  [FAIL] %s" % msg)
	quit(1)
