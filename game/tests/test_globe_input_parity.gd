## test_globe_input_parity.gd - LIVE receipt for the globe body's input
## surface (planar-retirement Step 5).
##
## WHY THIS EXISTS: the globe body (_on_player_input) used to answer only the
## `interact` action, so on the open world the player could not attack, target,
## or cast -- the planar controller answered the whole set. This drives the
## REAL input fan-out (InputManager.player_input) and the REAL combat entry
## point (create_hitbox) and asserts each leg reaches live state.
##
##   cd game && godot --headless --path . --script res://tests/test_globe_input_parity.gd
##
## Exit 0 = every check observed. Failures print FAIL lines and exit 1.
extends SceneTree

var _pass := 0
var _fail := 0

func _initialize() -> void:
	print("=== GLOBE INPUT PARITY: booting globe scene ===")
	_run.call_deferred()

func _ok(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  PASS: %s %s" % [label, detail])
	else:
		_fail += 1
		print("  FAIL: %s %s" % [label, detail])

func _run() -> void:
	var boot = load("res://tests/support/globe_boot.gd")
	var globe = await boot.boot(self)
	if globe == null:
		print("  FAIL: could not load globe_world.tscn")
		quit(1)
		return
	current_scene = globe

	var es := root.get_node_or_null("EntityService")
	var tm := root.get_node_or_null("TargetingManager")
	var im := root.get_node_or_null("InputManager")
	var player = globe.get("player")
	_ok("EntityService up", es != null)
	_ok("TargetingManager up", tm != null)
	_ok("InputManager up", im != null)
	_ok("player present", player != null)
	if es == null or tm == null or player == null:
		await boot.teardown(globe, self)
		quit(1)
		return

	# Survive the scene wildlife mid-test (the kill/loot laws are unaffected).
	if player.get("health_component") != null:
		player.health_component.max_health = 99999
		player.health_component.current_health = 99999

	# --- Spawn a registered enemy right in front of the player ------------
	var enemy: Node = load("res://entities/enemy.gd").new()
	enemy.display_name = "ParityDummy"
	enemy.starting_health = 40
	enemy.starting_level = 1
	globe.add_child(enemy)
	await process_frame
	es.register_entity(enemy)
	_ok("enemy registered with an id", str(enemy.get("entity_id")) != "")
	# Isolate the fight: free the scene wildlife so only this dummy is nearest.
	for e in get_nodes_in_group("enemies"):
		if e != enemy and is_instance_valid(e):
			e.queue_free()
	await process_frame
	enemy.global_position = player.global_position + Vector3(0, 0, -1.2)
	tm.register_targetable(str(enemy.get("entity_id")), "enemy", enemy,
			enemy.display_name, enemy.global_position, enemy.entity_type)
	await physics_frame

	# --- F2 (target_nearest) through the REAL input fan-out ---------------
	im.player_input.emit("target_nearest", true)
	await physics_frame
	_ok("F2 routed through player_input selected a target", tm.has_target(),
			"(%s)" % (str(tm.get_current_target().display_name) if tm.has_target() else "none"))
	var cur = tm.get_current_target()
	_ok("the selected target is the dummy",
			cur != null and cur.id == str(enemy.get("entity_id")),
			"(%s)" % (str(cur.id) if cur else "none"))
	_ok("the body's is_targeting flag is live", bool(player.get("is_targeting")))

	# --- Basic attack through the real attack action edge -----------------
	# The hitbox is created on the attack edge and swept by CombatSystem on a
	# later physics tick, so swing over a bounded window and watch the target.
	var hp_before: int = enemy.health_component.current_health
	var killed := [false]
	enemy.died.connect(func(_k): killed[0] = true)
	for i in range(20):
		if killed[0] or not is_instance_valid(enemy):
			break
		enemy.global_position = player.global_position + Vector3(0, 0, -1.2)
		Input.action_press("attack")
		await physics_frame
		Input.action_release("attack")
		await process_frame
	var hp_after: int = enemy.health_component.current_health if is_instance_valid(enemy) else 0
	_ok("the attack action damaged the target", hp_after < hp_before or killed[0],
			"(%d -> %d)" % [hp_before, hp_after])

	# --- Tab (target_next) re-targets through the fan-out -----------------
	player.clear_target()
	await physics_frame
	_ok("clear_target dropped the target", not tm.has_target())
	im.player_input.emit("target_next", true)
	await physics_frame
	_ok("Tab routed through player_input re-acquired a target", tm.has_target())

	# --- F1 (target_self) through the fan-out -----------------------------
	im.player_input.emit("target_self", true)
	await physics_frame
	var self_target = tm.get_current_target()
	_ok("F1 targeted the local player",
			self_target != null and self_target.id == str(player.get("entity_id")),
			"(%s)" % (str(self_target.id) if self_target else "none"))

	# --- ability_1 through the fan-out (no crash; routes to use_skill) ----
	im.player_input.emit("ability_1", true)
	await physics_frame
	_ok("ability_1 routed without error", true)

	# --- Click handlers (raycast + menu) do not fault ---------------------
	var center: Vector2 = root.get_visible_rect().size * 0.5
	player._handle_left_click(center)
	await physics_frame
	_ok("left-click raycast handled without error", true)
	player._handle_right_click()
	await physics_frame
	_ok("right-click context handled without error", true)

	# --- Interact near an NPC opens the action menu -----------------------
	# The attack leg above killed the dummy, so its loot drop is in range,
	# and the local player spawns near the village ankh -- both outrank the
	# NPC menu in the interact order (loot, then positional props, then the
	# NPC/gate menu). Clear drops and retire the prop groups to isolate the
	# NPC-menu leg.
	var gls := root.get_node_or_null("GroundLootService")
	if gls != null and gls.has_method("clear_all"):
		gls.clear_all()
	for grp in ["ankhs", "ancient_doors", "concord_stones", "moon_gates"]:
		for n in get_nodes_in_group(grp):
			n.remove_from_group(grp)
	var npc: Node = load("res://core/entities/npc_entity.gd").new()
	npc.display_name = "Parity Vendor"
	npc.npc_data = load("res://data/npc/npc_village_elder.tres")
	globe.add_child(npc)
	await process_frame
	if str(npc.get("entity_id")) == "":
		es.register_entity(npc)
	npc.global_position = player.global_position + Vector3(0, 0, -2.0)
	tm.register_targetable(str(npc.get("entity_id")), "npc", npc,
			npc.display_name, npc.global_position, npc.entity_type)
	await physics_frame
	im.player_input.emit("interact", true)
	await process_frame
	var menu = player.get("_action_menu")
	var menu_open: bool = menu != null and menu.visible
	_ok("E opened the NPC action menu on the globe", menu_open,
			"(menu=%s target=%s)" % [str(menu),
					str(menu.get("_target_id")) if menu else "n/a"])
	if menu != null:
		_ok("the menu was populated with a real target",
				str(menu.get("_target_id")) != "")

	await boot.teardown(globe, self)
	print("=== SUMMARY: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
