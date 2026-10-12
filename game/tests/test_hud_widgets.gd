## test_hud_widgets - orphan-face verify: PartyFrames + NotificationToast
## are mounted on the LIVE hud_layer.tscn scene (they used to be dead
## scripts nothing ever instantiated) and respond to real data:
##   - NotificationService CORNER location -> NotificationToast stack grows
##     (via HudIntegrator's location law), CHAT_LOG -> it does not.
##   - HudIntegrator dedupes the double-wired notification_sent /
##     notification_received pair so one send() = one toast.
##   - PartyFrames renders the member dicts pushed via update_party(),
##     hides when the party empties, and caps at MAX_PARTY_SIZE.
##
## Run: godot --headless --path game --script res://tests/test_hud_widgets.gd
extends SceneTree

var _passed := 0
var _failed := 0


func _initialize() -> void:
	print("--- HUD WIDGET WIRING TEST (PartyFrames + NotificationToast) ---")
	await process_frame

	var scene: PackedScene = load("res://ui/hud/hud_layer.tscn")
	if scene == null or not scene.can_instantiate():
		_fail("hud_layer.tscn did not load")
		_finish()
		return
	var hud := scene.instantiate()
	root.add_child(hud)
	await process_frame
	await process_frame

	# Integrator contract: hud_layer.gd installs it in _ready.
	var integrator: Node = hud.get_node_or_null("HudIntegrator")
	if integrator == null:
		_fail("HudIntegrator not installed by hud_layer (bind missing?)")
	else:
		_ok("HudIntegrator present on HUD scene")

	# --- Both formerly-orphaned widgets exist on the live scene. ---
	var toast: Control = hud.get_node_or_null("NotificationToast")
	var party: Control = hud.get_node_or_null("PartyFrames")
	if toast == null:
		_fail("NotificationToast node not on hud_layer.tscn")
	else:
		_ok("NotificationToast mounted on HUD scene")
	if party == null:
		_fail("PartyFrames node not on hud_layer.tscn")
	else:
		_ok("PartyFrames mounted on HUD scene (starts hidden: %s)" % str(not party.visible))

	if toast != null:
		_run_toast_checks(toast)

	if party != null:
		_run_party_checks(party)

	hud.queue_free()
	await process_frame
	_finish()


func _run_toast_checks(toast: Control) -> void:
	var toast_active: int = _stack_size(toast)

	# 1. CORNER-located notification: must reach the dedicated face.
	var notif: Node = root.get_node_or_null("NotificationService")
	if notif == null:
		_fail("NotificationService autoload missing")
		return

	notif.reset_dedupe()
	# send_to_player(entity, msg, type, priority, location); 2 = CORNER.
	notif.send_to_player("hudwidgets_player", "HDR toast law", 0, 1, 2)
	await process_frame
	await process_frame
	if _stack_size(toast) > toast_active:
		_ok("CORNER notification reached NotificationToast (%d active)" % _stack_size(toast))
	else:
		_fail("CORNER notification did not reach NotificationToast")

	# 2. CHAT_LOG: must stay off the toast stack (it is a log face).
	toast_active = _stack_size(toast)
	notif.send_to_player("hudwidgets_player", "log face only", 0, 1, 0)
	await process_frame
	await process_frame
	if _stack_size(toast) == toast_active:
		_ok("CHAT_LOG notification stays off the toast stack")
	else:
		_fail("CHAT_LOG notification leaked onto the toast stack")

	# 3. Double-wire: notification_sent + notification_received both carry
	#    the payload; only one toast may land per identical send().
	toast_active = _stack_size(toast)
	notif.reset_dedupe()
	notif.send_to_player("hudwidgets_player", "dedupe probe toast", 0, 1, 2)
	await process_frame
	await process_frame
	await process_frame
	var grew: int = _stack_size(toast) - toast_active
	if grew == 1:
		_ok("notification_sent/received double-fire deduped (%d toast)" % grew)
	else:
		_fail("dedupe law broken: %d toasts for one send (expected 1)" % grew)

	# 4. Flood law: the stack never exceeds its 5-visible cap.
	for i in range(12):
		notif.reset_dedupe()
		notif.send_to_player("hudwidgets_player", "flood %d" % i, 0, 1, 2)
	await process_frame
	await process_frame
	var flood_active: int = _stack_size(toast)
	if flood_active <= toast.MAX_VISIBLE_TOASTS:
		_ok("flood respected stack cap (%d <= %d)" % [flood_active, toast.MAX_VISIBLE_TOASTS])
	else:
		_fail("flood overflowed the stack (%d > %d)" % [flood_active, toast.MAX_VISIBLE_TOASTS])


func _run_party_checks(party: Control) -> void:
	# PartyService's own signal surface is pinned by the party tests; this
	# probe pins the FACE: what it renders for the member dicts the
	# integrator/services push into it.
	party._member_data.clear()
	party.update_party([_fake_member()])
	await process_frame
	if party.visible and party.get_member_count() == 1:
		_ok("PartyFrames renders a member and becomes visible")
	else:
		_fail("PartyFrames did not render the member (visible=%s count=%d)" % [str(party.visible), party.get_member_count()])

	party.update_party([])
	await process_frame
	if not party.visible:
		_ok("empty party hides PartyFrames")
	else:
		_fail("empty party left PartyFrames visible")

	# Members beyond the 5-cap never render extra frames.
	var members: Array = []
	for i in range(7):
		var m := _fake_member()
		m["player_id"] = "cap_p%d" % i
		members.append(m)
	party.update_party(members)
	await process_frame
	var rendered := 0
	for frame in party._member_containers:
		if frame.visible:
			rendered += 1
	if rendered == 5:
		_ok("frame render capped at MAX_PARTY_SIZE (5/%d pushed)" % members.size())
	else:
		_fail("frame cap broken: rendered %d of %d" % [rendered, members.size()])
	party.update_party([])


func _fake_member() -> Dictionary:
	return {
		"player_id": "cap_p0",
		"name": "ProbeMate",
		"class": "mage",
		"level": 4,
		"health": 80,
		"max_health": 100,
		"mana": 50,
		"max_mana": 100,
		"role": 2,
		"distance": 9.0,
		"is_leader": true,
		"ready_check": false,
	}


func _stack_size(face: Node) -> int:
	var stack: Variant = face.get("_active_toasts")
	if stack is Array:
		return (stack as Array).size()
	return 0


func _ok(msg: String) -> void:
	_passed += 1
	print("  [OK] %s" % msg)


func _fail(msg: String) -> void:
	_failed += 1
	printerr("  [FAIL] %s" % msg)


func _finish() -> void:
	print("\n=== HUD WIDGET TEST SUMMARY ===")
	print("Passed: %d  Failed: %d" % [_passed, _failed])
	print("RESULT: %s" % ("ALL TESTS PASSED" if _failed == 0 else "%d TESTS FAILED" % _failed))
	quit(0 if _failed == 0 else 1)
