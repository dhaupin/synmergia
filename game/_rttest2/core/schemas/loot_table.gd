## LootTable - Drop tables for enemies and containers
## Defines what items/currency can drop and their probabilities
## entries and currency_drops are exported arrays -- .tres files define them declaratively
extends Resource
class_name LootTable

# Loot table metadata
@export var id: String = ""
@export var name: String = ""
@export var description: String = ""

# Drop configuration -- serializable arrays for .tres files
@export var entries: Array[Dictionary] = []
@export var currency_drops: Array[Dictionary] = []

# Drop rate modifiers
@export var base_drop_chance: float = 1.0
@export var bonus_drop_per_level: float = 0.01
@export var max_bonus_drop: float = 0.5

# Loot rules
@export var auto_loot: bool = false
@export var share_loot: bool = true
@export var need_before_greed: bool = false

# Table-level constraints
@export var min_items_dropped: int = 0
@export var max_items_dropped: int = 10
@export var level: int = 1

# Rarity weights
@export var rarity_weights: Dictionary = {
	"COMMON": 1.0,
	"UNCOMMON": 0.5,
	"RARE": 0.2,
	"EPIC": 0.05,
	"LEGENDARY": 0.01
}

func _init() -> void:
	if id == "":
		id = name.to_lower().replace(" ", "_")

## Get guaranteed drops only
func get_guaranteed_drops() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for d in entries:
		if d.get("is_guaranteed", false):
			result.append(d)
	return result

## Get conditional drops for a context
func get_conditional_drops(context: Dictionary = {}) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for d in entries:
		var conditions: Array = d.get("conditions", [])
		if conditions.is_empty():
			continue
		var meets_all := true
		for c in conditions:
			if not context.get(c, false):
				meets_all = false
				break
		if meets_all:
			result.append(d)
	return result

## Calculate drop chance with level scaling
func calculate_drop_chance(player_level: int) -> float:
	var bonus := mini((player_level - level) * bonus_drop_per_level, max_bonus_drop)
	return mini(base_drop_chance + bonus, 1.0)

## Roll for drops
func roll_drop(rng: RandomNumberGenerator = null) -> Dictionary:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()

	var result := {
		"items": [],
		"currency": {},
		"rolled": false,
		"got_any": false
	}

	if randf() <= base_drop_chance:
		result.rolled = true

		for d in entries:
			if d.get("is_guaranteed", false):
				var qty := rng.randi_range(d.get("min_quantity", 1), d.get("max_quantity", 1))
				result.items.append({"item_id": d.get("item_id", ""), "quantity": qty})
				result.got_any = true

		var n := mini(entries.size(), rng.randi_range(min_items_dropped, max_items_dropped))
		for i in range(n):
			var d: Dictionary = entries[rng.randi() % entries.size()]
			if randf() <= d.get("drop_rate", 1.0):
				var qty := rng.randi_range(d.get("min_quantity", 1), d.get("max_quantity", 1))
				result.items.append({"item_id": d.get("item_id", ""), "quantity": qty})
				result.got_any = true

	for d in currency_drops:
		if d.get("is_guaranteed", false) or randf() <= d.get("drop_rate", 1.0):
			var amount := rng.randi_range(d.get("min_amount", 0), d.get("max_amount", 0))
			var cid: String = d.get("currency_id", "gold")
			result.currency[cid] = result.currency.get(cid, 0) + amount
			result.got_any = true

	return result

## Get all possible items from this table
func get_all_possible_items() -> Array[String]:
	var items: Array[String] = []
	for d in entries:
		var iid: String = d.get("item_id", "")
		if not iid.is_empty() and not items.has(iid):
			items.append(iid)
	return items

## Get total drop weight
func get_total_drop_weight() -> float:
	var total := 0.0
	for d in entries:
		total += d.get("drop_rate", 1.0) * d.get("rarity_weight", 1.0)
	return total
