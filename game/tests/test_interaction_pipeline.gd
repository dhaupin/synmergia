## test_interaction_pipeline.gd - LIVE interaction pipeline battery.
## Boots the world (same journey as test_splash_to_play/test_ui_alive)
## then drives the real the player body context-action handlers:
##   1. NPC dialog offering -> DialogService.start_dialogue -> DialogUI visible
##   2. NPC quest offering -> Quests panel opens + quest listed
##   3. NPC vendor offering -> ShopUI opens (via ShopUI.open_for_offering)
##   4. Ground loot -> create_drop -> try_pickup returns items
##   5. Targeting: raycast-free target via TargetingManager.set_target
##   6. NPC context menu shows Talk/Quests/Trade/Blacksmith items
##
##   cd game && xvfb-run godot --path . --script res://tests/test_interaction_pipeline.gd
##
## Exit 0 = all checks pass. Failures print FAIL lines and exit 1.
extends SceneTree

const NotifKindConst = preload("res://core/notifications/notification_kind.gd").NotifKind

var _t := 0.0
var _schedule: Array = []  # [ [time, Callable], ... ]
var _pass := 0
var _fail := 0

func _initialize() -> void:
	print("=== INTERACTION PIPELINE TEST ===")
	change_scene_to_file("res://ui/menus/main_menu.tscn")
	# Classic-world content (NPCs, dummies, context menus) lives in the
	# planar scene; pin the shape like play_driver does.
	ProjectSettings.set_setting("synmergia/world/shape", "planar")
	# The single _goto_char_select callable walks the whole round-6
	# journey (Start -> guest -> lobby create -> select), firing the
	# NEXT hop each time it runs -- so schedule it repeatedly.
	_schedule = [
		[1.0, _goto_char_select],
		[1.9, _goto_char_select],
		[2.8, _goto_char_select],
		[3.7, _goto_char_select],
		[4.4, _auto_select_step],
		[4.7, _auto_play_step],
		[5.0, _c_npc_catalog],
		[5.4, _c_dialog_via_context_action],
		[6.2, _c_quest_via_context_action],
		[7.0, _c_vendor_via_context_action],
		[7.8, _c_ground_loot],
		[8.6, _c_targeting],
		[9.4, _c_context_menu_items],
		[10.2, _c_interact_runner],
		[22.0, _c_summary],
	]

func _ok(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  PASS: %s %s" % [label, detail])
	else:
		_fail += 1
		print("  FAIL: %s %s" % [label, detail])

func _process(delta: float) -> bool:
	_t += delta
	while not _schedule.is_empty() and _t >= float(_schedule[0][0]):
		var step: Array = _schedule.pop_front()
		(step[1] as Callable).call()
	return false

## ------------------------------------------------------------------ journey

func _goto_char_select() -> void:
	# Round-6 menu: one Start button -> login guest -> lobby create ->
	# character select (the account creation flow the lobby drives).
	var start_btn: Button = current_scene.get_node_or_null("MenuButtons/StartButton")
	if start_btn and not start_btn.disabled:
		start_btn.pressed.emit()
		return
	if current_scene == null:
		return
	if current_scene.name == "Login":
		var guest: Button = current_scene.get_node_or_null("Center/Panel/Form/Buttons/GuestButton")
		if guest and not guest.disabled:
			guest.pressed.emit()
			return
	if current_scene.name == "Lobby":
		var create: Button = current_scene.get_node_or_null("Center/Panel/VBox/Buttons/CreateButton")
		if create and not create.disabled:
			create.pressed.emit()

func _auto_select_step() -> void:
	if current_scene and current_scene.name == "CharacterSelect" and current_scene.has_method("_auto_select"):
		current_scene._auto_select()

func _auto_play_step() -> void:
	if current_scene and current_scene.has_method("_auto_play"):
		current_scene._auto_play()

## ------------------------------------------------------------------ helpers

func _hud() -> Node:
	return current_scene.get_node_or_null("HudLayer") if current_scene else null

func _player() -> Node:
	var es := root.get_node_or_null("EntityService")
	if es and es.has_method("get_all_entities"):
		for e in es.get_all_entities():
			if is_instance_valid(e) and "is_local_player" in e and e.is_local_player:
				return e
	# Fallback: world scene child (planar "Player") or the globe's scene-node
	# body (`player`).
	if current_scene == null:
		return null
	return current_scene.get_node_or_null("Player") if current_scene.get_node_or_null("Player") else current_scene.get("player")

func _npcs_with_offering(offering_type: String) -> Array:
	var found: Array = []
	var world := current_scene
	if world == null:
		return found
	for npc in world.get_tree().get_nodes_in_group("offering_npcs"):
		if not is_instance_valid(npc) or not ("npc_data" in npc) or npc.npc_data == null:
			continue
		if npc.npc_data.has_method("has_offering") and npc.npc_data.has_offering(offering_type):
			found.append(npc)
	return found

## BOUNDED PLAYER WAIT: the world boot is ASYNC and registers the
## player a couple of seconds after the NPC spawn lands (every headless
## log shows "player registered as ..." arriving AFTER the spawn
## flurry), so fixed schedule slots can fire before the player exists.
## Await the boot (up to max_wait seconds) instead of trusting the
## slot -- the same law the interact runner uses.
func _await_player(max_wait: float) -> Variant:
	var waited := 0.0
	while _player() == null and waited < max_wait:
		await process_frame
		waited += 1.0 / 60.0
	return _player()

## BOUNDED ROSTER WAIT: the globe boots ASYNC and places its town
## NPCs a few seconds in (after the terrain streamer's first faces),
## so the fixed schedule slots can fire while the offering_npcs group
## is still empty. Await the roster instead of trusting the slot.
func _await_offering_npcs(max_wait: float) -> void:
	var waited := 0.0
	while waited < max_wait:
		if current_scene and not current_scene.get_tree().get_nodes_in_group("offering_npcs").is_empty():
			return
		await process_frame
		waited += 1.0 / 60.0

## ------------------------------------------------------------------ cases

func _c_npc_catalog() -> void:
	print("--- NPC catalog ---")
	_ok("elder NPC spawned with dialogue offering", not _npcs_with_offering("dialogue").is_empty())
	_ok("vendor NPC spawned with vendor offering", not _npcs_with_offering("vendor").is_empty())
	_ok("quest NPC spawned with quest offering", not _npcs_with_offering("quest").is_empty())
	var p = await _await_player(5.0)
	_ok("player present in world", p != null)

func _c_dialog_via_context_action() -> void:
	print("--- NPC dialog via context action ---")
	await _await_offering_npcs(6.0)
	var npcs := _npcs_with_offering("dialogue")
	if npcs.is_empty():
		_ok("dialogue NPC available", false)
		return
	var npc: Node = npcs[0]
	var player: Variant = await _await_player(5.0)
	if player == null:
		_ok("player available for dialog", false)
		return

	var dialog: Node = null
	var hud := _hud()
	var mm: Node = hud.get_node_or_null("MenuManager") if hud else null
	if mm:
		dialog = mm.get_node_or_null("DialogUI")
	if dialog == null and hud:
		dialog = hud.get_node_or_null("DialogUI")
	_ok("DialogUI exists in HUD", dialog != null)

	var ds := root.get_node_or_null("DialogService")
	_ok("DialogService autoload exists", ds != null)

	# The NPC may have despawned during the boot wait (the spawn
	# service cycles its roster); re-resolve a LIVE dialogue NPC. The
	# catalog already proved one exists at care-taking time.
	if npc == null or not (is_instance_valid(npc) and "entity_id" in npc):
		var live := _npcs_with_offering("dialogue")
		if not live.is_empty():
			npc = live[0]
	if npc == null or not is_instance_valid(npc):
		_ok("dialogue NPC still live after the boot wait", false)
		return

	# Drive the REAL context action, not the service directly.
	if not player.has_method("_on_context_action"):
		_ok("player has _on_context_action", false)
		return
	player._on_context_action("talk", str(npc.entity_id))
	await process_frame
	await process_frame

	if ds and dialog:
		var svc_ok: bool = ds.has_method("get_current_node") and not ds.get_current_node().is_empty()
		_ok("dialogue_started reached DialogService state", svc_ok)
		var shown: bool = dialog.visible
		_ok("DialogUI visible after Talk action", shown, "(visible=%s)" % str(shown))
		# Close it for subsequent cases.
		if ds.has_method("end_dialogue"):
			ds.end_dialogue()

func _c_quest_via_context_action() -> void:
	print("--- NPC quests via context action ---")
	await _await_offering_npcs(6.0)
	var npcs := _npcs_with_offering("quest")
	if npcs.is_empty():
		_ok("quest NPC available", false)
		return
	var npc: Node = npcs[0]
	var player: Variant = await _await_player(5.0)
	if player == null:
		_ok("player available for quests", false)
		return

	var hud := _hud()
	var mm: Node = hud.get_node_or_null("MenuManager") if hud else null
	_ok("MenuManager present", mm != null)

	var player_script_ok: bool = player.has_method("_on_context_action")
	if not player_script_ok:
		_ok("player has _on_context_action", false)
		return
	player._on_context_action("quest", str(npc.entity_id))
	await process_frame
	await process_frame

	if mm == null:
		return
	var open: Array = mm._open_panels
	_ok("quests panel opens from NPC context action", open.has("quests"),
		"(open=%s)" % str(open))
	# Close for subsequent cases.
	if open.has("quests"):
		mm.close_menu("quests")

func _c_vendor_via_context_action() -> void:
	print("--- NPC vendor via context action ---")
	await _await_offering_npcs(6.0)
	var npcs := _npcs_with_offering("vendor")
	if npcs.is_empty():
		_ok("vendor NPC available", false)
		return
	var npc: Node = npcs[0]
	var player: Variant = await _await_player(5.0)
	if player == null:
		_ok("player available for vendor", false)
		return

	# Stand at the stall: the shop runs a walk-away close (12 m), so a
	# real trade happens with the player beside the vendor. Park on the
	# vendor's radial (globe-honest) before triggering the trade.
	if npc is Node3D:
		var vpos: Vector3 = (npc as Node3D).global_position
		player.global_position = vpos + vpos.normalized() * 0.8
		player.velocity = Vector3.ZERO

	# The vendor branch needs _current_target_info to route the NPC trade
	# action to the shop; emulate the context-menu flow by setting the
	# target through TargetingManager first (same as a real long-press).
	var tm := root.get_node_or_null("TargetingManager")
	if tm == null:
		_ok("TargetingManager present", false)
		return
	tm.set_target(str(npc.entity_id), "npc", str(npc.display_name),
		npc.global_position if npc is Node3D else Vector3.ZERO, npc,
		4)  # Entity.EntityType.NPC

	if not player.has_method("_on_context_action"):
		_ok("player has _on_context_action", false)
		return
	player._on_context_action("trade", str(npc.entity_id))
	await process_frame
	await process_frame

	# ShopUI.open_for_offering parents the instance to the root Window.
	var shop: Node = null
	for child in root.get_children():
		if child.get_script() != null and child.get_script().resource_path.ends_with("shop_ui.gd"):
			shop = child
			break
	_ok("ShopUI opened via NPC trade action", shop != null and shop.visible,
		"(found=%s)" % str(shop != null))
	if shop and shop.has_method("close"):
		shop.close()

func _c_ground_loot() -> void:
	print("--- ground loot pickup ---")
	var gls := root.get_node_or_null("GroundLootService")
	var player := _player()
	if gls == null or player == null:
		_ok("GroundLootService + player present", false)
		return

	var items: Array = [{"item_id": "potion_health_small", "quantity": 2}]
	var pos: Vector3 = player.global_position + Vector3(1.5, 0.5, 0.0)
	var drop_id: String = gls.create_drop(pos, items, {"source": "test"})
	_ok("drop created", drop_id != "")

	var picked: Array = gls.try_pickup(player, drop_id)
	_ok("try_pickup returns items", not picked.is_empty(),
		"(%d items)" % picked.size())

	# world_playable should have cleared the minimap marker via the
	# ground_loot_picked_up signal.
	await process_frame
	await process_frame

func _c_targeting() -> void:
	print("--- targeting via TargetingManager ---")
	var tm := root.get_node_or_null("TargetingManager")
	if tm == null:
		_ok("TargetingManager present", false)
		return
	var es := root.get_node_or_null("EntityService")
	var enemies: Array = []
	if es and es.has_method("get_all_entities"):
		for e in es.get_all_entities():
			if is_instance_valid(e) and "entity_type" in e and int(e.entity_type) == 2:
				enemies.append(e)
	_ok("enemy present for targeting", not enemies.is_empty())
	if enemies.is_empty():
		return
	var target: Node = enemies[0]
	tm.set_target(str(target.entity_id), "enemy", str(target.display_name),
		target.global_position if target is Node3D else Vector3.ZERO, target, 2)
	var cur = tm.get_current_target()
	_ok("target acquired", cur != null and str(cur.id) == str(target.entity_id),
		"(id=%s)" % (str(cur.id) if cur else "none"))
	tm.clear_target()

func _c_context_menu_items() -> void:
	print("--- ActionMenu NPC filtering ---")
	var menu_script: Script = load("res://ui/components/action_menu.gd")
	var menu_instance: Node = menu_script.new()
	root.add_child(menu_instance)
	var npcs := _npcs_with_offering("dialogue")
	if npcs.is_empty():
		menu_instance.queue_free()
		_ok("dialogue NPC for menu test", false)
		return
	var npc: Node = npcs[0]
	menu_instance.show_menu_for_npc(Vector2(200, 200),
		str(npc.entity_id), npc.npc_data)
	var item_texts: Array = []
	for btn in menu_instance._item_buttons:
		item_texts.append(str(btn.text))
	var has_talk: bool = false
	for txt in item_texts:
		if str(txt).contains("Talk"):
			has_talk = true
	_ok("menu shows Talk for dialogue NPC", has_talk, "(items=%s)" % str(item_texts))
	menu_instance.close()
	menu_instance.queue_free()

## THE WALK-UP-AND-PRESS LOOP runner. The world boot is ASYNC (player
## registration lands a couple of seconds after the NPC spawn, see the
## round-22 audit), so the three cases wait for the player BEFORE the
## presses fire instead of trusting a fixed schedule gap.
var _interact_ran := false

func _c_interact_runner() -> void:
	if _interact_ran:
		return
	_interact_ran = true
	var waited := 0.0
	while _player() == null and waited < 8.0:
		await process_frame
		waited += 1.0 / 60.0
	if _player() == null:
		_ok("player booted for the interact run", false)
		return
	await _c_interact_menu_npc()
	await _c_interact_menu_gate()
	await _c_interact_range()

## THE WALK-UP-AND-PRESS LOOP (E / ACT button -> menu): put the player
## beside an NPC, fire the REAL _on_player_input path the E key and
## the touch ACT button both converge on, and expect the nearest NPC
## targeted + ITS action menu shown centered (no cursor needed).
func _c_interact_menu_npc() -> void:
	print("--- interact: walk up to NPC, press action ---")
	var player := _player()
	var tm := root.get_node_or_null("TargetingManager")
	if player == null or tm == null:
		_ok("player + TargetingManager present", false)
		return
	var npcs := _npcs_with_offering("dialogue")
	if npcs.is_empty():
		_ok("dialogue NPC available", false)
		return
	var npc: Node = npcs[0]
	tm.clear_target()
	# Stand IN range, beside the NPC (the walk-up part of the loop).
	player.global_position = _npc_ground_pos(npc) + Vector3(1.5, 0, 0)
	var before_menu: Node = player.get("_action_menu")
	if before_menu != null and is_instance_valid(before_menu):
		before_menu.hide()

	# The shared press path: both E (player_input) and the ACT button
	# land here. Fire the handler exactly as InputManager routes it
	# (press edge, then the release edge a real button sends).
	player._on_player_input("interact", true)
	player._on_player_input("interact", false)
	await process_frame
	await process_frame

	var menu: Node = player.get("_action_menu")
	_ok("action menu opened via interact", menu != null and is_instance_valid(menu) and menu.visible)
	var cur = tm.get_current_target()
	_ok("NPC targeted by proximity", cur != null and str(cur.id) == str(npc.entity_id),
		"(target=%s npc=%s)" % [str(cur.id if cur else "none"), str(npc.entity_id)])
	var texts: Array = []
	if menu != null and is_instance_valid(menu):
		for btn in menu._item_buttons:
			texts.append(str(btn.text))
	var has_talk := false
	for txt in texts:
		if str(txt).contains("Talk"):
			has_talk = true
	_ok("menu offers Talk for the NPC", has_talk, "(items=%s)" % str(texts))
	# THE VISUAL TARGET INDICATOR: set_target seated the pulsing ring
	# mesh at the NPC's feet ("Highlights/TargetingHighlight"). Assert
	# the mesh truth headless: node alive, visible, and re-seated ON
	# the NPC transform (the _process tracker keeps it there).
	var ring := root.find_child("TargetingHighlight", true, false)
	_ok("target ring exists and is visible", ring != null and tm.is_highlight_visible())
	await process_frame
	var ring_pos_ok := false
	if ring != null and ring is Node3D:
		ring_pos_ok = (ring as Node3D).global_position.distance_to(_npc_ground_pos(npc)) < 1.5
	_ok("target ring seated under the NPC", ring_pos_ok)
	if menu != null and is_instance_valid(menu):
		menu.hide()

## A gate (registered TELEPORT targetable, e.g. the dungeon portal in
## this scene) opens its Enter menu through the same resolve.
func _c_interact_menu_gate() -> void:
	print("--- interact: walk up to a gate, press action ---")
	var player := _player()
	var tm := root.get_node_or_null("TargetingManager")
	if player == null or tm == null:
		_ok("player + TargetingManager present", false)
		return
	var gates: Array = tm.get_targetables_by_type(32)  # Entity.EntityType.TELEPORT
	# The scene registers several TELEPORT targetables: the dungeon
	# portal (a plain gateway -> "Enter") and the arena queue stones
	# (queue_mode -> Queue/Leave/Lobby). This leg proves the walk-up
	# ENTER path, so pick a non-queue gateway rather than trusting
	# list order (the arena stone is registered first).
	var gate_id := ""
	var node: Node = null
	for g in gates:
		var gd: Dictionary = tm.get_targetable(str(g))
		var gn = gd.get("node", null)
		if gn == null or not is_instance_valid(gn):
			continue
		if "queue_mode" in gn and bool(gn.queue_mode):
			continue
		if gn.is_in_group("ankhs"):
			continue  # ankhs bind, they do not Enter
		gate_id = str(g)
		node = gn
		break
	if node == null:
		_ok("gateway targetable present in scene", false)
		return
	tm.clear_target()
	var gpos: Vector3 = (node as Node3D).global_position
	player.global_position = gpos + gpos.normalized() * 0.5
	player.velocity = Vector3.ZERO
	var menu: Node = player.get("_action_menu")
	if menu != null and is_instance_valid(menu):
		menu.hide()

	player._on_player_input("interact", true)
	player._on_player_input("interact", false)
	await process_frame
	await process_frame

	var cur = tm.get_current_target()
	_ok("gate targeted by proximity", cur != null and str(cur.id) == gate_id,
		"(target=%s gate=%s)" % [str(cur.id if cur else "none"), gate_id])
	menu = player.get("_action_menu")
	_ok("gate action menu opened", menu != null and is_instance_valid(menu) and menu.visible)
	var texts: Array = []
	if menu != null and is_instance_valid(menu):
		for btn in menu._item_buttons:
			texts.append(str(btn.text))
	var has_enter := false
	for txt in texts:
		if str(txt).contains("Enter"):
			has_enter = true
	_ok("menu offers Enter for the gate", has_enter, "(items=%s)" % str(texts))
	# Choose Enter? NO: a real activation warps the zone -- the menu
	# itself is the beat under test. Close and leave the world intact.
	if menu != null and is_instance_valid(menu):
		menu.hide()
	tm.clear_target()

## Out of range: the resolver must NOT menu (or target) anything.
func _c_interact_range() -> void:
	print("--- interact: range respected ---")
	var player := _player()
	var tm := root.get_node_or_null("TargetingManager")
	if player == null or tm == null:
		_ok("player + TargetingManager present", false)
		return
	var npcs := _npcs_with_offering("dialogue")
	if npcs.is_empty():
		_ok("dialogue NPC available", false)
		return
	var npc: Node = npcs[0]
	tm.clear_target()
	var menu: Node = player.get("_action_menu")
	if menu != null and is_instance_valid(menu):
		menu.hide()

	# 40 m out: beyond the 6 m interact arm.
	player.global_position = _npc_ground_pos(npc) + Vector3(40, 0, 0)
	player._try_interact()
	await process_frame
	await process_frame

	menu = player.get("_action_menu")
	var shown: bool = menu != null and is_instance_valid(menu) and menu.visible
	_ok("out-of-range press opens no menu", not shown)
	var cur = tm.get_current_target()
	_ok("out-of-range press sets no target", cur == null or str(cur.id) == "")
	tm.clear_target()
	_ok("target ring hidden after clear", not tm.is_highlight_visible())

## NPCs anchor on the walk line; drop the probe onto their own Y.
func _npc_ground_pos(npc: Node) -> Vector3:
	return (npc as Node3D).global_position if npc is Node3D else Vector3.ZERO

func _c_summary() -> void:
	print("=== INTERACTION SUMMARY: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
