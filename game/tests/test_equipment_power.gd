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
const CombatMath = preload("res://core/services/combat_math.gd")

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

func _approx(a: float, b: float, eps: float = 0.0001) -> bool:
	return absf(a - b) <= eps

func _weapon() -> Resource:
	var item = ItemScript.new()
	item.id = "test_sword"
	item.display_name = "Test Sword"
	item.equip_slot = ItemScript.EquipSlot.MAIN_HAND
	item.weapon_type = ItemScript.WeaponType.SWORD
	item.weapon_damage_min = 10
	item.weapon_damage_max = 20
	item.attack_speed = 1.2
	item.crit_chance = 0.10
	item.crit_damage = 0.25
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
	item.damage_resists = {"fire": 0.2}
	item.max_durability = 100
	item.current_durability = 100
	return item

func _shield() -> Resource:
	var item = ItemScript.new()
	item.id = "test_shield"
	item.display_name = "Test Shield"
	item.equip_slot = ItemScript.EquipSlot.OFF_HAND
	item.weapon_type = ItemScript.WeaponType.SHIELD
	item.shield_type = ItemScript.ShieldType.NORMAL
	item.armor_value = 10
	item.block_rating = 45.0
	item.damage_resists = {"physical": 0.1}
	item.max_durability = 100
	item.current_durability = 100
	return item

func _two_handed() -> Resource:
	var item = _weapon()
	item.id = "test_greatsword"
	item.display_name = "Test Greatsword"
	item.is_two_handed = true
	return item

func _wrist_shield() -> Resource:
	var item = _shield()
	item.id = "test_wristguard"
	item.display_name = "Test Wristguard"
	item.shield_type = ItemScript.ShieldType.WRIST
	item.armor_value = 4
	item.block_rating = 12.0
	item.damage_resists = {"physical": 0.03}
	return item

func _run() -> void:
	var player = PlayerBaseScript.new()
	player.name = "EquipmentProbePlayer"
	root.add_child(player)
	await process_frame

	# Strength 10 x 2, no weapon yet. Capture the body's class-applied base
	# before gear so the assertions test the GEAR delta, not a class constant.
	_assert(player.get_attack_power() == 20, "unarmed attack power is strength x 2")
	var base_speed: float = player.get_attack_speed()
	var base_crit: float = player.get_crit_chance()
	var base_crit_mult: float = player.get_crit_multiplier()
	var base_phys_resist: float = float(player.stats.get("resist_physical", 0.0))

	var bag = InventoryComponentScript.new()
	bag.name = "Inventory"
	player.add_child(bag)
	player.set("inventory_component", bag)

	var sword = _weapon()
	bag.add_item(sword)
	_assert(bag.equip_item(0), "a main-hand weapon equips")

	# The swing rolls inside 10..20; strength 10 x 2 is the base. Run enough
	# samples to prove the whole band is reachable, not just an average.
	var low := 9999
	var high := -1
	var distinct := {}
	for i in range(60):
		var roll := player.get_attack_power()
		low = mini(low, roll)
		high = maxi(high, roll)
		distinct[roll] = true
	_assert(low >= 30 and high <= 40,
		"weapon damage rolls between min and max (got %d..%d, expected 30..40)" % [low, high])
	_assert(distinct.size() > 2, "weapon damage is a real per-swing roll, not the average")

	# Inverted authored bounds are normalized, so a max below min can never
	# produce an impossible roll.
	var equipped_sword = bag.get_equipped(ItemScript.EquipSlot.MAIN_HAND)
	equipped_sword.weapon_damage_min = 30
	equipped_sword.weapon_damage_max = 10
	_assert(equipped_sword.get_effective_damage_min() == 10 \
		and equipped_sword.get_effective_damage_max() == 30,
		"an inverted damage range is normalized to lower..higher")
	var inverted_low := 9999
	var inverted_high := -1
	for i in range(30):
		var roll2 := player.get_attack_power()
		inverted_low = mini(inverted_low, roll2)
		inverted_high = maxi(inverted_high, roll2)
	_assert(inverted_low >= 30 and inverted_high <= 50,
		"an inverted range still rolls inside the normalized band (got %d..%d)" % [inverted_low, inverted_high])
	equipped_sword.weapon_damage_min = 10
	equipped_sword.weapon_damage_max = 20

	# Weapon cadence rides the body's class base by default and overrides it
	# with its own multiplier. Weapon crit is added to the body's crit delta.
	_assert(_approx(player.get_attack_speed(), base_speed * 1.2),
		"weapon cadence multiplies the body's class cadence (got %.3f, base %.3f)" % [player.get_attack_speed(), base_speed])
	_assert(_approx(player.get_crit_chance(), base_crit + 0.10),
		"weapon crit chance adds to the body's crit delta (got %.3f, base %.3f)" % [player.get_crit_chance(), base_crit])
	_assert(_approx(player.get_crit_multiplier(), base_crit_mult + 0.25),
		"weapon crit damage adds to the body's crit multiplier")

	var chest = _armor()
	bag.add_item(chest)
	_assert(bag.equip_item(0), "a chest piece equips")
	_assert(bag.get_equipment_armor() == 12, "equipment armor reaches the armor total")
	_assert(_approx(float(bag.get_equipment_stats().get("resist_fire", 0.0)), 0.2),
		"armor per-school resist reaches the equipment stat block")
	_assert(_approx(CombatMath.school_resist_for(player, "fire"), 0.2),
		"the combat pipeline sees the armor's fire ward")

	# add_item stores a per-slot duplicate (the quantity law), so break the
	# equipped instances, not the source resources.
	var equipped_chest = bag.get_equipped(ItemScript.EquipSlot.CHEST)
	equipped_sword.current_durability = 0
	_assert(player.get_attack_power() == 20, "a broken weapon contributes no attack power")
	_assert(_approx(player.get_crit_chance(), base_crit),
		"a broken weapon contributes no crit chance")
	_assert(_approx(player.get_attack_speed(), base_speed),
		"a broken weapon contributes no cadence override")
	equipped_chest.current_durability = 0
	_assert(bag.get_equipment_armor() == 0,
		"broken armor contributes no armor (got %d)" % bag.get_equipment_armor())
	_assert(_approx(float(bag.get_equipment_stats().get("resist_fire", 0.0)), 0.0),
		"broken armor contributes no resist")

	var shield = _shield()
	bag.add_item(shield)
	_assert(bag.equip_item(0), "an off-hand shield equips")
	_assert(CombatMath._has_shield(player), "a shield in the off hand opens the block lane")
	_assert(bag.get_equipment_armor() == 10,
		"shield armor value joins the equipment armor total (got %d)" % bag.get_equipment_armor())
	_assert(_approx(float(player.stats.get("block_rating", 0.0)), 45.0),
		"shield block rating reaches the body's stat block")
	_assert(_approx(CombatMath.school_resist_for(player, "physical"), base_phys_resist + 0.1),
		"shield physical ward is canonical on the body")

	# A broken shield is no longer a shield lane.
	var equipped_shield = bag.get_equipped(ItemScript.EquipSlot.OFF_HAND)
	equipped_shield.current_durability = 0
	_assert(not CombatMath._has_shield(player),
		"a broken shield stops opening the block lane")
	_assert(bag.get_equipment_armor() == 0,
		"a broken shield contributes no armor")

	# An off-hand that is not a shield must not open the block lane.
	var offhand_orb = ItemScript.new()
	offhand_orb.id = "test_orb"
	offhand_orb.display_name = "Test Orb"
	offhand_orb.equip_slot = ItemScript.EquipSlot.OFF_HAND
	offhand_orb.weapon_type = ItemScript.WeaponType.WAND
	offhand_orb.max_durability = 100
	offhand_orb.current_durability = 100
	bag.add_item(offhand_orb)
	_assert(bag.equip_item(bag.find_item("test_orb")), "an off-hand orb equips")
	_assert(not CombatMath._has_shield(player),
		"a non-shield off hand does not count as a shield")

	# A pre-canonical save stored every weapon in off-hand 8. Loading it must
	# move the hand weapon to main-hand 7, or old characters lose their weapon.
	var legacy = InventoryComponentScript.from_dict({
		"equipment": {
			"8": {
				"id": "legacy_sword",
				"display_name": "Legacy Sword",
				"equip_slot": 8,
				"weapon_type": 1,
				"weapon_damage_min": 5,
				"weapon_damage_max": 9,
				"current_durability": 100,
				"max_durability": 100,
			}
		},
		"inventory": [],
	})
	_assert(legacy.get_equipped(ItemScript.EquipSlot.MAIN_HAND) != null,
		"a legacy off-hand weapon migrates to main hand on load")
	_assert(legacy.get_equipped(ItemScript.EquipSlot.OFF_HAND) == null,
		"the migrated weapon no longer sits in the off hand")
	legacy.free()

	# --- Two-handed / wrist-shield hand law -----------------------------
	var hand_player = PlayerBaseScript.new()
	hand_player.name = "HandLawProbePlayer"
	root.add_child(hand_player)
	await process_frame
	var hand_bag = InventoryComponentScript.new()
	hand_bag.name = "Inventory"
	hand_player.add_child(hand_bag)
	hand_player.set("inventory_component", hand_bag)

	var greatsword = _two_handed()
	hand_bag.add_item(greatsword)
	_assert(hand_bag.equip_item(0), "a two-handed weapon equips in the main hand")
	var normal_shield = _shield()
	hand_bag.add_item(normal_shield)
	_assert(not hand_bag.equip_item(hand_bag.find_item("test_shield")),
		"a normal shield is illegal beside a two-handed weapon")
	var wrist = _wrist_shield()
	hand_bag.add_item(wrist)
	_assert(hand_bag.equip_item(hand_bag.find_item("test_wristguard")),
		"a wrist shield is legal beside a two-handed weapon")
	_assert(CombatMath._has_shield(hand_player), "a wrist shield opens the block lane")
	_assert(_approx(CombatMath._shield_block_scale(hand_player), 0.4),
		"a wrist shield contributes only the lesser block fraction")

	# Loading an illegal saved pair (two-handed + normal shield) returns the
	# normal shield to the bag instead of leaving both hands live.
	var illegal = InventoryComponentScript.from_dict({
		"equipment": {
			"7": {
				"id": "saved_greatsword",
				"display_name": "Saved Greatsword",
				"equip_slot": 7,
				"weapon_type": 1,
				"is_two_handed": true,
				"weapon_damage_min": 10,
				"weapon_damage_max": 20,
				"current_durability": 100,
				"max_durability": 100,
			},
			"8": {
				"id": "saved_shield",
				"display_name": "Saved Shield",
				"equip_slot": 8,
				"weapon_type": 10,
				"shield_type": 1,
				"current_durability": 100,
				"max_durability": 100,
			},
		},
		"inventory": [null],
	})
	_assert(illegal.get_equipped(ItemScript.EquipSlot.MAIN_HAND) != null,
		"the saved two-handed weapon survives the load")
	_assert(illegal.get_equipped(ItemScript.EquipSlot.OFF_HAND) == null,
		"an illegal saved normal shield leaves the off hand")
	_assert(illegal.find_item("saved_shield") >= 0,
		"the illegal saved shield is returned to the bag, not deleted")
	illegal.free()

	player.queue_free()
	hand_player.queue_free()
