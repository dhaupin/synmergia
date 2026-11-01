extends SceneTree

## Economy receipt (the money loop becomes player-facing):
##   1. The binder is honest: no local player leaves the HUD silent.
##   2. Node wallet rows: the wallet the world pays into (kills,
##      ground loot) speaks on real deltas and stays quiet through
##      hydration (total-carrier seeding).
##   3. Component wallet rows: vendors/vault spend the mounted
##      InventoryComponent; add_gold/remove_gold ride its signed
##      gold_changed into +N/-N rows.
##   4. The equip voice: equip_item/unequip_item/clear_equipment_slot
##      (full-loot strips count) emit item_equipped and land rows;
##      the catalog ghost name earns its first real emitters.
##   5. An open bag's Gold label follows the wallet live.
## Run:
##   godot --headless --path . --script res://tests/test_economy_wallet_rows.gd

func _initialize() -> void:
	# Autoload-lag law: the body runs on the first idle frame.
	_run.call_deferred()

func _run() -> void:
	var hud = load("res://ui/hud/hud_integrator.gd").new()
	root.add_child(hud)
	var log_ui = load("res://ui/components/combat_log.gd").new()
	root.add_child(log_ui)
	hud._combat_log = log_ui

	# 1. The binder's no-player leg is a silent no-op, not a crash.
	hud._bind_player_wallet_feedback()
	print("[OK] the wallet binder is a no-op without a local player (no crash)")

	# 2/3/4. Bind through the real seam: a probe player node with the
	# same duck-typed wallet surface the world pays (signal-carrying
	# gold total + a mounted InventoryComponent) rides PlayerManager's
	# local_player slot. A bare Node cannot gain properties via set(),
	# so the script body declares them.
	var pm: Node = root.get_node_or_null("PlayerManager")
	var comp = load("res://core/components/inventory_component.gd").new()
	comp.set_owner_id("<probe>")
	# Kept UNPARENTED on purpose: the probe is not an entity, and the
	# component's stat-apply reads get_parent() (null-safe return).
	var wallet_script := GDScript.new()
	wallet_script.source_code = "extends Node\nsignal gold_changed(current: int)\nvar gold: int = 100\nvar inventory_component = null\n"
	wallet_script.reload()
	var fake_player := Node.new()
	fake_player.name = "EconomyProbePlayer"
	fake_player.set_script(wallet_script)
	fake_player.gold = 100
	fake_player.inventory_component = comp
	root.add_child(fake_player)
	if pm == null or not pm.has_method("set_local_player"):
		push_error("FAIL: PlayerManager.set_local_player not reachable in script mode")
		quit(1)
		return
	pm.set_local_player(fake_player)
	var inv_svc: Node = root.get_node_or_null("InventoryService")
	if inv_svc == null or not inv_svc.has_method("register_inventory"):
		push_error("FAIL: InventoryService.register_inventory not reachable")
		quit(1)
		return
	inv_svc.register_inventory("<probe>", comp)
	hud._bind_player_wallet_feedback()
	if hud._node_gold_seen != 100:
		push_error("FAIL: the node wallet was never seeded (seen=%d)" % int(hud._node_gold_seen))
		quit(1)
		return
	if hud._comp_gold_seen != 0:
		push_error("FAIL: the component wallet was never seeded (seen=%d)" % int(hud._comp_gold_seen))
		quit(1)
		return
	print("[OK] the wallet binder seeds both wallets through the local-player seam")

	# 2. Node wallet: hydration stays quiet, paid deltas speak.
	var base: int = log_ui.get_message_count()
	fake_player.gold_changed.emit(100) # a restore/rebind re-announces the CURRENT total
	if log_ui.get_message_count() != base:
		push_error("FAIL: the hydration re-emit was not quiet (rows=%d > %d)" % [log_ui.get_message_count(), base])
		quit(1)
		return
	# A real payment: kill rewards advance the wallet, then emit the
	# NEW total (the seen-value stays at the pre-pay total -> +45).
	fake_player.gold = 145
	fake_player.gold_changed.emit(145)
	var after_gain: int = log_ui.get_message_count()
	if after_gain != base + 1:
		push_error("FAIL: the node wallet delta produced no row (%d -> %d)" % [base, after_gain])
		quit(1)
		return
	var gain_row: String = str(_last_row(log_ui))
	if not gain_row.contains("+45 gold"):
		push_error("FAIL: the gain row lost its truth ('%s')" % gain_row)
		quit(1)
		return
	print("[OK] the node wallet speaks in paid deltas (+45 gold), quiet through hydration")

	# 3. Component wallet: the services' wallet, signed deltas.
	var cbase: int = log_ui.get_message_count()
	comp.add_gold(50)
	if log_ui.get_message_count() != cbase + 1:
		push_error("FAIL: comp add_gold produced no row")
		quit(1)
		return
	if not str(_last_row(log_ui)).contains("+50 gold"):
		push_error("FAIL: the comp gain row lost its truth")
		quit(1)
		return
	if not comp.remove_gold(25):
		push_error("FAIL: comp remove_gold refused an affordable spend")
		quit(1)
		return
	if log_ui.get_message_count() != cbase + 2:
		push_error("FAIL: comp remove_gold produced no row")
		quit(1)
		return
	var spend_row: String = str(_last_row(log_ui))
	if not spend_row.contains("-25 gold"):
		push_error("FAIL: the spend row lost its truth ('%s')" % spend_row)
		quit(1)
		return
	print("[OK] the component wallet rows vendor spends and loot pays")

	# 4. The equip voice on the REAL endpoints: a real weapon item.
	var sword = load("res://data/weapons/wep_iron_sword.tres") if ResourceLoader.exists("res://data/weapons/wep_iron_sword.tres") else null
	if sword == null or not sword.can_equip():
		push_error("FAIL: the receipt needs an equip-able real item (wep_iron_sword)")
		quit(1)
		return
	# The expected slot text comes from the item's OWN data through
	# the enum, not a hardcoded main-hand guess (the sword's tres
	# declares equip_slot = 8 = off_hand).
	var slot_names: Variant = sword.EquipSlot.keys()
	var expected_slot: String = str(slot_names[int(sword.equip_slot)]).to_lower()
	if not comp.add_item(sword):
		push_error("FAIL: the probe bag refused the weapon")
		quit(1)
		return
	var ebase: int = log_ui.get_message_count()
	if not comp.equip_item(0):
		push_error("FAIL: equip_item refused a legal weapon")
		quit(1)
		return
	var e_row: String = str(_last_row(log_ui))
	if not e_row.contains("You equip") or not e_row.contains(expected_slot):
		push_error("FAIL: the equip row lost its truth ('%s')" % e_row)
		quit(1)
		return
	if not comp.unequip_item(int(sword.equip_slot)):
		push_error("FAIL: unequip_item refused the just-equipped weapon")
		quit(1)
		return
	# Re-equip so the final strip leg has something to strip (after
	# unequip_item the equipment dict already sits empty; stripping
	# nothing is honest silence, not a fourth row).
	var u_row: String = str(_last_row(log_ui))
	if not u_row.contains("You unequip"):
		push_error("FAIL: the unequip row lost its truth ('%s')" % u_row)
		quit(1)
		return
	if not comp.equip_item(0):
		push_error("FAIL: the re-equip for the strip leg was refused")
		quit(1)
		return
	comp.clear_equipment_slot(int(sword.equip_slot))
	var s_row: String = str(_last_row(log_ui))
	if not s_row.contains("You unequip"):
		push_error("FAIL: the full-loot strip produced no row ('%s')" % s_row)
		quit(1)
		return
	if log_ui.get_message_count() != ebase + 4:
		push_error("FAIL: the equip legs row count drifted (rows=%d, want=%d)" % [log_ui.get_message_count(), ebase + 4])
		quit(1)
		return
	print("[OK] equip/unequip/full-loot-strip land their rows")

	# 5. The open-bag Gold label follows the component wallet.
	var inv_ui = load("res://ui/components/inventory_ui.gd").new()
	root.add_child(inv_ui)
	# The real lifecycle: open() builds the panel and rides _on_open
	# (service bind + refresh) -- never a bare private refresh call.
	inv_ui.open("<probe>")
	if inv_ui._gold_label == null:
		push_error("FAIL: the bag's gold label never built")
		quit(1)
		return
	if not str(inv_ui._gold_label.text).contains("Gold:"):
		push_error("FAIL: the gold label did not hydrate ('%s')" % str(inv_ui._gold_label.text))
		quit(1)
		return
	comp.add_gold(7)
	if "Gold: %d" % comp.get_gold() != str(inv_ui._gold_label.text):
		push_error("FAIL: the open bag's gold label went stale ('%s', wallet=%d)" % [str(inv_ui._gold_label.text), comp.get_gold()])
		quit(1)
		return
	print("[OK] an open bag's Gold label follows the component wallet")

	inv_svc.unregister_inventory("<probe>")
	pm.set_local_player(null)
	hud.queue_free()
	log_ui.queue_free()
	comp.queue_free()
	inv_ui.queue_free()
	fake_player.queue_free()
	print("--- ECONOMY WALLET ROWS: ok=true ---")
	quit(0)

func _last_row(log_ui) -> Variant:
	var entries: Variant = log_ui.get("_entries")
	if not (entries is Array) or (entries as Array).is_empty():
		return ""
	return (entries as Array)[(entries as Array).size() - 1].get("text")
