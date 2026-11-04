## InventoryService - Player inventory operations
## Handles inventory-related operations and cross-player inventory access
extends Node
# QoSService uses static shim methods (AGENTS.md allowlist); the const is required.
const QoSService = preload("res://core/autoload/qos_service.gd")
const DictStore = preload("res://adapters/persistence/dict_store.gd")

const Item = preload("res://core/schemas/item.gd")
const InventoryComponent = preload("res://core/components/inventory_component.gd")
# Singleton instance
static var instance: InventoryService

# Player inventories (player_id -> InventoryComponent)
var _player_inventories: Dictionary = {}

## DictStore key prefix
const _kv_prefix := "inventory:player:"

signal item_transferred(from_id: String, to_id: String, item: Item, quantity: int)
signal gold_transferred(from_id: String, to_id: String, amount: int)

# Frame-level notification dispatch (see game/core/notifications/).
# InventoryService surfaces add/remove/full/soulbound/trade-reject events
# through the toast pipeline. Dedupe keys are item-aware so a player
# looting 50 of the same item sees one toast for the burst, not 50.
const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind

func _emit_inventory(
	player_id: String,
	kind: int,
	message: String,
	dedupe_key: String = "",
	data: Dictionary = {}
) -> void:
	if not is_instance_valid(NotificationService):
		return
	# Frame-level dispatch via the typed-Kind pipeline. notify()
	# builds the context internally and forwards through dedupe +
	# send(); the legacy NotificationContext wrapper is no longer
	# needed at this call site.
	NotificationService.notify(
		kind,
		message,
		"InventoryService",
		dedupe_key,
		data,
		player_id
	)

func _ready() -> void:
	instance = self
	_load_inventories()
	GameLog.info("InventoryService: Ready")

## Register a player's inventory
func register_inventory(player_id: String, inventory: InventoryComponent) -> void:
	_player_inventories[player_id] = inventory
	_persist_inventory(player_id)
	GameLog.debug("InventoryService: Registered inventory for %s" % player_id)

## Unregister a player's inventory
func unregister_inventory(player_id: String) -> void:
	_player_inventories.erase(player_id)

## Get player's inventory
func get_inventory(player_id: String) -> InventoryComponent:
	var inv = _player_inventories.get(player_id)
	# A freed registration (a body that went away without unregistering) must
	# not be handed back: returning it as a typed InventoryComponent raises
	# "previously freed instance". A freed Object compares equal to null, so
	# gate on validity alone. An absent key is also invalid -- erasing it is a
	# harmless no-op and returning null is the honest answer.
	if not is_instance_valid(inv):
		_player_inventories.erase(player_id)
		return null
	return inv

## Check if player has inventory registered
func has_inventory(player_id: String) -> bool:
	return _player_inventories.has(player_id)

## Transfer item from one player to another
func transfer_item(from_id: String, to_id: String, item: Item, quantity: int = -1) -> bool:
	# QoS: Rate limit inventory transfers
	if not QoSService.rate_limit(from_id, "inventory_transfer"):
		GameLog.debug("InventoryService: Rate limited transfer for %s" % from_id)
		return false

	# SECURITY: Validate inputs
	if from_id == "" or to_id == "" or item == null:
		GameLog.error("InventoryService: Invalid transfer parameters")
		return false

	if from_id == to_id:
		GameLog.warn("InventoryService: Cannot transfer to self")
		return false

	# SECURITY: Check both players are registered
	var from_inv: InventoryComponent = get_inventory(from_id)
	var to_inv: InventoryComponent = get_inventory(to_id)
	if not from_inv or not to_inv:
		GameLog.error("InventoryService: Missing inventory for transfer %s -> %s" % [from_id, to_id])
		return false

	# Find item in source inventory
	var slot: int = from_inv.find_item(item.id)
	if slot < 0:
		GameLog.warn("InventoryService: Item %s not found in %s" % [item.id, from_id])
		return false

	# SECURITY: Verify item is actually at this slot (ownership check)
	var source_item: Item = from_inv.get_item(slot)
	if source_item == null or source_item != item:
		GameLog.error("InventoryService: Item ownership verification failed for %s" % item.id)
		return false

	# SECURITY: Reject soulbound items. bind_on_pickup binds at first pickup;
	# soulbound is the explicit flag the schema exposes.
	if source_item.soulbound or source_item.bind_on_pickup:
		GameLog.warn("InventoryService: Refusing to transfer soulbound item %s from %s" % [item.id, from_id])
		_emit_inventory(
			from_id,
			NotifKind.ITEM_SOULBOUND_REJECT,
			"%s is soulbound and cannot be transferred" % item.display_name,
			"inv_soulbound:%s:%s" % [from_id, item.id],
			{"item_id": item.id, "reason": "soulbound"}
		)
		return false

	# Remove from source
	var removed: Item = from_inv.remove_item(slot, quantity)
	if not removed:
		return false

	# Add to destination
	if not to_inv.add_item(removed):
		# Failed to add - return to source
		from_inv.add_item(removed)
		GameLog.warn("InventoryService: Transfer failed - destination full")
		# Frame-level toast on the destination player. Dedupe on (to, item)
		# so a series of failed transfers for the same item doesn't spam.
		_emit_inventory(
			to_id,
			NotifKind.ITEM_FULL,
			"Inventory full -- couldn't receive %s" % item.display_name,
			"inv_full:%s:%s" % [to_id, item.id],
			{"item_id": item.id, "from_id": from_id, "qty": removed.current_stack}
		)
		return false

	item_transferred.emit(from_id, to_id, removed, removed.current_stack)
	# Frame-level toasts: recipient sees "received", sender sees "sent".
	# Two distinct players -> two distinct dedupe keys, both fire normally.
	_emit_inventory(
		to_id,
		NotifKind.ITEM_ADDED,
		"Received %s x%d" % [item.display_name, removed.current_stack],
		"inv_recv:%s:%s" % [to_id, item.id],
		{"item_id": item.id, "from_id": from_id, "qty": removed.current_stack}
	)
	_emit_inventory(
		from_id,
		NotifKind.ITEM_REMOVED,
		"Sent %s x%d" % [item.display_name, removed.current_stack],
		"inv_sent:%s:%s" % [from_id, item.id],
		{"item_id": item.id, "to_id": to_id, "qty": removed.current_stack}
	)
	GameLog.info("InventoryService: Transferred %s x%d from %s to %s" % [item.id, removed.current_stack, from_id, to_id])

	return true

## Transfer gold from one player to another
func transfer_gold(from_id: String, to_id: String, amount: int) -> bool:
	# QoS: Rate limit gold transfers
	if not QoSService.rate_limit(from_id, "gold_transfer"):
		GameLog.debug("InventoryService: Rate limited gold transfer for %s" % from_id)
		return false

	# SECURITY: Validate inputs
	if from_id == "" or to_id == "":
		GameLog.error("InventoryService: Invalid gold transfer parameters")
		return false

	if from_id == to_id:
		GameLog.warn("InventoryService: Cannot transfer gold to self")
		return false

	if amount <= 0:
		GameLog.warn("InventoryService: Cannot transfer negative or zero gold")
		return false

	# Check both players are registered
	var from_inv: InventoryComponent = get_inventory(from_id)
	var to_inv: InventoryComponent = get_inventory(to_id)
	if not from_inv or not to_inv:
		GameLog.error("InventoryService: Missing inventory for gold transfer %s -> %s" % [from_id, to_id])
		return false

	if not from_inv.remove_gold(amount):
		GameLog.warn("InventoryService: %s has insufficient gold for transfer" % from_id)
		return false

	to_inv.add_gold(amount)
	gold_transferred.emit(from_id, to_id, amount)
	GameLog.info("InventoryService: Transferred %d gold from %s to %s" % [amount, from_id, to_id])

	return true

## Transfer multiple items at once
func transfer_items(from_id: String, to_id: String, items: Array) -> Dictionary:
	var results := {
		"success": true,
		"transferred": [],
		"failed": []
	}

	for item_data in items:
		var item_id: String = item_data.get("item_id", "")
		var quantity: int = item_data.get("quantity", -1)

		if item_id == "":
			results["failed"].append({"item_id": item_id, "reason": "Invalid item_id"})
			results["success"] = false
			continue

		# Find item in source
		var from_inv: InventoryComponent = get_inventory(from_id)
		if not from_inv:
			results["failed"].append({"item_id": item_id, "reason": "Source inventory not found"})
			results["success"] = false
			continue

		var slot: int = from_inv.find_item(item_id)
		if slot < 0:
			results["failed"].append({"item_id": item_id, "reason": "Item not found"})
			results["success"] = false
			continue

		# Transfer this item
		if not transfer_item(from_id, to_id, from_inv.get_item(slot), quantity):
			results["failed"].append({"item_id": item_id, "reason": "Transfer failed"})
			results["success"] = false
		else:
			results["transferred"].append(item_id)

	# Frame-level toast on the sender: if the whole batch failed and nothing
	# transferred, surface a single trade-reject. The per-item toasts already
	# fire from transfer_item, so this is just the summary line.
	if not results["success"] and results["transferred"].is_empty() and not results["failed"].is_empty():
		var first_fail: Dictionary = results["failed"][0]
		_emit_inventory(
			from_id,
			NotifKind.ITEM_TRADE_REJECT,
			"Trade rejected (%d item(s) failed)" % results["failed"].size(),
			"trade_reject:%s:%s" % [from_id, first_fail.get("item_id", "unknown")],
			{"failed_count": results["failed"].size(), "to_id": to_id}
		)

	return results

## Execute a full trade (used by TradeService)
func execute_trade(trade_id: String, player1: String, player2: String,
					player1_items: Array, player2_items: Array,
					player1_gold: int, player2_gold: int) -> Dictionary:
	# QoS: Rate limit trades for both players
	if not QoSService.rate_limit(player1, "inventory_trade"):
		GameLog.debug("InventoryService: Rate limited trade for %s" % player1)
		return {"success": false, "error": "Rate limited"}
	if not QoSService.rate_limit(player2, "inventory_trade"):
		GameLog.debug("InventoryService: Rate limited trade for %s" % player2)
		return {"success": false, "error": "Rate limited"}

	var results := {
		"trade_id": trade_id,
		"player1": {
			"items_transferred": [],
			"gold_transferred": 0
		},
		"player2": {
			"items_transferred": [],
			"gold_transferred": 0
		},
		"success": true
	}

	# Transfer gold
	if player1_gold > 0:
		if transfer_gold(player1, player2, player1_gold):
			results["player1"]["gold_transferred"] = player1_gold
		else:
			results["success"] = false

	if player2_gold > 0:
		if transfer_gold(player2, player1, player2_gold):
			results["player2"]["gold_transferred"] = player2_gold
		else:
			results["success"] = false

	# Transfer items from player1 to player2
	for item_data in player1_items:
		var item_id: String = item_data.get("item_id", "")
		var quantity: int = item_data.get("quantity", -1)

		var from_inv: InventoryComponent = get_inventory(player1)
		if not from_inv:
			continue

		var slot: int = from_inv.find_item(item_id)
		if slot < 0:
			continue

		var item: Item = from_inv.get_item(slot)
		if item and transfer_item(player1, player2, item, quantity):
			results["player1"]["items_transferred"].append(item_id)

	# Transfer items from player2 to player1
	for item_data in player2_items:
		var item_id: String = item_data.get("item_id", "")
		var quantity: int = item_data.get("quantity", -1)

		var from_inv: InventoryComponent = get_inventory(player2)
		if not from_inv:
			continue

		var slot: int = from_inv.find_item(item_id)
		if slot < 0:
			continue

		var item: Item = from_inv.get_item(slot)
		if item and transfer_item(player2, player1, item, quantity):
			results["player2"]["items_transferred"].append(item_id)

	GameLog.info("InventoryService: Trade %s completed - success: %s" % [trade_id, results["success"]])
	return results

## Get player's gold
func get_gold(player_id: String) -> int:
	var inv: InventoryComponent = get_inventory(player_id)
	if inv:
		return inv.get_gold()
	return 0

## Signed gold delta through the ONE purse. The companion to get_gold():
## VaultService.deposit_gold/withdraw_gold/expand_vault and DeathFeatures
## call this by name, but it never existed -- every vault gold move (and the
## expansion debit/refund) died on a missing method, so the vault held no
## coin and the death gold-penalty silently no-oped. Positive adds, negative
## removes; a removal the purse cannot cover refuses (no partial debit) and
## returns false so the caller can abort its own book.
func modify_gold(player_id: String, amount: int) -> bool:
	var inv: InventoryComponent = get_inventory(player_id)
	if inv == null:
		return false
	if amount >= 0:
		inv.add_gold(amount)
		return true
	return inv.remove_gold(-amount)


## Check if player can receive item (has space and weight)
func can_receive_item(player_id: String, item: Item) -> bool:
	var inv: InventoryComponent = get_inventory(player_id)
	if not inv:
		return false

	# Check weight
	if not inv.can_carry(item):
		return false

	# Check slot (will return false if no space)
	return true

## Get inventory summary
func get_inventory_summary(player_id: String) -> Dictionary:
	var inv: InventoryComponent = get_inventory(player_id)
	if not inv:
		return {}

	return {
		"player_id": player_id,
		"gold": inv.get_gold(),
		"current_weight": inv.get_current_weight(),
		"max_weight": inv.get_max_weight(),
		"encumbered": inv.is_encumbered(),
		"slots_used": inv.get_inventory_count(),
		"slots_total": inv.get_total_slots(),
		"free_slots": inv.get_free_slot_count()
	}

## ============================================================================
## THE USE DOOR: consumables actually become effects
## ============================================================================
## For the whole project's life the consumable schema carried a book
## (buff_effects) and no one ever read it -- a potion was an ingredient
## for nothing. The use door fixes the CONSUMER, not the schema:
##
##   GATES BEFORE EVERYTHING: a real bag, a real slot, a real item,
##   CONSUMABLE category, an alive body, a non-empty effect book, and
##   the per-ITEM use cooldown (a potion's cooldown is the ITEM's own
##   field, not a service namespace: CooldownService's books price
##   COOLDOWNS by action key, so the bag's use door keeps its own book
##   keyed [player][item] -> expiry). Every refusal names itself.
##
##   VALIDATED THEN PAID: the whole effect book is validated (every
##   buff a known type with usable values) BEFORE a single charge is
##   removed -- the books never half-drink. Then ONE charge leaves the
##   slot, then the effects land (instant heal/mana/stamina through
##   the body's duck surface; timed effects are real StatusEffect
##   nodes riding apply_status_effect -- the skill precedent).
##
##   UNKNOWN = REFUSAL: an unreadable buff type, a buff with no
##   value, or a timed effect with no duration refuses the whole use
##   (nothing consumed) -- never a silent no-op.

signal item_used(player_id: String, item: Item, applied: Array)

# [player_id -> [item_id -> expiry unix seconds]] (the use cooldown book)
var _use_cooldowns: Dictionary = {}

## The receipt seam: an injectable body resolver for scripted boots
## (the transport-seam law: injectable resolvers, never product
## fakes). Runtime rides the default chain in _use_body.
var _use_body_override: Callable = Callable()

const StatusEffect = preload("res://core/entities/status_effect.gd")

## Stat buff keys the use door knows. Maps buff dict key -> the
## StatusEffect export it drives (suffix law: "<stat>_mod", and the
## two multiplier exports). Anything outside this book is a refusal.
const _STAT_BUFFS := {
	"strength": "strength_mod",
	"agility": "agility_mod",
	"intelligence": "intelligence_mod",
	"vitality": "vitality_mod",
	"endurance": "endurance_mod",
	"wisdom": "wisdom_mod",
	"max_health": "max_health_mod",
	"max_mana": "max_mana_mod",
	"physical_resistance": "physical_resistance",
	"magical_resistance": "magical_resistance",
	"movement_speed": "movement_speed_multiplier",
	"attack_speed": "attack_speed_multiplier",
	"damage": "damage_multiplier",
	"defense": "defense_multiplier",
}

func use_item(player_id: String, slot: int) -> Dictionary:
	var inv: InventoryComponent = get_inventory(player_id)
	if inv == null:
		return _use_refusal(player_id, "", "no inventory")

	var item: Item = inv.get_item(slot)
	if item == null:
		return _use_refusal(player_id, "", "empty slot")

	if item.item_category != Item.ItemCategory.CONSUMABLE:
		return _use_refusal(player_id, item.id, "not consumable")

	var body = _use_body(player_id)
	if body == null:
		return _use_refusal(player_id, item.id, "no body")

	if body.has_method("is_alive") and not body.is_alive():
		return _use_refusal(player_id, item.id, "dead")

	if "level" in body and int(item.required_level) > 0 \
			and int(body.level) < int(item.required_level):
		return _use_refusal(player_id, item.id, "not your level yet")

	if item.buff_effects.is_empty() and str(item.use_skill_id).is_empty():
		return _use_refusal(player_id, item.id, "inert")

	var remaining := _use_cooldown_remaining(player_id, item.id)
	if remaining > 0.0:
		return {
			"ok": false,
			"reason": "cooldown",
			"item_id": item.id,
			"remaining": remaining,
		}

	if not str(item.use_skill_id).is_empty():
		return _use_refusal(player_id, item.id, "skill items route through SkillService (deferred lane)")

	# VALIDATE the whole book before consuming anything.
	var applied: Array = []
	var bad := validate_effects(item)
	if not bad.is_empty():
		return _use_refusal(player_id, item.id, "bad buff book: %s" % ", ".join(bad))

	# Now the books move: ONE charge leaves the slot... (a fail here
	# means the stack vanished between our read and the consume; the
	# bag's own item_removed speakers it, we do not invent a refund
	# for an instant effect already paid because effects only APPLY
	# after the charge left).
	var removed: Item = inv.remove_item(slot, 1)
	if removed == null:
		return _use_refusal(player_id, item.id, "consume failed")

	# ...then the effects land, in book order.
	for buff: Dictionary in item.buff_effects:
		var r := _apply_buff(body, item, buff)
		applied.append(r)

	# The cooldown writes AFTER the drink (an expiry keyed at consume
	# time: the door re-opens exactly item.cooldown later).
	if float(item.cooldown) > 0.0:
		if not _use_cooldowns.has(player_id):
			_use_cooldowns[player_id] = {}
		_use_cooldowns[player_id][item.id] = \
			Time.get_unix_time_from_system() + float(item.cooldown)

	item_used.emit(player_id, removed, applied)
	_persist_inventory(player_id)

	return {"ok": true, "item_id": item.id, "consumed": 1, "applied": applied}

## Return [] when every buff is known and usable; a list of defect
## strings otherwise (honest names, one per bad buff).
func validate_effects(item: Item) -> Array:
	var bad: Array = []
	for i in range(item.buff_effects.size()):
		var buff: Dictionary = item.buff_effects[i]
		var kind := str(buff.get("type", ""))
		var value = buff.get("value", null)
		match kind:
			"instant_heal", "instant_mana", "instant_stamina":
				if value == null or float(value) <= 0.0:
					bad.append("buff[%d] %s needs value > 0" % [i, kind])
			"heal_over_time":
				if value == null or float(value) <= 0.0:
					bad.append("buff[%d] %s needs value > 0" % [i, kind])
				if _effect_duration(item, buff) <= 0.0:
					bad.append("buff[%d] %s needs a duration" % [i, kind])
			"stat_buff":
				if not _STAT_BUFFS.has(str(buff.get("stat", ""))):
					bad.append("buff[%d] unknown stat '%s'" % [i, buff.get("stat", "")])
				elif value == null or float(value) == 0.0:
					bad.append("buff[%d] %s needs a nonzero value" % [i, kind])
				elif _effect_duration(item, buff) <= 0.0:
					bad.append("buff[%d] %s needs a duration" % [i, kind])
			_:
				bad.append("buff[%d] unknown type '%s'" % [i, kind])
	return bad

## Timed effects: the buff's own duration wins, else the item's
## duration field, else nothing (a refusal in validation).
func _effect_duration(item: Item, buff: Dictionary) -> float:
	var d = buff.get("duration", null)
	if d != null and float(d) > 0.0:
		return float(d)
	return max(0.0, float(item.duration))

func _use_refusal(player_id: String, item_id: String, reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "item_id": item_id, "remaining": 0.0}

## The body a use door serves: the registered character entity (the
## server truth), else the local player body (the script-mode truth;
## tests and simulated boots register their own bags).
func _use_body(player_id: String):
	if _use_body_override.is_valid():
		return _use_body_override.call(player_id)
	var es = get_node_or_null("/root/EntityService")
	if es != null and es.has_method("get_entity"):
		var ent = es.get_entity(player_id)
		if ent != null and is_instance_valid(ent):
			return ent
	var pm = get_node_or_null("/root/PlayerManager")
	if pm != null and pm.has_method("get_local_player"):
		var local = pm.get_local_player()
		if local != null and is_instance_valid(local):
			return local
	return null

func _apply_buff(body, item: Item, buff: Dictionary) -> Dictionary:
	var kind := str(buff.get("type", ""))
	var value := float(buff.get("value", 0))
	match kind:
		"instant_heal":
			if body.has_method("heal"):
				body.heal(int(value))
				return {"type": kind, "value": value, "landed": true}
			return {"type": kind, "value": value, "landed": false}
		"instant_mana":
			if body.has_method("restore_mana"):
				body.restore_mana(int(value))
			elif "current_mana" in body:
				var target: int = int(body.current_mana) + int(value)
				if "max_mana" in body:
					target = mini(target, int(body.max_mana))
				body.current_mana = target
			return {"type": kind, "value": value, "landed": true}
		"instant_stamina":
			if body.has_method("restore_stamina"):
				body.restore_stamina(value)
			elif "current_stamina" in body:
				body.current_stamina = float(body.current_stamina) + value
			return {"type": kind, "value": value, "landed": true}
		"heal_over_time":
			return _apply_timed_effect(body, item, buff, kind, value)
		"stat_buff":
			return _apply_timed_effect(body, item, buff, kind, value)
	return {"type": kind, "value": value, "landed": false}

## A timed effect is a real StatusEffect riding the entity's own
## apply_status_effect law (the skill/aura precedent: stat mods in,
## ticks heal, the entity's timers expire it).
func _apply_timed_effect(body, item: Item, buff: Dictionary, kind: String, value: float) -> Dictionary:
	var fx := StatusEffect.new()
	fx.effect_id = item.id + "_" + kind
	fx.effect_name = item.display_name
	if kind == "stat_buff":
		fx.effect_name = "%s (%s)" % [item.display_name, str(buff.get("stat", ""))]
	fx.effect_type = StatusEffect.EffectType.BUFF
	var dur := _effect_duration(item, buff)
	if kind == "stat_buff":
		fx.tick_behavior = StatusEffect.TickBehavior.DURATION
		var export_name: String = _STAT_BUFFS[str(buff.get("stat", ""))]
		var stat := str(buff.get("stat", ""))
		# Float multiplier exports (speed/damage/defense) take the raw
		# float; the stat exports take int points.
		if export_name.ends_with("_multiplier") or export_name.ends_with("_resistance"):
			fx.set(export_name, value)
		else:
			fx.set(export_name, int(value))
	else:
		fx.tick_behavior = StatusEffect.TickBehavior.TICKED
		fx.tick_heal = int(value)
		fx.tick_interval = max(0.1, float(buff.get("interval", 1.0)))
		fx.total_ticks = maxi(1, int(dur / fx.tick_interval))
	if body.has_method("apply_status_effect"):
		fx.duration = dur
		body.apply_status_effect(fx)
		return {"type": kind, "value": value, "duration": dur, "landed": true}
	return {"type": kind, "value": value, "duration": dur, "landed": false}

## The use door's cooldown book read (remaining seconds, 0 = ready).
func _use_cooldown_remaining(player_id: String, item_id: String) -> float:
	if not _use_cooldowns.has(player_id):
		return 0.0
	var exp = _use_cooldowns[player_id].get(item_id, 0.0)
	return max(0.0, float(exp) - Time.get_unix_time_from_system())

## == Persistence ============================================================

func _load_inventories() -> void:
	var store := DictStore.new()
	_player_inventories = {}
	var keys: Array = store.all_keys()
	var inventory_keys: Array = []
	for key in keys:
		if key.begins_with(_kv_prefix):
			inventory_keys.append(key)
	if inventory_keys.is_empty():
		return
	var results: Dictionary = store.get_many(inventory_keys)
	for key in inventory_keys:
		var player_id = key.substr(_kv_prefix.length())
		var data: Dictionary = results.get(key, {})
		if not data.is_empty():
			_player_inventories[player_id] = InventoryComponent.from_dict(data)

func _persist_inventory(player_id: String) -> void:
	var store := DictStore.new()
	if _player_inventories.has(player_id):
		var inv: InventoryComponent = _player_inventories[player_id]
		# A null bag (registered for the no-purse law checks, or a slot
		# freed before its registration was cleaned up) erases its save
		# rather than crashing on to_dict -- a purse that is not held
		# is a purse that does not persist.
		if inv != null:
			store.set_kv(_kv_prefix + player_id, inv.to_dict())
		else:
			store.erase(_kv_prefix + player_id)
	else:
		store.erase(_kv_prefix + player_id)


## Public persist for one player (used by services that mutate an
## InventoryComponent directly, e.g. SkillAcademyService book burns).
func persist_inventory(player_id: String) -> void:
	_persist_inventory(player_id)


func persist_all_inventories() -> void:
	var store := DictStore.new()
	var entries: Dictionary = {}
	for player_id in _player_inventories.keys():
		var inv: InventoryComponent = _player_inventories[player_id]
		entries[_kv_prefix + player_id] = inv.to_dict()
	if not entries.is_empty():
		store.set_batch(entries)
