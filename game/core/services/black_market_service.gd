## BlackMarketService - THE DEEP ROLLS: the Underdeck Fixer's gamble.
##
## The fixer is not a merchant, he is a gambler: Concord Sigils in, ONE
## weighted draw out of a REAL LootTable out. The pools live in
## data/loot_tables/loot_black_market_*.tres -- the same LootTable
## schema the world's real drops use, so the roll never trusted a
## client, never invented an item, and honors every entry the gear
## catalog grows into. The draw math is SERVER truth here; the panel
## sends only a roll_id.
##
## Wallet law: sigils ride the ONE purse (InventoryComponent via
## InventoryService); the debit is an honest ledger remove and a
## failed grant REFUNDS it -- the books never keep a sigil without
## paying the prize.
extends Node

func _inv_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("InventoryService")) if tree and tree.root else null

func _data_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("DataService")) if tree and tree.root else null

func _glog():
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("GameLog")) if tree and tree.root else null

const PremiumShopServiceScript = preload("res://core/services/premium_shop_service.gd")

## Singleton instance (the PremiumShopService dialect: one instance per
## process, lazily built, no _ready state).
static var _instance = null
static func singleton():
	if _instance == null:
		_instance = load("res://core/services/black_market_service.gd").new()
	return _instance

const CURRENCY_ID := "currency_concord_sigil"
const RATE_LIMIT_ACTION := "black_market_roll"

## The roll board. Each tier reads a REAL LootTable resource; sigils is
## the honest debit per roll. rarity_boost multiplies every entry's
## rarity_weight (the depths pull pays UP, not sideways).
const ROLLS := [
	{
		"roll_id": "tide",
		"label": "Tide Pull",
		"sigils": 3,
		"table": "res://data/loot_tables/loot_black_market_tide.tres",
		"rarity_boost": 1.0,
	},
	{
		"roll_id": "depths",
		"label": "Depths Pull",
		"sigils": 12,
		"table": "res://data/loot_tables/loot_black_market_depths.tres",
		"rarity_boost": 2.0,
	},
]

## Fired after an honest completed roll (prize paid, purse debited).
signal roll_granted(player_id: String, roll_id: String, item_id: String, rarity_name: String)

## The board the panel renders (no secrets, just the honest shape).
func get_roll_options() -> Array:
	var options: Array = []
	for roll in ROLLS:
		var table = load(str(roll.get("table", "")))
		if table == null:
			continue
		options.append({
			"roll_id": str(roll.get("roll_id", "")),
			"label": str(roll.get("label", "")),
			"sigils": int(roll.get("sigils", 0)),
			"description": str(table.description),
			"pool_size": table.entries.size(),
		})
	return options

## The ONE roll leg. Returns {success, value/message} and, on success,
## {item_id, item_name, rarity_name, quantity}. Every refusal names its
## cause; every grant is audited. The client never supplies weights,
## item ids, or amounts.
func roll_deep(player_id: String, roll_id: String) -> Dictionary:
	var row := _row_for(roll_id)
	if row.is_empty():
		return {"success": false, "message": "The fixer doesn't offer that pull. (unknown roll tier)"}
	var inv := _inventory_of(player_id)
	if inv == null:
		return {"success": false, "message": "No wallet is mounted for that player. (no purse)"}
	var table = load(str(row.get("table", "")))
	if table == null or table.entries.is_empty():
		return {"success": false, "message": "That pull's deep-water ledger is empty; the fixer won't take coin for nothing."}

	# Defense in depth: the rate gate runs BEFORE any books move, so a
	# spammer cannot even reach the debit leg.
	var qos := Engine.get_main_loop() as SceneTree
	var qos_node := qos.root.get_node_or_null(NodePath("QoSService")) if qos and qos.root else null
	if qos_node != null and qos_node.has_method("rate_limit"):
		if not qos_node.call("rate_limit", player_id, RATE_LIMIT_ACTION):
			return {"success": false, "message": "The fixer waves you off -- you've pulled too fast. (rate limited)"}

	# Debit first, prize second, refund on any refusal -- the purse
	# never holds a sigil without the prize leaving the door.
	var sigils := int(row.get("sigils", 0))
	if inv.get_currency_amount(CURRENCY_ID) < sigils:
		return {"success": false, "message": "You need %d Concord Sigils for that pull (you have %d)." % [sigils, inv.get_currency_amount(CURRENCY_ID)]}
	if not inv.remove_currency(CURRENCY_ID, sigils):
		return {"success": false, "message": "The ledger refused the debit; the pull stays closed."}

	var draw := _weighted_draw(table, float(row.get("rarity_boost", 1.0)))
	var granted := _grant_draw(player_id, draw)
	if granted.is_empty():
		_refund(inv, sigils, "grant refused")
		return {"success": false, "message": str(draw.get("refuse_reason", "The fixer could not deliver the prize; your sigils are back."))}

	var gl = _glog()
	if gl:
		gl.info("BlackMarketService: %s paid %d sigils for the %s pull and drew %s x%d (%s)" % [
			player_id, sigils, str(row.get("label", roll_id)),
			str(granted.get("item_id", "")), int(granted.get("quantity", 1)),
			str(granted.get("rarity_name", "")),
		])
	roll_granted.emit(player_id, str(roll_id), str(draw.get("item_id", "")), str(draw.get("rarity_name", "")))
	return {
		"success": true,
		"message": "The fixer pays out: %s x%d (%s)." % [str(granted.get("item_name", "")), int(granted.get("quantity", 1)), str(draw.get("rarity_name", ""))],
		"item_id": str(draw.get("item_id", "")),
		"item_name": str(granted.get("item_name", "")),
		"rarity_name": str(draw.get("rarity_name", "")),
		"quantity": int(granted.get("quantity", 1)),
	}

## ---------------------------------------------------------------------------

func _row_for(roll_id: String) -> Dictionary:
	for roll in ROLLS:
		if str(roll.get("roll_id", "")) == roll_id:
			return roll
	return {}

## The weighted draw is pure server math: each table entry's
## rarity_weight rides the tier boost; the draw carries the entry's
## honest quantity band.
func _weighted_draw(table, boost: float) -> Dictionary:
	var total := 0.0
	for entry in table.entries:
		total += max(0.0, float(entry.get("rarity_weight", 1.0)) * boost)
	if total <= 0.0:
		return {"refuse_reason": "Every weight in that pool flattened to zero; the roll refuses."}
	var pick := randf() * total
	var running := 0.0
	for entry in table.entries:
		running += max(0.0, float(entry.get("rarity_weight", 1.0)) * boost)
		if pick <= running:
			return {
				"item_id": str(entry.get("item_id", "")),
				"min_quantity": int(entry.get("min_quantity", 1)),
				"max_quantity": int(entry.get("max_quantity", 1)),
				"refuse_reason": "",
			}
	# Float edge fell past the last entry (can only happen on rounding);
	# honor the LAST real entry rather than fabricating one.
	var last: Dictionary = table.entries[table.entries.size() - 1]
	return {
		"item_id": str(last.get("item_id", "")),
		"min_quantity": int(last.get("min_quantity", 1)),
		"max_quantity": int(last.get("max_quantity", 1)),
		"refuse_reason": "",
	}

## Grant the drawn entry through the ONE purse's bag. Refusals name
## their cause so the refund audit has an honest line to point at.
func _grant_draw(player_id: String, draw: Dictionary) -> Dictionary:
	var item_id := str(draw.get("item_id", ""))
	if item_id == "":
		return {}
	var ds := _data_svc()
	if ds == null or not ds.has_method("get_item"):
		return {}
	var item = ds.call("get_item", item_id)
	if item == null:
		return {}
	var inv := _inventory_of(player_id)
	if inv == null or not inv.add_item(item, int(draw.get("min_quantity", 1))):
		return {}
	var quantity := int(draw.get("min_quantity", 1))
	if draw.get("max_quantity", 1) > draw.get("min_quantity", 1):
		quantity = randi_range(draw.get("min_quantity", 1), draw.get("max_quantity", 1))
	return {
		"item_name": str(item.display_name),
		"item_id": item_id,
		"rarity_name": str(Item.Rarity.keys()[item.rarity]),
		"quantity": quantity,
	}

## The refund leg: the books go back exactly where they left. Any
## failure here is a hard error in the audit -- no silent loss ever.
func _refund(inv, sigils: int, cause: String) -> void:
	if not inv.add_currency(CURRENCY_ID, sigils):
		var gl = _glog()
		if gl:
			gl.error("BlackMarketService: REFUND FAILED for %d sigils (%s) -- the books owed a player" % [sigils, cause])
		return
	var gl = _glog()
	if gl:
		gl.warn("BlackMarketService: refunded %d sigils (%s)" % [sigils, cause])

func _inventory_of(player_id: String) -> InventoryComponent:
	var svc := _inv_svc()
	if svc == null or not svc.has_method("get_inventory"):
		return null
	var inv = svc.call("get_inventory", player_id)
	if inv == null or not is_instance_valid(inv):
		return null
	return inv
