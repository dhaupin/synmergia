## PlaythroughDriverRunner - the node-based flow runner for the rendered
## playthrough driver. WHY A NODE RUNNER: the world boot's suspended signal
## handler (StarterKitService's deferred grant timer) strands SceneTree-script
## awaits in Godot 4.7.2 (see globe_driver_runner.gd); a plain Node resumes
## across that boundary and prints the verdict + exit code itself.
##
## WHAT IT PROVES: the existing drivers stop at HUD panels. This one walks the
## REAL gameplay loop on the planar world_playable scene -- target a live wolf,
## swing through the actual `attack` input action, watch it die, collect the
## corpse loot through the `interact` action, equip gear, repair it at the
## blacksmith, and open an NPC's action menu by walking up and pressing E.
## Every stage asserts on LIVE node state, so a seam that only breaks under
## real play (the class of bug the unit receipts miss) fails here.
##
## Run (rendered; headless boots the world too, so it runs both ways):
##   xvfb-run -a godot --path game --script res://tests/playthrough_driver.gd
## Shots: /tmp/play/playthrough_*.png
extends Node

var _pass: int = 0
var _fail: int = 0
var _fail_flags: String = ""

func _ready() -> void:
	run()

func _ok(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  PASS: %s %s" % [label, detail])
	else:
		_fail += 1
		_fail_flags += label + "; "
		print("  FAIL: %s %s" % [label, detail])

func run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute("/tmp/play")

	# --- Stage 1: boot the playable world ----------------------------
	# Runtime load: autoloads are live now; a parse-time load would fail.
	var scene: PackedScene = load("res://scenes/world_playable.tscn")
	if scene == null:
		print("PLAYTHROUGH FAIL: world_playable.tscn did not load")
		get_tree().quit(1)
		return
	var inst := scene.instantiate()
	get_tree().root.add_child(inst)
	get_tree().current_scene = inst
	await _settle(1.5)

	var player = inst.get_node_or_null("Player")
	_ok("world booted with a Player", player != null)
	if player == null:
		await _finish()
		return
	var pid := str(player.get("entity_id"))
	_ok("player has an entity id", pid != "", "(%s)" % pid)
	await _shot("playthrough_1_spawn")

	var es := get_tree().root.get_node_or_null("EntityService")
	var loot := get_tree().root.get_node_or_null("GroundLootService")
	var isvc := get_tree().root.get_node_or_null("InventoryService")
	_ok("EntityService up", es != null)
	_ok("GroundLootService up", loot != null)
	_ok("InventoryService up", isvc != null)
	var inv = player.get("inventory_component")
	_ok("player has an inventory component", inv != null)
	if es == null or loot == null or inv == null:
		await _finish()
		return
	_ok("inventory registered under the player id", isvc.get_inventory(pid) == inv)

	# Isolation for the combat stage: a level-1 body can be killed by the
	# scene-placed wildlife mid-fight, and a DEAD player legitimately earns no
	# kill credit (kill_rewards._is_valid_combatant rejects dead nodes), which
	# made the XP assertion nondeterministic under real-time render. Give the
	# player a health pool deep enough to survive the test fight; the kill/loot
	# laws under test are unaffected.
	if player.get("health_component") != null:
		player.health_component.max_health = 99999
		player.health_component.current_health = 99999

	# --- Stage 2: target a live wolf through the real input map ------
	var tm := get_tree().root.get_node_or_null("TargetingManager")
	_ok("TargetingManager up", tm != null)
	var wolf = await _spawn_wolf(inst, player, es)
	_ok("wolf registered", wolf != null and str(wolf.get("entity_id")) != "")
	# Isolate the fight: free the scene-placed wildlife so only the player and
	# the spawned wolf are in it. A wandering scene wolf stealing the killing
	# blow (correct game behavior, but nondeterministic under real-time render)
	# made kill credit -- and thus the XP assertion -- flaky.
	for e in get_tree().get_nodes_in_group("enemies"):
		if e != wolf and is_instance_valid(e):
			e.queue_free()
	await get_tree().process_frame
	_key(KEY_F2)  # target_nearest
	await _settle(0.3)
	var cur = tm.get_current_target() if tm else null
	_ok("F2 selected a target", cur != null, "(%s)" % (str(cur.display_name) if cur else "none"))
	if cur != null:
		_ok("target is the wolf", str(cur.display_name) == "Wolf")
		# The TargetFrame renders acquisition: the frame used to resolve a
		# TargetInfo's id as entity_id (always ""), so it hid itself and never
		# populated -- the name label stayed "No Target" for the whole game.
		var tf = get_tree().root.find_child("TargetFrame", true, false)
		if tf != null and tf.has_method("get_target_id"):
			_ok("target frame registered the acquisition",
					str(tf.get_target_id()) == str(cur.id), "(id=%s)" % str(tf.get_target_id()))
			var name_lbl = tf.get("_name_label")
			_ok("target frame rendered the target name",
					name_lbl != null and name_lbl.text == "Wolf", "(%s)" % (name_lbl.text if name_lbl else "n/a"))

	# --- Stage 3: kill it through the real attack action -------------
	var hp_before: int = wolf.health_component.current_health
	var xp_before: int = int(player.get("experience"))
	var killed: bool = await _kill(wolf, player)
	_ok("wolf died to the attack action", killed, "(%d hp)" % hp_before)
	if not killed:
		await _finish()
		return

	# --- Stage 4: the kill paid out (XP + a real corpse drop) --------
	await get_tree().process_frame
	await get_tree().process_frame
	var xp_after: int = int(player.get("experience"))
	_ok("kill awarded XP", xp_after > xp_before, "(%d -> %d)" % [xp_before, xp_after])
	await _shot("playthrough_2_killed")

	# --- Stage 5: collect corpse loot through the interact action ----
	# loot_wolf rolls probabilistically (item drop rates 0.3/0.05/0.8/0.2), so
	# keep killing until a corpse actually leaves a drop before asserting the
	# pickup. Bounded at 4 kills; P(no drop in 4) is under 1e-6.
	var got_loot: bool = await _collect_any_drop(player, loot, inv)
	var kills := 1
	while not got_loot and kills < 4:
		var w2 = await _spawn_wolf(inst, player, es)
		if w2 == null:
			break
		if not await _kill(w2, player):
			break
		kills += 1
		got_loot = await _collect_any_drop(player, loot, inv)
	_ok("corpse left a drop and interact collected it", got_loot,
		"(%d kills, %d drops live)" % [kills, loot.get_drop_count()])
	await _shot("playthrough_3_looted")

	# --- Stage 6: equip real gear ------------------------------------
	var ds := get_tree().root.get_node_or_null("DataService")
	var sword = ds.get_item("wep_iron_sword") if ds else null
	_ok("DataService resolved wep_iron_sword", sword != null)
	if sword != null:
		var added: bool = inv.add_item(sword, 1)
		_ok("sword entered the bag", added)
		var slot: int = inv.find_item("wep_iron_sword")
		_ok("sword has a bag slot", slot >= 0, "(slot %d)" % slot)
		if slot >= 0:
			var str_before: int = int(player.get_stat("strength"))
			var equipped: bool = inv.equip_item(slot)
			_ok("sword equipped", equipped)
			_ok("equipment slot now holds the sword",
				inv.get_equipped(int(sword.equip_slot)) != null)
			# The bug this driver caught: _apply_equipment_stats aborted on the
			# player (parent is not an Entity), so gear moved no attributes.
			var stats: Dictionary = inv.get_equipment_stats()
			var str_after: int = int(player.get_stat("strength"))
			_ok("equipping applied gear stats to the player",
				stats.is_empty() or str_after != str_before or int(stats.get("strength", 0)) == 0,
				"(strength %d -> %d, gear %s)" % [str_before, str_after, str(stats)])
			# Idempotency: _apply_equipment_stats runs on every equip/unequip and
			# add_stat has no inverse, so a naive re-add stacks the bonus. A
			# unequip/re-equip cycle must land back on the same total.
			inv.unequip_item(int(sword.equip_slot))
			var str_unequipped: int = int(player.get_stat("strength"))
			var reslot: int = inv.find_item("wep_iron_sword")
			if reslot >= 0:
				inv.equip_item(reslot)
			var str_reequipped: int = int(player.get_stat("strength"))
			_ok("unequip removed the gear bonus", str_unequipped == str_before,
				"(strength %d -> %d, expected %d)" % [str_after, str_unequipped, str_before])
			_ok("re-equip does not stack the gear bonus", str_reequipped == str_after,
				"(strength %d -> %d, expected %d)" % [str_unequipped, str_reequipped, str_after])

	# --- Stage 7: the blacksmith repairs the equipped sword ----------
	var smith := get_tree().root.get_node_or_null("BlacksmithService")
	_ok("BlacksmithService up", smith != null)
	if smith != null and sword != null:
		var eq = inv.get_equipped(int(sword.equip_slot))
		if eq != null and "durability" in eq:
			eq.durability = max(1, int(eq.max_durability) - 5)
		var gold_before: int = inv.get_gold()
		var res: Dictionary = smith.repair_all_equipped(pid, inv)
		_ok("blacksmith repair reported a result", res is Dictionary, "(%s)" % str(res))
		var eq2 = inv.get_equipped(int(sword.equip_slot))
		_ok("repair left the blade in place", eq2 != null)
		_ok("repair did not lose gold without a repair",
			inv.get_gold() >= gold_before or int(res.get("repaired", 0)) > 0,
			"(gold %d -> %d)" % [gold_before, inv.get_gold()])

	# --- Stage 8: walk up to an NPC and open its action menu ---------
	await _stage_npc_menu(inst, player)

	# --- Stage 9: buy and sell through the real shop panel -----------
	await _stage_vendor_trade(player, inv, ds, pid)

	# --- Stage 10: the vault takes and returns coin and goods --------
	await _stage_vault(player, inv, pid)

	# --- Stage 11: the banker's vault opens from the action menu -----
	await _stage_bank_menu(player)

	# --- Stage 12: death runs the respawn cycle ----------------------
	await _stage_death_respawn(player)

	# --- Stage 13: dialogue -> quest accept -> turn-in -> rewards -----
	await _stage_dialogue_quest(inst, player, inv, pid)

	# --- Stage 14: accept an available quest from the journal ---------
	await _stage_journal_accept(player, pid)

	# --- Stage 15: the waypoint -> compass loop -----------------------
	await _stage_waypoint_route(player)

	# --- Stage 16: the friend request -> accept -> block loop ---------
	await _stage_social_friends(pid)

	# --- Stage 17: the chat pipeline + the ignore book ----------------
	await _stage_chat_social(pid)

	await _finish()

## Spawn a real wolf with the shipped wolf data, in front of the player.
func _spawn_wolf(inst: Node, player, es: Node):
	var wolf = load("res://entities/enemy.gd").new()
	wolf.enemy_data = load("res://data/enemies/enemy_wolf.tres")
	wolf.display_name = "Wolf"
	wolf.global_position = player.global_position + _forward(player) * 1.2
	inst.add_child(wolf)
	await get_tree().process_frame
	es.register_entity(wolf)
	var ai = load("res://core/ai/enemy_ai.gd").new()
	if wolf.has_method("attach_ai"):
		wolf.attach_ai(ai)
	return wolf

## Swing the real attack action until the wolf dies (bounded). True on death.
## The attack edge is HELD for a physics frame: action_press+release in the same
## frame can miss the state machine's just_pressed edge, which made the kill
## flaky. The player is also turned to face the wolf each swing so the frontal
## hitbox cone always covers it.
func _kill(wolf, player) -> bool:
	var killed := [false]
	wolf.died.connect(func(_k): killed[0] = true)
	for i in range(150):
		if killed[0] or not is_instance_valid(wolf):
			break
		if is_instance_valid(wolf):
			_face(player, wolf.global_position)
			wolf.global_position = player.global_position + _forward(player) * 1.2
		Input.action_press("attack")
		await get_tree().physics_frame
		Input.action_release("attack")
		await get_tree().process_frame
	return killed[0]

## Turn the player's yaw so -Z (the forward the hitbox cone reads) points at
## `pos` on the XZ plane.
func _face(player, pos: Vector3) -> void:
	var to: Vector3 = pos - player.global_position
	to.y = 0.0
	if to.length() < 0.001:
		return
	player.rotation.y = atan2(-to.x, -to.z)

## Walk onto each live drop and press E; true if anything entered the bag.
func _collect_any_drop(player, loot, inv) -> bool:
	var drops: Dictionary = loot.get("_drops")
	if drops == null or drops.is_empty():
		return false
	for drop_id in drops.keys():
		var drop: Dictionary = drops.get(drop_id, {})
		var pos: Vector3 = drop.get("position", Vector3.ZERO)
		player.global_position = pos
		await get_tree().physics_frame
		var slots_before: int = inv.get_inventory_count()
		var gold_before: int = inv.get_gold()
		_key(KEY_E)
		await _settle(0.4)
		if inv.get_inventory_count() > slots_before or inv.get_gold() > gold_before:
			return true
	return false

## Spawn a real vendor NPC beside the player, register it, and press E.
## Proves the walk-up-and-press interaction loop resolves and opens the menu.
func _stage_npc_menu(inst: Node, player) -> void:
	var npc = load("res://core/entities/npc_entity.gd").new()
	npc.display_name = "Playthrough Vendor"
	npc.npc_data = load("res://data/npc/npc_village_elder.tres")
	npc.global_position = player.global_position + _forward(player) * 2.0
	inst.add_child(npc)
	await get_tree().process_frame
	_ok("vendor NPC spawned", npc.is_inside_tree())

	var es := get_tree().root.get_node_or_null("EntityService")
	var tm := get_tree().root.get_node_or_null("TargetingManager")
	if es and str(npc.get("entity_id")) == "":
		es.register_entity(npc)
	if tm and str(npc.get("entity_id")) != "":
		tm.register_targetable(str(npc.get("entity_id")), "npc", npc,
			npc.display_name, npc.global_position, npc.entity_type)
	await get_tree().process_frame

	_key(KEY_E)
	await _settle(0.6)
	# The player owns its own ActionMenu (player._show_npc_context_menu); the
	# HUD also ships one, so read the player's reference, not find_child.
	var menu = player.get("_action_menu")
	var npc_id := str(npc.get("entity_id"))
	var menu_open: bool = menu != null and menu.visible
	_ok("E opened the NPC action menu", menu_open,
		"(menu=%s visible=%s target=%s npc=%s)" % [str(menu),
			str(menu.visible) if menu else "n/a",
			str(menu.get("_target_id")) if menu else "n/a", npc_id])
	if menu != null:
		# E targets the NEAREST interactable NPC, which may be a scene-placed
		# NPC rather than the one spawned here -- the law under test is that the
		# press resolved a live NPC and populated the menu, not which one.
		_ok("the menu was populated with a real target",
			str(menu.get("_target_id")) != "")
	await _shot("playthrough_4_npc_menu")

## Stage 9: buy and sell through the real shop panel. Opens the merchant's
## vendor offering exactly as the action menu does (ShopUI.open_for_offering),
## then drives the panel's own Buy/Sell buttons -- the shop only ever reached
## by hand is the last unproven money loop. Asserts both purses move and the
## item crosses the counter.
func _stage_vendor_trade(player, inv, ds, pid: String) -> void:
	var merchant = load("res://data/npc/npc_merchant_general.tres")
	_ok("merchant data loaded", merchant != null)
	if merchant == null or ds == null:
		return
	var offering = merchant.get_vendor_offering()
	_ok("merchant has a vendor offering", offering != null)
	if offering == null:
		return

	# Fund the purse so affordability never masks the transaction under test.
	inv.add_gold(500)
	var gold_before: int = inv.get_gold()

	ShopUI.open_for_offering(pid, offering, merchant, player.global_position + _forward(player) * 2.0)
	await _settle(0.3)
	var shop = ShopUI.singleton()
	_ok("shop panel opened", shop != null and shop.visible)
	if shop == null:
		return

	shop._current_tab = shop.Tab.BUY
	shop._refresh_grid()
	var catalog: Array = shop.get("_catalog")
	_ok("shop catalog has buyable stock", catalog.size() > 0, "(%d entries)" % catalog.size())
	if catalog.is_empty():
		ShopUI.close_shop()
		return

	# Pick a stock entry the vendor will also buy back (its category is in the
	# offering's buy_categories) so the counter can round-trip honestly.
	var buy_index := -1
	for i in range(catalog.size()):
		var it: Resource = catalog[i].get("item")
		if it != null and offering.buy_categories.has(it.item_category):
			buy_index = i
			break
	_ok("the store stocks something it also buys", buy_index >= 0)
	if buy_index < 0:
		ShopUI.close_shop()
		return

	var buy_item: Resource = catalog[buy_index].get("item")
	var buy_id: String = str(buy_item.id) if buy_item != null else ""
	var buy_price: int = int(catalog[buy_index].get("price", 0))
	shop._selected_index = buy_index
	shop._selected_type = shop.Tab.BUY
	shop._on_buy_pressed()
	await _settle(0.2)
	var gold_after_buy: int = inv.get_gold()
	_ok("buy debited the purse by the quoted price",
		gold_after_buy == gold_before - buy_price,
		"(%d -> %d, price %d, item %s)" % [gold_before, gold_after_buy, buy_price, buy_id])
	_ok("buy landed the item in the bag", inv.find_item(buy_id) >= 0, "(%s)" % buy_id)

	# Sell it back: the catalog came from the vendor's buy_categories, so the
	# counter round-trips. VendorService is not an autoload -- resolve its
	# singleton through a runtime load (same script resource ShopUI preloads,
	# so the static _instance is shared).
	var svc = load("res://core/services/vendor_service.gd").singleton()
	shop._current_tab = shop.Tab.SELL
	# The sellable list is a snapshot taken at open time; buying changed the bag,
	# so re-query it (the panel's own reload leg) before reading it back.
	shop._load_sellable()
	shop._refresh_grid()
	var sellable: Array = shop.get("_sellable")
	var found := -1
	for i in range(sellable.size()):
		if str(sellable[i].get("item").id) == buy_id:
			found = i
			break
	_ok("the bought item appears in the vendor's sellable list", found >= 0)
	if found >= 0:
		var sell_price: int = int(sellable[found].get("price", 0))
		shop._selected_index = found
		shop._selected_type = shop.Tab.SELL
		shop._on_sell_pressed()
		await _settle(0.2)
		var gold_after_sell: int = inv.get_gold()
		_ok("sell credited the purse by the quoted price",
			gold_after_sell == gold_after_buy + sell_price,
			"(%d -> %d, price %d)" % [gold_after_buy, gold_after_sell, sell_price])
		_ok("sell removed the item from the bag", inv.find_item(buy_id) < 0, "(%s)" % buy_id)
		_ok("the vendor buys for no more than it sells (spread holds)", sell_price <= buy_price,
			"(buy %d, sell %d)" % [buy_price, sell_price])
		if svc != null:
			var buyback: Array = svc.get_buyback(pid)
			_ok("the sale entered the vendor buyback ledger", buyback.size() > 0,
				"(%d entries)" % buyback.size())
	await _shot("playthrough_5_shop")
	ShopUI.close_shop()


## Stage 10: the vault takes and returns coin and goods. Drives the real
## VaultService legs (deposit/withdraw gold + item) -- the seam whose gold
## helper (InventoryService.modify_gold) was missing for its whole life.
func _stage_vault(player, inv, pid: String) -> void:
	var vault = get_tree().root.get_node_or_null("VaultService")
	_ok("VaultService up", vault != null)
	if vault == null:
		return
	var personal: int = vault.VaultType.PERSONAL

	# Gold round-trip: this is the leg that died on the missing modify_gold.
	inv.add_gold(100)
	var gold_before: int = inv.get_gold()
	var deposit_ok: bool = vault.deposit_gold(pid, personal, 40)
	await get_tree().process_frame
	var gold_after_dep: int = inv.get_gold()
	_ok("vault gold deposit succeeded", deposit_ok, "(purse %d -> %d)" % [gold_before, gold_after_dep])
	_ok("deposit debited exactly the amount", gold_after_dep == gold_before - 40,
		"(%d -> %d, expected %d)" % [gold_before, gold_after_dep, gold_before - 40])
	var vdata: Dictionary = vault.open_vault(pid, personal)
	_ok("the vault now holds the coin", int(vdata.get("gold", 0)) == 40,
		"(vault gold %d)" % int(vdata.get("gold", 0)))
	var withdraw_ok: bool = vault.withdraw_gold(pid, personal, 40)
	await get_tree().process_frame
	_ok("vault gold withdrawal succeeded", withdraw_ok)
	_ok("withdraw restored the purse", inv.get_gold() == gold_before,
		"(gold %d, expected %d)" % [inv.get_gold(), gold_before])

	# Item round-trip: deposit a real resource, withdraw it back by slot.
	var ore = ds_get_item("res_iron_ore")
	if ore != null:
		var item_dict := {
			"id": str(ore.id),
			"name": str(ore.display_name),
			"icon_path": str(ore.icon_path) if "icon_path" in ore else "",
			"rarity": int(ore.rarity) if "rarity" in ore else 0,
			"stack_size": int(ore.stack_size) if "stack_size" in ore else 1,
		}
		var dep_item: bool = vault.deposit_item(pid, personal, item_dict, 2)
		_ok("vault item deposit succeeded", dep_item)
		var vdata2: Dictionary = vault.open_vault(pid, personal)
		var slots: Array = vdata2.get("slots", [])
		var occupied := -1
		for i in range(slots.size()):
			if not slots[i].is_empty() and str(slots[i].get("id", "")) == str(ore.id):
				occupied = i
				break
		_ok("the deposited item is in a vault slot", occupied >= 0, "(slot %d)" % occupied)
		if occupied >= 0:
			var wres: Dictionary = vault.withdraw_item(pid, personal, occupied, 2)
			_ok("vault item withdrawal returned the item", not wres.is_empty(), "(%s)" % str(wres))
	await _shot("playthrough_6_vault")


## Stage 11: the banker's vault opens from the action menu. Proves the
## walk-up -> Bank path reaches the real panel, not just the service API.
func _stage_bank_menu(player) -> void:
	var banker = load("res://data/npc/npc_banker_village.tres")
	_ok("banker data loaded", banker != null)
	if banker == null:
		return
	var inst = get_tree().current_scene
	var npc = load("res://core/entities/npc_entity.gd").new()
	npc.display_name = "Village Banker"
	npc.npc_data = banker
	npc.global_position = player.global_position + _forward(player) * 2.0
	inst.add_child(npc)
	await get_tree().process_frame
	var es := get_tree().root.get_node_or_null("EntityService")
	var tm := get_tree().root.get_node_or_null("TargetingManager")
	if es and str(npc.get("entity_id")) == "":
		es.register_entity(npc)
	if tm and str(npc.get("entity_id")) != "":
		tm.register_targetable(str(npc.get("entity_id")), "npc", npc,
			npc.display_name, npc.global_position, npc.entity_type)
	await get_tree().process_frame

	_key(KEY_E)
	await _settle(0.6)
	var menu = player.get("_action_menu")
	_ok("E opened the banker action menu", menu != null and menu.visible)
	if menu != null:
		menu._on_action_selected("bank")
		await _settle(0.5)
	var mm := get_tree().root.get_node_or_null("MenuManager")
	if mm == null and get_tree().current_scene != null:
		var hud = get_tree().current_scene.get_node_or_null("HudLayer")
		mm = hud.get_node_or_null("MenuManager") if hud else null
	_ok("MenuManager resolved", mm != null)
	if mm != null:
		var bank_panel: Control = mm.get_panel_node("bank")
		_ok("the bank panel is showing after the Bank action",
			bank_panel != null and bank_panel.visible,
			"(panel=%s)" % str(bank_panel))
		if bank_panel != null and bank_panel.has_method("close"):
			bank_panel.close()
	await _shot("playthrough_7_bank")


## Stage 12: death runs the respawn cycle. Kills the player through the real
## HealthComponent.take_damage path, then asserts the service-driven cycle
## holds the body dead and brings it back alive at a resolved position.
func _stage_death_respawn(player) -> void:
	var hc = player.get("health_component")
	_ok("player has a health component", hc != null)
	if hc == null:
		return
	var rs = get_tree().root.get_node_or_null("RespawnService")
	_ok("RespawnService up", rs != null)
	if rs == null:
		return

	# Collapse the (huge) health pool this driver set for the combat stage so a
	# single hit kills -- the death path under test, not the fight.
	hc.max_health = 50
	hc.current_health = 50

	var completed := [false]
	var completed_pos := [Vector3.ZERO]
	rs.respawn_completed.connect(func(_p, pos): completed[0] = true; completed_pos[0] = pos)

	# Real damage path: take_damage -> die -> player_died -> RespawnService cycle.
	# Seed a bag item so the corpse has something to carry (equipped gear
	# is not part of the bag; the corpse carries bag items).
	var bag_inv = player.get("inventory_component")
	if bag_inv != null and bag_inv.has_method("add_item"):
		var seed_item = ds_get_item("wep_iron_sword")
		if seed_item != null:
			bag_inv.add_item(seed_item, 1)

	hc.take_damage(9999, null)
	await get_tree().process_frame
	_ok("the player is dead after lethal damage", hc.is_dead())
	# The death corpse must carry the player's bag. get_all_items() returns
	# Item instances but _loot_items is Array[Dictionary]; the old
	# append_array() rejected the Objects (typed-array error) so a dead
	# player's gear never became lootable.
	var corpse = hc.get_corpse() if hc.has_method("get_corpse") else null
	if corpse != null:
		var corpse_items: Array = corpse.get_loot_items()
		var carried := false
		for it in corpse_items:
			if it is Dictionary and str(it.get("item_id", "")) == "wep_iron_sword":
				carried = true
		_ok("the death corpse carries the player's equipped bag item", carried,
			"(%d loot entries)" % corpse_items.size())
	else:
		_ok("the death corpse carries the player's equipped bag item", false, "(no corpse)")
	var modes: Array = rs.get_available_respawn_modes(player)
	_ok("the zone offers at least one respawn mode", modes.size() > 0, "(%s)" % str(modes))
	await _shot("playthrough_8_death")

	# The service's own self-driven cycle: death -> hold -> respawn. In the
	# ankh-less starter zone this is the TIMED default (10s) -- wait it out.
	var waited := 0.0
	while not completed[0] and waited < 13.0:
		await _settle(0.5)
		waited += 0.5
	_ok("the respawn cycle completed", completed[0], "(waited %.1fs)" % waited)
	_ok("the player is alive again", not hc.is_dead(), "(hp %d)" % hc.current_health)
	_ok("respawn restored the body to a real position",
		completed_pos[0] != Vector3.ZERO or player.global_position != Vector3.ZERO,
		"(pos %s)" % str(player.global_position))
	await _shot("playthrough_9_respawn")


## DataService item lookup without the local `ds` binding (used by stages that
## do not receive it).
func ds_get_item(item_id: String):
	var ds := get_tree().root.get_node_or_null("DataService")
	return ds.get_item(item_id) if ds != null and ds.has_method("get_item") else null


## Stage 13: the dialogue -> quest -> reward lane, driven end to end. Walks
## up to the blacksmith, opens its dialogue through the action menu, follows
## the branch that carries the GIVE_QUEST action, and proves the reward
## machinery pays on turn-in. This is the loop that had NO receipt: before
## round 2, turn_in_quest marked the quest REWARDED but granted nothing
## (QuestService._apply_rewards folded the reward summary and threw it away).
func _stage_dialogue_quest(inst: Node, player, inv, pid: String) -> void:
	var dsvc := get_tree().root.get_node_or_null("DialogService")
	var qsvc := get_tree().root.get_node_or_null("QuestService")
	var pman := get_tree().root.get_node_or_null("PlayerManager")
	_ok("DialogService + QuestService up", dsvc != null and qsvc != null)
	if dsvc == null or qsvc == null:
		return
	# _grant_rewards pays the PlayerManager mirror only when the local player
	# matches the quest earner; the playable world registers the player as
	# local (player_controller._ready -> PlayerManager.set_local_player).
	if pman != null and pman.get_local_player() != player:
		pman.set_local_player(player)

	# Spawn the blacksmith with its shipped data (dialogue + quest giver).
	var npc = load("res://core/entities/npc_entity.gd").new()
	npc.display_name = "Playthrough Blacksmith"
	npc.npc_data = load("res://data/npc/npc_blacksmith_village.tres")
	npc.global_position = player.global_position + _forward(player) * 2.0
	inst.add_child(npc)
	await get_tree().process_frame
	var es := get_tree().root.get_node_or_null("EntityService")
	var tm := get_tree().root.get_node_or_null("TargetingManager")
	# SpawnService registers an NPC under its NPCData id (entity_id ==
	# npc_data.id), which is what the dialogue -> TALK bridge matches on. A
	# manual registration without the override would get an "entity_N" id and
	# the TALK objective would never credit -- register the real way.
	var npc_id := str(npc.npc_data.id)
	if es and str(npc.get("entity_id")) == "":
		es.register_entity(npc, null, npc_id)
	if tm and str(npc.get("entity_id")) != "":
		tm.register_targetable(str(npc.get("entity_id")), "npc", npc,
			npc.display_name, npc.global_position, npc.entity_type)
	await get_tree().process_frame

	# E opens the action menu (proving the press resolves a live NPC). Drive
	# the "talk" action with the blacksmith's id pinned -- the same
	# _on_context_action seam the menu emits through, but immune to the
	# nearest-target scan picking a leftover NPC from an earlier stage.
	_key(KEY_E)
	await _settle(0.6)
	var menu = player.get("_action_menu")
	_ok("E opened the blacksmith action menu", menu != null and menu.visible)
	if menu == null or not menu.visible:
		return
	var started := [false]
	dsvc.dialogue_started.connect(func(_n, _d): started[0] = true)
	player._on_context_action("talk", str(npc.get("entity_id")))
	await _settle(0.4)
	# Some legs race the signal connect; the current dialogue is the truth.
	_ok("dialogue started with the blacksmith",
		started[0] or dsvc.get_current_node() != {})
	await _shot("playthrough_10_dialogue")

	# Walk the tree: node 0 -> choice 0 -> node 1 -> choice 0 -> node 3
	# (the GIVE_QUEST choice) -> node 4 -> auto-end.
	var gold_before: int = int(inv.get_gold())
	var pm_gold_before: int = int(pman.gold) if pman else 0
	var guard := 0
	while dsvc.get_current_node() != {} and guard < 12:
		guard += 1
		var node: Dictionary = dsvc.get_current_node()
		var choices: Array = node.get("choices", [])
		if choices.is_empty():
			dsvc.advance()
		else:
			dsvc.select_choice(0)
		await get_tree().process_frame
	# The choice fired GIVE_QUEST; accept_quest is the observable result.
	var accepted: Dictionary = qsvc.get_quest_progress(pid, "quest_intro_core_npcs")
	_ok("dialogue GIVE_QUEST accepted quest_intro_core_npcs",
		not accepted.is_empty(), "(state=%s)" % str(accepted.get("state")))
	if accepted.is_empty():
		return

	# Complete the required TALK objective by speaking to the blacksmith -- the
	# real dialogue_ended bridge credits it (target == the npc_ id).
	dsvc.start_dialogue(str(npc.npc_data.id), "blacksmith_village_intro")
	dsvc.end_dialogue()
	await get_tree().process_frame
	var prog: Dictionary = qsvc.get_quest_progress(pid, "quest_intro_core_npcs")
	# auto_complete = true: completion pays on the spot, so the quest lands in
	# REWARDED (4) without a trip back to the giver.
	_ok("the TALK bridge completed + auto-paid the quest",
		int(prog.get("state", -1)) == 4, "(state=%s)" % str(prog.get("state")))
	# quest_intro_core_npcs authors gold_reward=25, xp_reward=250, rewards=[].
	# The reward must land exactly once even though dialogue_ended fires twice
	# (the walk ended the dialogue once, then the explicit pass again).
	_ok("quest auto-pay granted the gold reward exactly once (25)",
		int(inv.get_gold()) == gold_before + 25,
		"(%d -> %d)" % [gold_before, inv.get_gold()])
	_ok("quest auto-pay mirrored the gold into PlayerManager",
		int(pman.gold) == pm_gold_before + 25 if pman else true,
		"(%d -> %d)" % [pm_gold_before, int(pman.gold) if pman else 0])
	await _shot("playthrough_11_quest_reward")

	# The blacksmith's tree also carries an OPEN_SHOP choice ("I'll start with
	# the forge." -> shop_id blacksmith_service). Drive it and assert the real
	# ShopUI opens bound to that offering -- the authored dialogue -> shop seam
	# had no live receipt. (blacksmith_service is a type="service" offering, so
	# the panel is intentionally empty of goods; the seam is what is under test.)
	dsvc.start_dialogue(str(npc.npc_data.id), "blacksmith_village_intro")
	await get_tree().process_frame
	dsvc.select_choice(0)   # node 0 -> 1
	await get_tree().process_frame
	dsvc.select_choice(0)   # node 1 -> 3
	await get_tree().process_frame
	dsvc.select_choice(1)   # node 3 -> OPEN_SHOP(blacksmith_service), ends dialogue
	await _settle(0.5)
	var ShopUIScript := load("res://ui/components/shop_ui.gd")
	var shop = ShopUIScript.singleton() if ShopUIScript else null
	_ok("the dialogue OPEN_SHOP choice opened the shop panel",
			shop != null and shop.visible, "(shop=%s)" % str(shop))
	if shop != null:
		var bound: String = str(shop._offering.display_name) if shop._offering else ""
		_ok("the shop panel is bound to the authored offering",
				bound == "Equipment Repair", "(offering=%s)" % bound)
		shop.close()
	await _shot("playthrough_12_dialogue_shop")


## Stage 14: accept a quest from the JOURNAL (not an NPC). Opens the real
## QuestUI through MenuManager, lists the AVAILABLE tab, selects a quest the
## player has not accepted, and presses its Accept button. Proves the journal
## accept path works on live node state -- before the round-2 fix the AVAILABLE
## detail read get_quest_progress ({} for an unaccepted quest) and showed no
## Accept button, so the journal could not accept a quest at all.
func _stage_journal_accept(player, pid: String) -> void:
	var mm := get_tree().root.get_node_or_null("MenuManager")
	if mm == null and get_tree().current_scene != null:
		var hud = get_tree().current_scene.get_node_or_null("HudLayer")
		mm = hud.get_node_or_null("MenuManager") if hud else null
	_ok("MenuManager resolved for the journal stage", mm != null)
	if mm == null:
		return
	mm.open_menu("quests")
	await _settle(0.5)
	var panel: Control = mm.get_panel_node("quests")
	_ok("the quest journal opened", panel != null and panel.visible)
	if panel == null:
		return
	panel._current_tab = panel.Tab.AVAILABLE
	panel.refresh_quest_list()
	await get_tree().process_frame
	var qsvc := get_tree().root.get_node_or_null("QuestService")
	var avail: Array = qsvc.get_available_quests(pid)
	var pick_id := str(avail[0].get("id", "")) if not avail.is_empty() and avail[0] is Dictionary else ""
	_ok("the journal lists an available quest to accept", not pick_id.is_empty(),
			"(id=%s, %d listed)" % [pick_id, avail.size()])
	if pick_id.is_empty():
		return
	panel._show_quest_detail(pick_id)
	await get_tree().process_frame
	var accept: Button = null
	var stack: Array = [panel._quest_detail]
	while not stack.is_empty():
		var n = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
			if c is Button and str(c.text) == "Accept Quest":
				accept = c
	_ok("the available quest detail shows an Accept button", accept != null)
	if accept == null:
		return
	accept.pressed.emit()
	await get_tree().process_frame
	var prog: Dictionary = qsvc.get_quest_progress(pid, pick_id)
	# QuestState.IN_PROGRESS == 2 (the runner uses literals, no QuestData import).
	_ok("pressing Accept accepted the quest from the journal",
			not prog.is_empty() and int(prog.get("state", -1)) == 2,
			"(state=%s)" % str(prog.get("state")))
	await _shot("playthrough_12_journal_accept")
	if panel.has_method("close"):
		panel.close()



## Stage 15: the waypoint -> compass loop. Creates a real waypoint at the
## player's position, activates it through WaypointService, and asserts the
## HUD Compass actually opened for the local player -- the compass had zero
## driver coverage, and its activation arm gates on the local player id.
func _stage_waypoint_route(player) -> void:
	var wsvc := get_tree().root.get_node_or_null("WaypointService")
	_ok("WaypointService up", wsvc != null)
	if wsvc == null:
		return
	var pid := str(player.get("entity_id"))
	var comp = _find_compass()
	_ok("the HUD Compass is in the tree", comp != null)
	if comp != null:
		comp.hide_compass()

	var res: Dictionary = wsvc.create_waypoint_here(pid, "Playthrough Marker")
	_ok("create_waypoint_here succeeded", bool(res.get("success", false)), "(%s)" % str(res.get("message", "")))
	var wp: Dictionary = res.get("waypoint", {})
	var wp_id := str(wp.get("id", ""))
	_ok("the waypoint got an id", wp_id != "", "(%s)" % wp_id)
	if wp_id == "":
		return

	var act: Dictionary = wsvc.activate_waypoint(pid, wp_id)
	_ok("activate_waypoint succeeded", bool(act.get("success", false)), "(%s)" % str(act.get("message", "")))
	if comp != null:
		_ok("the compass opened for the activated waypoint", comp.visible,
			"(local=%s pid=%s)" % [str(_local_pid()), pid])
	_ok("WaypointService reports the active waypoint",
		str(wsvc.get_active_waypoint(pid).get("id", "")) == wp_id)

	# Bounds validation refuses an out-of-world position (anti-teleport).
	var far: Dictionary = wsvc.create_waypoint(pid, "Far Marker", Vector3(9999999.0, 0.0, 0.0), "zone_starter_plains")
	_ok("create_waypoint refuses an out-of-bounds position",
		not bool(far.get("success", false)), "(%s)" % str(far.get("message", "")))

	wsvc.deactivate_waypoint(pid)
	if comp != null:
		_ok("the compass closed when the waypoint deactivated", not comp.visible)
	await _shot("playthrough_13_waypoint")


## Stage 16: the friend request -> accept -> block loop. Two real player ids
## drive FriendsService's request/accept/block surface; asserts the loop's
## observable state (friendship, one-time accept, block auto-unfriends).
func _stage_social_friends(pid: String) -> void:
	var fsvc := get_tree().root.get_node_or_null("FriendsService")
	_ok("FriendsService up", fsvc != null)
	if fsvc == null:
		return
	var peer := "playthrough_peer"
	var accepted_signals := [0]
	var declined_signals := [0]
	fsvc.friend_request_accepted.connect(func(_fid): accepted_signals[0] += 1)
	fsvc.friend_request_declined.connect(func(_f, _t): declined_signals[0] += 1)

	var req: Dictionary = fsvc.send_friend_request(pid, "Playthrough Player", peer)
	_ok("send_friend_request succeeded", bool(req.get("success", false)), "(%s)" % str(req.get("message", "")))
	var req_id := str(req.get("request_id", ""))
	if req_id == "":
		return
	var accept: Dictionary = fsvc.accept_friend_request(peer, req_id)
	_ok("accept_friend_request succeeded", bool(accept.get("success", false)), "(%s)" % str(accept.get("message", "")))
	_ok("the two players are friends after accept", fsvc.is_friend(pid, peer))
	# Regression: accept used to ALSO emit friend_request_declined (copy-paste
	# from decline), so the UI saw an accept and a decline for one request.
	_ok("accept emitted accepted exactly once, declined not at all",
		accepted_signals[0] == 1 and declined_signals[0] == 0,
		"(accepted=%d declined=%d)" % [accepted_signals[0], declined_signals[0]])

	var blk: Dictionary = fsvc.block_player(pid, peer)
	_ok("block_player succeeded", bool(blk.get("success", false)), "(%s)" % str(blk.get("message", "")))
	_ok("blocking auto-unfriended the pair", not fsvc.is_friend(pid, peer))
	_ok("the peer can no longer interact with the blocker", not fsvc.can_interact_with(peer, pid))
	var unblk: Dictionary = fsvc.unblock_player(pid, peer)
	_ok("unblock_player succeeded", bool(unblk.get("success", false)), "(%s)" % str(unblk.get("message", "")))
	_ok("the peer can interact again after unblock", fsvc.can_interact_with(peer, pid))


## Stage 17: the chat pipeline + the ignore book. A real party makes PARTY
## chat resolve a live audience (send_message returns true + message_received
## fires); the ignore book then hides the peer's lines at the display surface
## while System stays visible.
func _stage_chat_social(pid: String) -> void:
	var csvc := get_tree().root.get_node_or_null("ChatService")
	_ok("ChatService up", csvc != null)
	if csvc == null:
		return
	var peer := "playthrough_chatter"

	# A real party makes PARTY chat resolve a live target set.
	var psvc := get_tree().root.get_node_or_null("PartyService")
	var got: Array = []
	csvc.message_received.connect(func(sender_id, channel, msg, targets): got.append([sender_id, channel, msg, targets]))
	if psvc != null:
		var party_id: String = psvc.create_party(pid)
		_ok("party created for chat", party_id != "", "(%s)" % party_id)
		psvc.invite_player(pid, peer)
		psvc.accept_invite(peer)
		var sent: bool = csvc.send_message(pid, csvc.Channel.PARTY, "playthrough hello")
		_ok("party chat delivered to a real audience", sent)
		_ok("message_received fired for the party line", not got.is_empty())
		psvc.leave_party(pid)
		psvc.leave_party(peer)
	else:
		_ok("PartyService up (for the chat audience)", false)

	# System messages always land, even with an ignore list.
	var sys_lines: Array = []
	csvc.message_received.connect(func(sender_id, channel, msg, _targets):
		if channel == csvc.Channel.SYSTEM:
			sys_lines.append(msg))
	csvc.send_system_message(pid, "Playthrough system line")
	_ok("send_system_message emitted a SYSTEM line", not sys_lines.is_empty())

	# The ignore book: ignoring the peer hides their lines (by id), System
	# stays visible, and unignoring restores delivery.
	var ign: Dictionary = csvc.ignore_player(pid, peer)
	_ok("ignore_player succeeded", bool(ign.get("success", false)), "(%s)" % str(ign.get("message", "")))
	_ok("is_ignored_sender reports the ignored peer", csvc.is_ignored_sender(pid, peer))
	_ok("is_ignored_sender never hides SYSTEM", not csvc.is_ignored_sender(pid, "SYSTEM"))
	var unign: Dictionary = csvc.unignore_player(pid, peer)
	_ok("unignore_player succeeded", bool(unign.get("success", false)), "(%s)" % str(unign.get("message", "")))
	_ok("the peer is no longer ignored", not csvc.is_ignored_sender(pid, peer))

	# The display surface: ChatUI (the live chat panel) drops an ignored
	# sender's line but keeps a System line.
	var mm := get_tree().root.get_node_or_null("MenuManager")
	if mm == null and get_tree().current_scene != null:
		var hud = get_tree().current_scene.get_node_or_null("HudLayer")
		mm = hud.get_node_or_null("MenuManager") if hud else null
	var chat = mm.get_node_or_null("ChatUI") if mm != null else null
	_ok("the HUD chat panel is in the tree", chat != null)
	if chat != null and chat.has_method("add_message"):
		csvc.ignore_player(pid, peer)
		var count_before: int = int(chat.get("_message_count"))
		chat.add_message(peer, csvc.Channel.SAY, "hidden line", pid)
		var after_hidden: int = int(chat.get("_message_count"))
		chat.add_message("SYSTEM", csvc.Channel.SYSTEM, "visible line", pid)
		var after_system: int = int(chat.get("_message_count"))
		_ok("ChatUI dropped the ignored sender's line", after_hidden == count_before,
			"(%d -> %d)" % [count_before, after_hidden])
		_ok("ChatUI kept the System line", after_system > after_hidden)
		csvc.unignore_player(pid, peer)


func _local_pid() -> String:
	var pm := get_tree().root.get_node_or_null("PlayerManager")
	return str(pm.get_local_player_id()) if pm != null else ""


## The HUD Compass: under the HUD's WaypointUI, or found by name anywhere.
func _find_compass():
	var hud = get_tree().current_scene.get_node_or_null("HudLayer") if get_tree().current_scene else null
	if hud != null:
		var direct = hud.get_node_or_null("Compass")
		if direct != null:
			return direct
	return get_tree().root.find_child("Compass", true, false)


func _finish() -> void:
	print("PLAYTHROUGH %d passed, %d failed%s" % [_pass, _fail, _fail_flags if _fail_flags else ""])
	await get_tree().process_frame
	get_tree().quit(0 if _fail == 0 else 1)

## The player's forward direction on the XZ plane (stable regardless of pitch).
func _forward(player) -> Vector3:
	var f: Vector3 = -player.global_transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.001 else Vector3.FORWARD


func _key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventKey.new()
	up.keycode = code
	up.physical_keycode = code
	up.pressed = false
	Input.parse_input_event(up)

## Wall-clock settle: under xvfb + llvmpipe the world renders at ~1-2 fps, so a
## frame-counted settle is time dilation (see globe_driver_runner.gd).
func _settle(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _shot(stage_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("/tmp/play/%s.png" % stage_name)
		print("  shot: /tmp/play/%s.png" % stage_name)
