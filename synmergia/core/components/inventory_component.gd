## InventoryComponent - Item management
## Attached to entities that can carry items
class_name InventoryComponent
extends Node

signal item_added(item: Item, slot: int)
signal item_removed(item: Item, slot: int)
signal item_swapped(slot1: int, slot2: int)
signal inventory_full()
signal gold_changed(amount: int)

@export var max_inventory_slots: int = 20
@export var max_equipment_slots: int = 12

var _inventory: Array[Item] = []
var _equipment: Dictionary = {}  # EquipSlot -> Item
var _gold: int = 0

func _ready() -> void:
	# Initialize inventory slots
	for i in max_inventory_slots:
		_inventory.append(null)

func _init() -> void:
	pass

## Add item to inventory
func add_item(item: Item, quantity: int = 1) -> bool:
	# Try to stack first
	if item.stack_size > 1:
		var stacked := _try_stack_item(item, quantity)
		if stacked >= quantity:
			return true
		quantity -= stacked
	
	# Find empty slot
	var empty_slot := _find_empty_slot()
	if empty_slot < 0:
		inventory_full.emit()
		EventBus.inventory_full.emit(get_parent())
		return false
	
	_inventory[empty_slot] = item
	item_added.emit(item, empty_slot)
	EventBus.item_picked_up.emit(get_parent(), item)
	return true

## Try to stack item with existing stack
func _try_stack_item(item: Item, quantity: int) -> int:
	for i in range(_inventory.size()):
		var slot_item := _inventory[i]
		if slot_item and slot_item.id == item.id:
			var space := slot_item.stack_size - slot_item.current_stack
			if space > 0:
				var to_add := min(space, quantity)
				slot_item.current_stack += to_add
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
		return item
	else:
		item.current_stack -= quantity
		if item.current_stack <= 0:
			_inventory[slot] = null
			item_removed.emit(item, slot)
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
			return false  # Can't swap, inventory full
	
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

## Add gold
func add_gold(amount: int) -> void:
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
		
		for stat in item.stats:
			if not stats.has(stat):
				stats[stat] = 0
			stats[stat] += item.stats[stat]
		
		for stat in item.primary_stats:
			if not stats.has(stat):
				stats[stat] = 0
			stats[stat] += item.primary_stats[stat]
	
	return stats

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
	var entity: Entity = get_parent()
	if entity == null:
		return
	
	var stats := get_equipment_stats()
	
	# TODO: Apply these to entity's calculated stats
	# This would modify the entity's effective stats
