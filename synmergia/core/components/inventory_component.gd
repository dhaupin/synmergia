## InventoryComponent - Item management
## Attached to entities that can carry items
class_name InventoryComponent
extends Node

signal item_added(item: Item, slot: int)
signal item_removed(item: Item, slot: int)
signal item_swapped(slot1: int, slot2: int)
signal item_bound(item: Item, bind_type: String)	# Emitted when item becomes bound (bind_type: "pickup", "equip", "soulbound")
signal inventory_full()
signal gold_changed(amount: int)

# Weight / Encumbrance
signal weight_changed(current: float, max_weight: float, encumbered: bool)

@export var max_inventory_slots: int = GameConfig.Inventory.DEFAULT_SLOTS
@export var max_equipment_slots: int = GameConfig.Inventory.MAX_EQUIPMENT_SLOTS

var _inventory: Array[Item] = []
var _equipment: Dictionary = {}	 # EquipSlot -> Item
var _gold: int = 0

# Weight / Encumbrance
var _current_weight: float = 0.0
var _max_weight: float = GameConfig.Inventory.DEFAULT_MAX_WEIGHT	# Base carry capacity
var _encumbrance_penalty: float = GameConfig.Inventory.ENCUMBRANCE_PENALTY	# Speed reduction when over weight

func _ready() -> void:
				# Initialize inventory slots
				for i in max_inventory_slots:
								_inventory.append(null)

func _init() -> void:
				pass

## Add item to inventory
func add_item(item: Item, quantity: int = 1) -> bool:
				# Security: Check for item duplication exploit
				if item and item.id != "":
								var exploit_detected := SecurityService.check_item_duplication(_owner_id, item.id, quantity)
								if exploit_detected:
												GameLog.warn("InventoryComponent: Item duplication detected for player %s" % _owner_id)
												return false

				# Try to stack first
				if item.stack_size > 1:
								var stacked := _try_stack_item(item, quantity)
								if stacked >= quantity:
												return true
								quantity -= stacked

				# Check weight limit
				if not can_carry(item):
								return false

				# Find empty slot
				var empty_slot := _find_empty_slot()
				if empty_slot < 0:
								inventory_full.emit()
								EventBus.inventory_full.emit(get_parent())
								return false

				_inventory[empty_slot] = item
				item_added.emit(item, empty_slot)
				EventBus.item_picked_up.emit(get_parent(), item)
				_update_weight(item)
				return true

## Try to stack item with existing stack
func _try_stack_item(item: Item, quantity: int) -> int:
				for i in range(_inventory.size()):
								var slot_item := _inventory[i]
								if slot_item and slot_item.id == item.id:
												var space := slot_item.stack_size - slot_item.current_stack
												if space > 0:
																var to_add := mini(space, quantity)
																var old_stack := slot_item.current_stack
																slot_item.current_stack += to_add
																# Update weight for stacked items
																_current_weight += (slot_item.current_stack - old_stack) * slot_item.weight_per_unit
																weight_changed.emit(_current_weight, _max_weight, is_encumbered())
																return to_add
				return 0

## Find empty inventory slot
func _find_empty_slot() -> int:
				for i in range(_inventory.size()):
								if _inventory[i] == null:
												return i
				return -1

## Remove item from inventory
func remove_item(slot: int, quantity: int = -1) -> Item:
				if slot < 0 or slot >= _inventory.size():
								return null

				var item := _inventory[slot]
				if item == null:
								return null

				if quantity < 0 or quantity >= item.current_stack:
								_inventory[slot] = null
								item_removed.emit(item, slot)
								EventBus.item_dropped.emit(get_parent(), item)
				else:
								item.current_stack -= quantity
								if item.current_stack <= 0:
												_inventory[slot] = null
												item_removed.emit(item, slot)
				
				_update_weight(item, -1)
				return item

## Get item at slot
func get_item(slot: int) -> Item:
				if slot < 0 or slot >= _inventory.size():
								return null
				return _inventory[slot]

## Equip item
func equip_item(inventory_slot: int) -> bool:
				var item := get_item(inventory_slot)
				if item == null or not item.can_equip():
								return false

				var equip_slot := item.equip_slot

				# Unequip current item in that slot
				var old_item := _equipment.get(equip_slot)
				if old_item:
								_equipment[equip_slot] = null
								# Try to put in inventory
								if not add_item(old_item):
												return false	# Can't swap, inventory full

				# Equip new item
				_inventory[inventory_slot] = null
				_equipment[equip_slot] = item

				item_swapped.emit(inventory_slot, equip_slot)

				# Apply equipment stats
				_apply_equipment_stats()

				return true

## Unequip item to inventory
func unequip_item(equip_slot: int) -> bool:
				var item := _equipment.get(equip_slot)
				if item == null:
								return false

				if not add_item(item):
								return false

				_equipment[equip_slot] = null
				_apply_equipment_stats()
				return true

## Get equipped item
func get_equipped(equip_slot: int) -> Item:
				return _equipment.get(equip_slot)

## Get all equipment
func get_all_equipment() -> Dictionary:
				return _equipment.duplicate()

	## Get all equipped items as array
	func get_all_equipped_items() -> Array[Item]:
		var items: Array[Item] = []
		for item in _equipment.values():
			if item:
				items.append(item)
		return items
	
	## Get equipped items with low durability (below threshold)
	func get_low_durability_items(threshold: float = 0.2) -> Array[Item]:
		var items: Array[Item] = []
		for item in _equipment.values():
			if item and item.max_durability > 0 and item.get_durability_percent() < threshold:
				items.append(item)
		return items
	
	## Repair all equipped items (costs gold)
	func repair_all_equipped(gold_per_durability: float = 1.0) -> int:
		var total_cost := 0
		
		for item in _equipment.values():
			if item and item.max_durability > 0 and item.can_repair:
				var missing := item.max_durability - item.current_durability
				if missing > 0:
					var cost := int(missing * gold_per_durability)
					total_cost += cost
					item.repair()
		
		return total_cost
	
	## Repair specific equipped item
	func repair_equipped_item(equip_slot: int, gold_per_durability: float = 1.0) -> int:
		var item: Item = _equipment.get(equip_slot)
		if not item or item.max_durability <= 0 or not item.can_repair:
			return 0
		
		var missing := item.max_durability - item.current_durability
		if missing <= 0:
			return 0
		
		var cost := int(missing * gold_per_durability)
		item.repair()
		return cost
## Add gold
func add_gold(amount: int) -> void:
	# SECURITY: Reject negative or zero amounts
	if amount <= 0:
		return
	_gold += amount
	gold_changed.emit(amount)
	EventBus.gold_changed.emit(get_parent(), amount)

## Remove gold
func remove_gold(amount: int) -> bool:
				if _gold < amount:
								return false
				_gold -= amount
				gold_changed.emit(-amount)
				EventBus.gold_changed.emit(get_parent(), -amount)
				return true

## Get gold
func get_gold() -> int:
				return _gold

## Set gold (for loading saves)
func set_gold(amount: int) -> void:
				_gold = max(0, amount)

## Get total stat contribution from equipment
func get_equipment_stats() -> Dictionary:
				var stats: Dictionary = {}

				for item in _equipment.values():
								if item == null:
												continue
								
								# Use effective stats (0 if broken)
								var effective_stats := item.get_effective_stats()
								
								for stat in effective_stats:
												if not stats.has(stat):
																stats[stat] = 0
												stats[stat] += effective_stats[stat]

				return stats

## Get total armor from equipment (0 if broken)
func get_equipment_armor() -> int:
				var total := 0
				for item in _equipment.values():
								if item:
												total += item.get_effective_armor_value()
				return total

## Get main hand weapon damage range (0 if broken)
func get_main_hand_damage() -> Dictionary:
				var min_dmg := 0
				var max_dmg := 0
				var weapon: Item = _equipment.get(Item.EquipSlot.MAIN_HAND)
				if weapon:
								min_dmg = weapon.get_effective_damage_min()
								max_dmg = weapon.get_effective_damage_max()
				return {"min": min_dmg, "max": max_dmg}

## Get inventory count
func get_inventory_count() -> int:
				var count := 0
				for item in _inventory:
								if item != null:
												count += 1
				return count

## Get free slot count
func get_free_slot_count() -> int:
				var count := 0
				for slot in _inventory:
								if slot == null:
												count += 1
				return count

## Find item in inventory
func find_item(item_id: String) -> int:
				for i in range(_inventory.size()):
								if _inventory[i] and _inventory[i].id == item_id:
												return i
				return -1

## Get all items
func get_all_items() -> Array[Item]:
				var items: Array[Item] = []
				for item in _inventory:
								if item:
												items.append(item)
				return items

## Clear inventory
func clear_inventory() -> void:
				_inventory.clear()
				for i in max_inventory_slots:
								_inventory.append(null)

## Clear equipment
func clear_equipment() -> void:
				_equipment.clear()
				_apply_equipment_stats()

## Apply equipment stats to entity
func _apply_equipment_stats() -> void:
				var entity: SynmergiaEntity = get_parent()
				if entity == null:
								return

				var equipment_stats := get_equipment_stats()
				for stat_name in equipment_stats:
								var value: int = equipment_stats[stat_name]
								entity.add_stat(stat_name, value)

# ============ WEIGHT / ENCUMBRANCE ============

## Get current weight
func get_current_weight() -> float:
				return _current_weight

## Get max weight
func get_max_weight() -> float:
				return _max_weight

## Get encumbrance percentage (0.0 to 1.0+)
func get_encumbrance() -> float:
				if _max_weight <= 0:
								return 0.0
				return _current_weight / _max_weight

## Check if encumbered (over weight limit)
func is_encumbered() -> bool:
				return _current_weight > _max_weight

## Get speed penalty based on encumbrance
func get_speed_penalty() -> float:
				if not is_encumbered():
								return 1.0
				var over := _current_weight - _max_weight
				var penalty := over / _max_weight * _encumbrance_penalty
				return max(0.1, 1.0 - penalty)

## Set max weight (e.g., from strength stat or upgrades)
func set_max_weight(max_w: float) -> void:
				_max_weight = max_w
				weight_changed.emit(_current_weight, _max_weight, is_encumbered())

## Can carry item? (check weight)
func can_carry(item: Item) -> bool:
				var new_weight := item.weight * item.current_stack
				return _current_weight + new_weight <= _max_weight

## Get remaining carry capacity
func get_remaining_capacity() -> float:
				return max(0.0, _max_weight - _current_weight)

## Update weight tracking
func _update_weight(item: Item, direction: int = 1) -> void:
				if direction > 0:
								_current_weight += item.weight * item.current_stack
				else:
								_current_weight -= item.weight * item.current_stack
								_current_weight = max(0.0, _current_weight)
				weight_changed.emit(_current_weight, _max_weight, is_encumbered())

## Recalculate total weight from all items
func recalculate_weight() -> void:
				_current_weight = 0.0
				
				for item in _inventory:
								if item:
												_current_weight += item.weight * item.current_stack
				
				for item in _equipment.values():
								if item:
												_current_weight += item.weight * item.current_stack
				
				weight_changed.emit(_current_weight, _max_weight, is_encumbered())

# ============ BAG EXPANSION ============

# Extra bag slots (can be unlocked)
var _extra_bags: Array[Array] = []
var _unlocked_bags: int = 0
const MAX_BAGS: int = GameConfig.Inventory.MAX_BAGS
const BAG_SIZE: int = GameConfig.Inventory.BAG_SIZE

signal bag_expanded(bag_index: int, new_size: int)
signal bag_locked(bag_index: int)

## Expand inventory with a new bag
func expand_inventory() -> bool:
				if _unlocked_bags >= MAX_BAGS:
								return false

				var new_bag: Array = []
				for i in BAG_SIZE:
								new_bag.append(null)
				_extra_bags.append(new_bag)
				_unlocked_bags += 1

				bag_expanded.emit(_unlocked_bags - 1, BAG_SIZE)
				GameLog.info("InventoryComponent: Expanded inventory with bag %d" % (_unlocked_bags - 1))
				return true

## Get total inventory slots (base + bags)
func get_total_slots() -> int:
				return max_inventory_slots + (_unlocked_bags * BAG_SIZE)

## Get items from a specific bag
func get_bag_items(bag_index: int) -> Array:
				if bag_index < 0 or bag_index >= _extra_bags.size():
								return []
				return _extra_bags[bag_index]

## Add item to bag
func add_item_to_bag(bag_index: int, item: Item, slot: int = -1) -> bool:
				if bag_index < 0 or bag_index >= _extra_bags.size():
								return false

				var bag: Array = _extra_bags[bag_index]

				if slot < 0:
								slot = _find_empty_slot_in_bag(bag)

				if slot < 0 or slot >= bag.size():
								return false

				bag[slot] = item
				return true

## Find empty slot in bag
func _find_empty_slot_in_bag(bag: Array) -> int:
				for i in range(bag.size()):
								if bag[i] == null:
												return i
				return -1

## Is bag unlocked?
func is_bag_unlocked(bag_index: int) -> bool:
				return bag_index < _unlocked_bags

## Get unlocked bag count
func get_unlocked_bag_count() -> int:
				return _unlocked_bags

# ============ BANK / STORAGE ============

var _bank: Array = []
var _bank_size: int = 98
var _bank_expansion_count: int = 0
const MAX_BANK_EXPANSIONS: int = GameConfig.Inventory.MAX_BANK_EXPANSIONS
const BANK_EXPANSION_SIZE: int = 98

signal bank_item_added(item: Item, slot: int)
signal bank_item_removed(item: Item, slot: int)
signal bank_expanded(new_size: int)

## Initialize bank
func init_bank() -> void:
				if _bank.is_empty():
								for i in _bank_size:
												_bank.append(null)

## Add item to bank
func add_to_bank(item: Item, slot: int = -1) -> bool:
				init_bank()

				if item.stack_size > 1:
								var stacked := _try_stack_in_bank(item)
								if stacked >= 1:
												return true

				if slot < 0:
								slot = _find_empty_bank_slot()

				if slot < 0:
								return false

				_bank[slot] = item
				bank_item_added.emit(item, slot)
				return true

## Try to stack item in bank
func _try_stack_in_bank(item: Item) -> int:
				for i in range(_bank.size()):
								var bank_item: Item = _bank[i]
								if bank_item and bank_item.id == item.id:
												var space := bank_item.stack_size - bank_item.current_stack
												if space > 0:
																var to_add := mini(space, item.current_stack)
																bank_item.current_stack += to_add
																item.current_stack -= to_add
																return to_add
				return 0

## Find empty bank slot
func _find_empty_bank_slot() -> int:
				for i in range(_bank.size()):
								if _bank[i] == null:
												return i
				return -1

## Remove item from bank
func remove_from_bank(slot: int) -> Item:
				init_bank()
				if slot < 0 or slot >= _bank.size():
								return null

				var item: Item = _bank[slot]
				_bank[slot] = null
				if item:
								bank_item_removed.emit(item, slot)
				return item

## Get bank item
func get_bank_item(slot: int) -> Item:
				init_bank()
				if slot < 0 or slot >= _bank.size():
								return null
				return _bank[slot]

## Get bank size
func get_bank_size() -> int:
				return _bank_size

## Expand bank
func expand_bank() -> bool:
				if _bank_expansion_count >= MAX_BANK_EXPANSIONS:
								return false

				for i in range(BANK_EXPANSION_SIZE):
								_bank.append(null)

				_bank_size += BANK_EXPANSION_SIZE
				_bank_expansion_count += 1

				bank_expanded.emit(_bank_size)
				GameLog.info("InventoryComponent: Bank expanded to %d slots" % _bank_size)
				return true

## Get all bank items
func get_all_bank_items() -> Array:
				init_bank()
				var items: Array = []
				for item in _bank:
								if item:
												items.append(item)
				return items

## Move item from inventory to bank
func move_to_bank(inv_slot: int, bank_slot: int = -1) -> bool:
				var item: Item = remove_item(inv_slot)
				if not item:
								return false

				if not add_to_bank(item, bank_slot):
								add_item(item)
								return false

				return true

## Move item from bank to inventory
func move_to_inventory(bank_slot: int, inv_slot: int = -1) -> bool:
				var item: Item = remove_from_bank(bank_slot)
				if not item:
								return false

				if inv_slot >= 0:
								var existing: Item = _inventory[inv_slot] if inv_slot < _inventory.size() else null
								_inventory[inv_slot] = item
								if existing:
												add_to_bank(existing)
				else:
								if not add_item(item):
												add_to_bank(item)
												return false

				return true

# ============ ITEM DESTRUCTION / SELLING ============

var _sell_price_multiplier: float = 0.5

signal item_sold(item: Item, gold_amount: int)
signal item_destroyed(item: Item)

## Sell item (removes and gives gold)
func sell_item(slot: int, quantity: int = -1) -> int:
				var item: Item = _inventory[slot]
				if not item:
								return 0

				var price := _calculate_sell_price(item, quantity)

				if quantity < 0 or quantity >= item.current_stack:
								_inventory[slot] = null
								item_removed.emit(item, slot)
				else:
								item.current_stack -= quantity

				add_gold(price)
				item_sold.emit(item, price)
				GameLog.info("InventoryComponent: Sold %s for %d gold" % [item.display_name, price])

				return price

## Calculate sell price
func _calculate_sell_price(item: Item, quantity: int = -1) -> int:
				var base_price: int = item.get("vendor_price", 1)
				if quantity < 0:
								quantity = item.current_stack
				return int(base_price * _sell_price_multiplier * quantity)

## Destroy item (removes without gold)
func destroy_item(slot: int, quantity: int = -1) -> bool:
				var item: Item = _inventory[slot]
				if not item:
								return false

				if quantity < 0 or quantity >= item.current_stack:
								_inventory[slot] = null
								item_removed.emit(item, slot)
								GameLog.info("InventoryComponent: Destroyed %s" % item.display_name)
				else:
								item.current_stack -= quantity
								GameLog.info("InventoryComponent: Destroyed %d x %s" % [quantity, item.display_name])

				item_destroyed.emit(item)
				return true

## Set sell price multiplier
func set_sell_price_multiplier(multiplier: float) -> void:
				_sell_price_multiplier = clamp(multiplier, 0.0, 1.0)

## Get item value
func get_item_value(item: Item) -> int:
				return item.get("vendor_price", 1) * _sell_price_multiplier

## Sell all items of type
func sell_all_of_type(item_id: String) -> int:
				var total := 0
				for i in range(_inventory.size()):
								var item: Item = _inventory[i]
								if item and item.id == item_id:
												total += sell_item(i)
				return total

## Destroy all items of type
func destroy_all_of_type(item_id: String) -> int:
				var count := 0
				for i in range(_inventory.size()):
								var item: Item = _inventory[i]
								if item and item.id == item_id:
												destroy_item(i)
												count += 1
				return count
