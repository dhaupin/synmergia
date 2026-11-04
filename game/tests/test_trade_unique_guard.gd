## test_trade_unique_guard - regression for the unreachable-body bug in
## TradeService._is_item_owned_by_anyone. The loop body sat one tab under the
## `continue`, so it never ran and can_trade_item() always allowed a unique
## item that was already owned. This receipt mounts a player whose purse holds
## a unique item and asserts can_trade_item() refuses it -- and that an
## unowned unique / plain item is still allowed (the guard has teeth both ways).
extends SceneTree

var _passed := 0
var _failed := 0

func _init() -> void:
	call_deferred("_run")

func _ok(msg: String) -> void:
	_passed += 1
	print("[OK] " + msg)

func _fail(msg: String) -> void:
	_failed += 1
	push_error("FAIL: " + msg)

func _run() -> void:
	await process_frame
	var es: Node = root.get_node_or_null("EntityService")
	var inv_svc: Node = root.get_node_or_null("InventoryService")
	var trade: Node = root.get_node_or_null("TradeService")
	if es == null or inv_svc == null or trade == null:
		_fail("EntityService/InventoryService/TradeService autoloads missing")
		_finish()
		return
	_ok("services present")

	# A player node carrying a mounted purse, registered so EntityService's
	# get_all_players() sees it (the guard iterates real players).
	var comp = load("res://core/components/inventory_component.gd").new()
	comp.set_owner_id("trade_probe")
	var ps := GDScript.new()
	ps.source_code = "extends Node3D\nvar entity_id: String = 'trade_probe'\nvar entity_type: int = 1\nvar display_name: String = 'TradeProbe'\nvar seed: int = 0\nvar inventory_component = null\n"
	ps.reload()
	var player = ps.new()
	player.name = "TradeProbePlayer"
	player.inventory_component = comp
	root.add_child(player)
	es.register_entity(player, null, "trade_probe")
	inv_svc.register_inventory("trade_probe", comp)

	var unique_item := Item.new()
	unique_item.id = "test_unique_relic"
	unique_item.display_name = "Test Unique Relic"
	unique_item.unique = true
	comp.add_item(unique_item, 1)

	var owned: bool = trade.can_trade_item(unique_item)
	if owned:
		_fail("can_trade_item allowed a UNIQUE item the player already owns (guard unreachable)")
	else:
		_ok("can_trade_item refuses an already-owned unique item")

	var unowned_unique := Item.new()
	unowned_unique.id = "test_unique_other"
	unowned_unique.display_name = "Test Unique Other"
	unowned_unique.unique = true
	if trade.can_trade_item(unowned_unique):
		_ok("can_trade_item still allows an unowned unique item")
	else:
		_fail("can_trade_item wrongly refused an unowned unique item")

	var plain := Item.new()
	plain.id = "test_plain_item"
	plain.display_name = "Test Plain"
	if trade.can_trade_item(plain):
		_ok("can_trade_item allows a plain item")
	else:
		_fail("can_trade_item wrongly refused a plain item")

	es.unregister_entity(player, "test")
	inv_svc.unregister_inventory("trade_probe")
	player.queue_free()
	_finish()

func _finish() -> void:
	print("--- TRADE UNIQUE GUARD: %d passed, %d failed ---" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
