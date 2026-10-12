## test_notification_toast - end-to-end smoke test for the
## NotificationService -> TooltipManager.show_toast() pipeline.
##
## Run with:
##   tools/godot --headless --path synmergia --script res://tests/test_notification_toast.gd
extends SceneTree
var _world: Node
var _passed := 0
var _failed := 0


func _initialize() -> void:
	print("--- NOTIFICATION -> TOAST INTEGRATION TEST ---")
	await process_frame
	# Drop into PLAYING so the HUD (with the TooltipManager) is live.
	var gm: Node = root.get_node_or_null("GameManager")
	if not gm:
		_fail("GameManager autoload missing")
		return
	gm.change_state(gm.GameState.PLAYING)
	await process_frame
	await process_frame

	# In headless mode, WorldPlayable scene is not loaded (no 3D rendering context).
	# Manually instantiate the HudLayer with TooltipManager for testing.
	_world = root.get_node_or_null("WorldPlayable")
	if not _world:
		_world = await _setup_headless_hud()
		if not _world:
			_fail("Failed to set up headless HUD for testing")
			return
	_ok("Headless HUD set up (TooltipManager available)")

	var tooltip_mgr: Node = _world.get_node_or_null("HudLayer/TooltipManager")
	if not tooltip_mgr:
		# TooltipManager is sometimes parented elsewhere -- walk the tree.
		tooltip_mgr = _find_node(_world, "TooltipManager")
	if not tooltip_mgr:
		_fail("TooltipManager not found in world tree")
		return
	_ok("TooltipManager present: %s" % tooltip_mgr.get_path())

	if not tooltip_mgr.has_method("show_toast"):
		_fail("TooltipManager.show_toast() missing -- add it to tooltip_manager.gd")
		return
	_ok("TooltipManager has show_toast()")

	# 1. Direct call to show_toast -- verify the panel actually appears.
	_clear_toasts(tooltip_mgr)
	tooltip_mgr.show_toast("Direct toast call", Color.YELLOW, 0.5)
	await process_frame
	if _active_toast_count(tooltip_mgr) > 0:
		_ok("show_toast() created a panel (count=%d)" % _active_toast_count(tooltip_mgr))
	else:
		_fail("show_toast() did not create a panel")

	# 2. NotificationService round-trip -- a CORNER-located notification
	#    flows through the HUD integrator into the toast face (prefer the
	#    dedicated NotificationToast stack; fall back to TooltipManager).
	var notif: Node = root.get_node_or_null("NotificationService")
	if not notif:
		_fail("NotificationService autoload missing")
		return
	_clear_toasts(tooltip_mgr)
	var toast_face: Node = _world.get_node_or_null("HudLayer/NotificationToast")
	if toast_face == null:
		toast_face = _find_node(_world, "NotificationToast")
	var face_active: int = _toast_face_count(toast_face)
	# DisplayLocation.CORNER == 2 -- the corner-toast location.
	notif.send_to_player("test_player", "Hello via NotificationService", 0, 1, 2)
	await process_frame
	await process_frame
	var reached: bool = _toast_face_count(toast_face) > face_active \
		or _active_toast_count(tooltip_mgr) > 0
	if reached:
		_ok("NotificationService CORNER -> toast face (%d panels)" % max(_toast_face_count(toast_face), _active_toast_count(tooltip_mgr)))
	else:
		_fail("Notification never reached a toast face -- HudIntegrator not wired?")

	# 2b. A CHAT_LOG notification must NOT spawn a toast (corner law:
	# only CORNER-located notifications hit the stack; chat-log ones
	# belong to the combat log).
	_clear_toasts(tooltip_mgr)
	face_active = _toast_face_count(toast_face)
	notif.send_to_player("test_player", "Chat log only, no toast", 0, 1, 0)
	await process_frame
	await process_frame
	if _toast_face_count(toast_face) == face_active and _active_toast_count(tooltip_mgr) == 0:
		_ok("CHAT_LOG notification stays off the toast stack")
	else:
		_fail("CHAT_LOG notification leaked onto the toast stack")

	# 3. Flood a handful of toasts to make sure the stack limit kicks in.
	for i in range(8):
		tooltip_mgr.show_toast("Spam test %d" % i, Color.WHITE, 0.1)
	await process_frame
	var stack: Array = tooltip_mgr.get("_active_toasts")
	if stack.size() <= 5:
		_ok("Stack limit respected (active=%d, limit=5)" % stack.size())
	else:
		_fail("Stack overflow: active=%d" % stack.size())

	# 4. broadcast_alert -- same pipeline, admin scope.
	notif.broadcast_alert(
		"[TEST] Server-wide alert",
		[notif.AlertScope.server_wide()],
		14, # ALERT
		3   # CRITICAL
	)
	await process_frame
	_ok("broadcast_alert() did not crash with single-scope array")

	# 6. AppFirewall -> RecursionGuard -> NotificationService pipeline.
	#    When a recursive call exceeds the configured depth, the guard
	#    emits block_triggered, AppFirewall listens, and routes the
	#    event to NotificationService.broadcast_server (admin scope).
	var firewall: Node = root.get_node_or_null("AppFirewall")
	if not firewall:
		_fail("AppFirewall autoload missing -- cannot test recursion guard")
	else:
		_clear_toasts(tooltip_mgr)
		var guard: RefCounted = firewall.get_recursion_guard()
		if guard == null:
			_fail("AppFirewall.get_recursion_guard() returned null")
		else:
			# Force a block: set a tiny max depth, then enter past it. Use a
			# FRESH context name each run -- RecursionGuard keeps a process-
			# level depth tracker, and a context from an earlier suite run
			# (or step) sits at depth > 0, so the first enter() here would
			# block and break the allow/allow/block shape assertion.
			var ctx_name := "test_toast_ctx_v%d" % (Time.get_ticks_msec() % 100000)
			guard.set_max_depth(ctx_name, 2)
			var allowed_1: bool = guard.enter(ctx_name)
			var allowed_2: bool = guard.enter(ctx_name)
			var allowed_3: bool = guard.enter(ctx_name)
			await process_frame
			await process_frame
			if allowed_1 and allowed_2 and not allowed_3:
				_ok("RecursionGuard: enter/exit semantics correct (allow, allow, block)")
			else:
				_fail("RecursionGuard semantics wrong: a1=%s a2=%s a3=%s" % [allowed_1, allowed_2, allowed_3])
			# Rendering law: the firewall recursion alert is a HIGH-priority
			# SECURITY_BLOCKED admin alert, which the notification frame
			# maps to CENTER_SCREEN (1), NOT a corner toast. Pin the
			# pipeline instead: the payload reached NotificationService
			# under player_id="admins" with kind SECURITY_BLOCKED (24) in
			# its data. Ambient gameplay toasts (achievements, bouts) may
			# legitimately share the stack during the await, so the stack
			# is checked BY CONTENT: the recursion message must not be on
			# it.
			if not _stack_contains(tooltip_mgr, "RecursionGuard") \
					and not _face_contains(toast_face, "RecursionGuard"):
				_ok("admin recursion alert stays off the corner toast stack (center-screen law)")
			else:
				_fail("admin center-screen alert leaked onto the corner toast stack")
			var admins_hist: Array = notif.get_history("admins", 20)
			var captured := false
			for entry in admins_hist:
				var data: Dictionary = entry.get("data", {})
				if int(data.get("kind", -1)) == 24 \
						and str(data.get("context", "")) == ctx_name:
					captured = true
					break
			if captured:
				_ok("RecursionGuard block -> AppFirewall -> NotificationService (kind=24, ctx=%s)" % ctx_name)
			else:
				_fail("Recursion block never reached NotificationService (no kind=24 entry for ctx)")
			guard.exit(ctx_name)
			guard.exit(ctx_name)

	_print_summary()
	quit(0 if _failed == 0 else 1)


func _find_node(root_node: Node, node_name: String) -> Node:
	if root_node.name == node_name:
		return root_node
	for child in root_node.get_children():
		var found: Node = _find_node(child, node_name)
		if found:
			return found
	return null


func _setup_headless_hud() -> Node:
	# Create a minimal test world node with HudLayer, TooltipManager and
	# the dedicated NotificationToast face.
	var test_world := Node.new()
	test_world.name = "WorldPlayable"
	root.add_child(test_world)

	# Load and instantiate HudLayer scene (which includes TooltipManager)
	var HudLayerScript := load("res://ui/hud/hud_layer.gd")
	if not HudLayerScript:
		_fail("Failed to load HudLayer script")
		return null

	var hud: Node = HudLayerScript.new()
	hud.name = "HudLayer"
	# Pre-create the widget children this test exercises. In the real scene
	# they come from hud_layer.tscn; a script-instantiated headless HUD has
	# no scene children, and _find() resolves direct children only at _ready,
	# so add them BEFORE the HUD enters the tree.
	var TooltipScript := load("res://ui/components/tooltip_manager.gd")
	if TooltipScript:
		var tooltip: Control = TooltipScript.new()
		tooltip.name = "TooltipManager"
		hud.add_child(tooltip)
	var ToastScript := load("res://ui/components/notification_toast.gd")
	if ToastScript:
		var toast: Control = ToastScript.new()
		toast.name = "NotificationToast"
		hud.add_child(toast)
	test_world.add_child(hud)
	# NOTE: do NOT call _ready() manually -- add_child() on a node already
	# inside the tree triggers it, and HudLayer guards double-init with a
	# static instance (second _ready() queue_free()s the HUD).
	await process_frame
	await process_frame

	# Verify HudIntegrator was installed
	var integrator: Node = hud.get_node_or_null("HudIntegrator")
	if not integrator:
		_fail("HudIntegrator not installed in headless HUD")
		return null

	# Bind the integrator to the HUD (normally done by _install_integrator)
	if integrator.has_method("bind"):
		integrator.call("bind", hud)

	# Verify TooltipManager exists
	var tooltip: Node = hud.get_node_or_null("TooltipManager")
	if not tooltip:
		_fail("TooltipManager not found in headless HudLayer")
		return null

	return test_world


func _active_toast_count(tooltip_mgr: Node) -> int:
	var stack: Array = tooltip_mgr.get("_active_toasts")
	return stack.size() if stack != null else 0


## Active panels on the dedicated NotificationToast face (same field name,
## different node -- null face counts as 0).
func _toast_face_count(toast_face: Node) -> int:
	if toast_face == null:
		return 0
	var stack: Array = toast_face.get("_active_toasts")
	return stack.size() if stack != null else 0


## Content scan for a toast-face stack: any active panel whose labels
## contain the needle counts. Handles both faces (TooltipManager panels
## hold one Label; NotificationToast panels hold title/message labels).
func _stack_contains(face: Node, needle: String) -> bool:
	if face == null:
		return false
	var stack: Array = face.get("_active_toasts")
	if stack == null:
		return false
	for panel in stack:
		if not is_instance_valid(panel):
			continue
		if _panel_text(panel).findn(needle) != -1:
			return true
	return false


func _face_contains(toast_face: Node, needle: String) -> bool:
	return _stack_contains(toast_face, needle)


func _panel_text(panel: Node) -> String:
	var text := ""
	for child in panel.get_children():
		if child is Label:
			text += str(child.text)
		elif child is Node:
			text += _panel_text(child)
	if panel.has_meta("toast_data"):
		text += str(panel.get_meta("toast_data", {}).get("message", ""))
	return text


func _clear_toasts(tooltip_mgr: Node) -> void:
	# Drop any panels left over from prior steps so each check starts clean.
	var stack: Array = tooltip_mgr.get("_active_toasts")
	if stack == null:
		return
	for p in stack:
		if is_instance_valid(p):
			p.queue_free()
	stack.clear()


func _ok(msg: String) -> void:
	_passed += 1
	print("  [OK] %s" % msg)


func _fail(msg: String) -> void:
	_failed += 1
	printerr("  [FAIL] %s" % msg)


func _print_summary() -> void:
	print("\n=== TEST SUMMARY ===")
	print("Passed: %d" % _passed)
	print("Failed: %d" % _failed)
	if _failed == 0:
		print("RESULT: ALL TESTS PASSED")
	else:
		print("RESULT: %d TESTS FAILED" % _failed)
