## LootTable - Drop tables for enemies and containers
## Defines what items/currency can drop and their probabilities
class_name LootTable
extends Resource

## Individual loot entry
class LootEntry:
		var item_id: String
		var min_quantity: int
		var max_quantity: int
		var drop_rate: float  # 0.0 to 1.0
		var rarity_weight: float  # Multiplier for rarity-based rolls
		var is_guaranteed: bool
		var conditions: Array[String]  # e.g., ["boss", "elite"]
		
		func _init(p_item_id: String = "", p_min: int = 1, p_max: int = 1, 
					p_drop_rate: float = 1.0, p_rarity_weight: float = 1.0,
					p_guaranteed: bool = false, p_conditions: Array[String] = []):
				item_id = p_item_id
				min_quantity = p_min
				max_quantity = p_max
				drop_rate = p_drop_rate
				rarity_weight = p_rarity_weight
				is_guaranteed = p_guaranteed
				conditions = p_conditions

## Currency drop entry
class CurrencyDrop:
		var currency_id: String  # e.g., "gold", "gems"
		var min_amount: int
		var max_amount: int
		var drop_rate: float
		var is_guaranteed: bool
		
		func _init(p_currency_id: String = "", p_min: int = 0, p_max: int = 0,
					p_drop_rate: float = 1.0, p_guaranteed: bool = false):
				currency_id = p_currency_id
				min_amount = p_min
				max_amount = p_max
				drop_rate = p_drop_rate
				is_guaranteed = p_guaranteed

# Loot table metadata
@export var id: String = ""
@export var name: String = ""
@export var description: String = ""

# Drop configuration
@export var entries: Array[LootEntry] = []
@export var currency_drops: Array[CurrencyDrop] = []

# Drop rate modifiers
@export var base_drop_chance: float = 1.0  # Overall chance to drop anything
@export var bonus_drop_per_level: float = 0.01  # +1% per player level above table level
@export var max_bonus_drop: float = 0.5  # Cap at +50%

# Loot rules
@export var auto_loot: bool = false  # If true, items go directly to inventory
@export var share_loot: bool = true  # If true in party, loot is shared
@export var need_before_greed: bool = false  # Enable NBG system

# Table-level constraints
@export var min_items_dropped: int = 0
@export var max_items_dropped: int = 10
@export var level: int = 1  # Table level for scaling

# Rarity weights (used during roll)
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

## Add a loot entry
func add_entry(item_id: String, min_qty: int = 1, max_qty: int = 1, 
               drop_rate: float = 1.0, rarity_weight: float = 1.0,
               guaranteed: bool = false, conditions: Array[String] = []) -> void:
		var entry := LootEntry.new(item_id, min_qty, max_qty, drop_rate, rarity_weight, guaranteed, conditions)
		entries.append(entry)

## Add a currency drop
func add_currency(currency_id: String, min_amt: int, max_amt: int, 
                  drop_rate: float = 1.0, guaranteed: bool = false) -> void:
		var drop := CurrencyDrop.new(currency_id, min_amt, max_amt, drop_rate, guaranteed)
		currency_drops.append(drop)

## Get guaranteed drops only
func get_guaranteed_drops() -> Array[LootEntry]:
		var guaranteed: Array[LootEntry] = []
		for entry in entries:
				if entry.is_guaranteed:
						guaranteed.append(entry)
		return guaranteed

## Get conditional drops for a context
func get_conditional_drops(context: Dictionary = {}) -> Array[LootEntry]:
		var conditional: Array[LootEntry] = []
		for entry in entries:
				if entry.conditions.is_empty():
						continue
				var meets_all := true
				for condition in entry.conditions:
						if not context.get(condition, false):
								meets_all = false
								break
				if meets_all:
						conditional.append(entry)
		return conditional

## Calculate drop chance with level scaling
func calculate_drop_chance(player_level: int) -> float:
		var level_diff := player_level - level
		var bonus := level_diff * bonus_drop_per_level
		bonus = mini(bonus, max_bonus_drop)
		return mini(base_drop_chance + bonus, 1.0)

## Roll for a single drop
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
		
		# Roll for any drops
		if randf() <= base_drop_chance:
				result.rolled = true
				
				# Roll for guaranteed drops
				for entry in entries:
						if entry.is_guaranteed:
								var qty := rng.randi_range(entry.min_quantity, entry.max_quantity)
								result.items.append({"item_id": entry.item_id, "quantity": qty})
								result.got_any = true
				
				# Roll for random drops (up to max)
				var drops_to_roll := mini(entries.size(), rng.randi_range(min_items_dropped, max_items_dropped))
				for i in range(drops_to_roll):
						var entry: LootEntry = entries[rng.randi() % entries.size()]
						if randf() <= entry.drop_rate:
								var qty := rng.randi_range(entry.min_quantity, entry.max_quantity)
								result.items.append({"item_id": entry.item_id, "quantity": qty})
								result.got_any = true
		
		# Roll currency drops
		for currency in currency_drops:
				if currency.is_guaranteed or randf() <= currency.drop_rate:
						var amount := rng.randi_range(currency.min_amount, currency.max_amount)
						result.currency[currency.currency_id] = result.currency.get(currency.currency_id, 0) + amount
						result.got_any = true
		
		return result

## Get all possible items from this table
func get_all_possible_items() -> Array[String]:
		var items: Array[String] = []
		for entry in entries:
				if not items.has(entry.item_id):
						items.append(entry.item_id)
		return items

## Get total drop weight for calculations
func get_total_drop_weight() -> float:
		var total := 0.0
		for entry in entries:
				total += entry.drop_rate * entry.rarity_weight
		return total
