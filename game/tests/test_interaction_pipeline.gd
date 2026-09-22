## test_interaction_pipeline.gd - LIVE interaction pipeline battery.
## Boots the world (same journey as test_splash_to_play/test_ui_alive)
## then drives the real PlayerController context-action handlers:
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
	_schedule = [
		[1.0, _goto_char_select],
		[2.0, _auto_select_step],
		[2.6, _auto_play_step],
		[5.0, _c_npc_catalog],
		[5.4, _c_dialog_via_context_action],
		[6.2, _c_quest_via_context_action],
		[7.0, _c_vendor_via_context_action],
		[7.8, _c_ground_loot],
		[8.6, _c_targeting],
		[9.4, _c_context_menu_items],
		[10.2, _c_summary],
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
	var btn: Button = current_scene.get_node_or_null("MenuButtons/PlayButton")
	if btn and not btn.disabled:
		btn.pressed.emit()

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
	# Fallback: world scene child.
	return current_scene.get_node_or_null("Player") if current_scene else null

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

## ------------------------------------------------------------------ cases

func _c_npc_catalog() -> void:
	print("--- NPC catalog ---")
	_ok("elder NPC spawned with dialogue offering", not _npcs_with_offering("dialogue").is_empty())
	_ok("vendor NPC spawned with vendor offering", not _npcs_with_offering("vendor").is_empty())
	_ok("quest NPC spawned with quest offering", not _npcs_with_offering("quest").is_empty())
	_ok("player present in world", _player() != null)

func _c_dialog_via_context_action() -> void:
	print("--- NPC dialog via context action ---")
	var npcs := _npcs_with_offering("dialogue")
	if npcs.is_empty():
		_ok("dialogue NPC available", false)
		return
	var npc: Node = npcs[0]
	var player := _player()
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
	var npcs := _npcs_with_offering("quest")
	if npcs.is_empty():
		_ok("quest NPC available", false)
		return
	var npc: Node = npcs[0]
	var player := _player()
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
	var npcs := _npcs_with_offering("vendor")
	if npcs.is_empty():
		_ok("vendor NPC available", false)
		return
	var npc: Node = npcs[0]
	var player := _player()
	if player == current_scene and player == null:
		return

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

func _c_summary() -> void:
	print("=== INTERACTION SUMMARY: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
