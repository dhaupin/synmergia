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
		_world = _setup_headless_hud()
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

	# 2. NotificationService round-trip -- verify notification_sent signal
	#    flows through the HUD and triggers show_toast.
	var notif: Node = root.get_node_or_null("NotificationService")
	if not notif:
		_fail("NotificationService autoload missing")
		return
	_clear_toasts(tooltip_mgr)
	notif.send_to_player("test_player", "Hello via NotificationService")
	await process_frame
	await process_frame
	if _active_toast_count(tooltip_mgr) > 0:
		_ok("NotificationService.send_to_player() -> show_toast() (%d panels)" % _active_toast_count(tooltip_mgr))
	else:
		_fail("Notification never reached show_toast -- HudIntegrator not wired?")

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
			# Force a block: set a tiny max depth, then enter past it.
			guard.set_max_depth("test_toast_ctx", 2)
			var allowed_1: bool = guard.enter("test_toast_ctx")
			var allowed_2: bool = guard.enter("test_toast_ctx")
			var allowed_3: bool = guard.enter("test_toast_ctx")
			await process_frame
			await process_frame
			if allowed_1 and allowed_2 and not allowed_3:
				_ok("RecursionGuard: enter/exit semantics correct (allow, allow, block)")
			else:
				_fail("RecursionGuard semantics wrong: a1=%s a2=%s a3=%s" % [allowed_1, allowed_2, allowed_3])
			if _active_toast_count(tooltip_mgr) > 0:
				_ok("RecursionGuard block -> AppFirewall -> NotificationService -> toast (%d)" % _active_toast_count(tooltip_mgr))
			else:
				_fail("Recursion block didn't reach the toast pipeline")
			guard.exit("test_toast_ctx")
			guard.exit("test_toast_ctx")


func _find_node(root_node: Node, node_name: String) -> Node:
	if root_node.name == node_name:
		return root_node
	for child in root_node.get_children():
		var found: Node = _find_node(child, node_name)
		if found:
			return found
	return null


func _setup_headless_hud() -> Node:
	# Create a minimal test world node with HudLayer and TooltipManager
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
	test_world.add_child(hud)

	# Call _ready to initialize the HUD (installs HudIntegrator, etc.)
	hud.call("_ready")
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
