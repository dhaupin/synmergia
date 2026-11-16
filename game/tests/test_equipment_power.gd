## test_equipment_power.gd - the equipped weapon and armor reach the live
## player combat surface (not just the item catalog).
##
## Run headless:
##   godot --headless --path game --script res://tests/test_equipment_power.gd
## Exit 0 = all pass.
extends SceneTree

const PlayerBaseScript = preload("res://entities/player/player_base.gd")
const InventoryComponentScript = preload("res://core/components/inventory_component.gd")
const ItemScript = preload("res://core/schemas/item.gd")

var _pass := 0
var _fail := 0

func _initialize() -> void:
	await process_frame
	await _run()
	print("--- EQUIPMENT POWER: %d passed, %d failed ---" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  [FAIL] ", msg)

func _weapon() -> Resource:
	var item = ItemScript.new()
	item.id = "test_sword"
	item.display_name = "Test Sword"
	item.equip_slot = ItemScript.EquipSlot.MAIN_HAND
	item.weapon_type = ItemScript.WeaponType.SWORD
	item.weapon_damage_min = 10
	item.weapon_damage_max = 20
	item.max_durability = 100
	item.current_durability = 100
	return item

func _armor() -> Resource:
	var item = ItemScript.new()
	item.id = "test_chest"
	item.display_name = "Test Chest"
	item.equip_slot = ItemScript.EquipSlot.CHEST
	item.armor_type = ItemScript.ArmorType.PLATE
	item.armor_value = 12
	item.max_durability = 100
	item.current_durability = 100
	return item

func _run() -> void:
	var player = PlayerBaseScript.new()
	player.name = "EquipmentProbePlayer"
	root.add_child(player)
	await process_frame

	# Strength 10 x 2, no weapon yet.
	_assert(player.get_attack_power() == 20, "unarmed attack power is strength x 2")

	var bag = InventoryComponentScript.new()
	bag.name = "Inventory"
	player.add_child(bag)
	player.set("inventory_component", bag)

	var sword = _weapon()
	bag.add_item(sword)
	_assert(bag.equip_item(0), "a main-hand weapon equips")
	# Strength 20 + average (10,20) = 35. Weapon damage is no longer inert.
	_assert(player.get_attack_power() == 35,
		"the equipped weapon's average damage joins attack power (got %d, range %s)" % [player.get_attack_power(), str(bag.get_main_hand_damage())])

	var chest = _armor()
	bag.add_item(chest)
	_assert(bag.equip_item(0), "a chest piece equips")
	_assert(bag.get_equipment_armor() == 12, "equipment armor reaches the armor total")

	# add_item stores a per-slot duplicate (the quantity law), so break the
	# equipped instances, not the source resources.
	var equipped_sword = bag.get_equipped(ItemScript.EquipSlot.MAIN_HAND)
	var equipped_chest = bag.get_equipped(ItemScript.EquipSlot.CHEST)
	equipped_sword.current_durability = 0
	_assert(player.get_attack_power() == 20, "a broken weapon contributes no attack power")
	equipped_chest.current_durability = 0
	_assert(bag.get_equipment_armor() == 0,
		"broken armor contributes no armor (got %d)" % bag.get_equipment_armor())

	player.queue_free()
