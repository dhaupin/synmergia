## test_dual_wield.gd - the no-shield two-one-hander posture:
##   * a second one-hander auto-fills the off hand, never a shield slot;
##   * dual wield grants speed + a small all-lane power lift and half the
##     off-hand band, and both weapons' crit identities land;
##   * shields still close the posture;
##   * staff/wand bands feed spell power and relic bands feed healing power;
##   * every WeaponType has at least one record and the new families author
##     both legal hand counts.
##
## Run headless:
##   cd game && godot --headless --path . --script res://tests/test_dual_wield.gd
## Exit 0 = all pass.
extends SceneTree

const PlayerBaseScript = preload("res://entities/player/player_base.gd")
const InventoryComponentScript = preload("res://core/components/inventory_component.gd")
const ItemScript = preload("res://core/schemas/item.gd")
const CombatMath = preload("res://core/services/combat_math.gd")
const Skill = preload("res://core/combat/skill.gd")

var _pass := 0
var _fail := 0

func _initialize() -> void:
	await process_frame
	await _run()
	print("--- DUAL WIELD: %d passed, %d failed ---" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  [FAIL] ", msg)

func _approx(a: float, b: float, eps: float = 0.0001) -> bool:
	return absf(a - b) <= eps

func _item(id: String, type: int, two_handed: bool, damage: int, lane: int = 0) -> Resource:
	var item = ItemScript.new()
	item.id = id
	item.display_name = id
	item.item_category = ItemScript.ItemCategory.WEAPON
	item.equip_slot = ItemScript.EquipSlot.MAIN_HAND
	item.weapon_type = type
	item.weapon_damage_type = lane
	item.weapon_damage_min = damage
	item.weapon_damage_max = damage
	item.is_two_handed = two_handed
	item.attack_speed = 1.0
	item.crit_chance = 0.05
	item.crit_damage = 0.20
	item.max_durability = 100
	item.current_durability = 100
	return item

func _player(name: String) -> Node:
	var player = PlayerBaseScript.new()
	player.name = name
	root.add_child(player)
	await process_frame
	var bag = InventoryComponentScript.new()
	bag.name = "Inventory"
	player.add_child(bag)
	player.set("inventory_component", bag)
	return player

func _run() -> void:
	# --- Two one-handers: auto off-hand, speed, power, crit ----------------
	var player = await _player("DualWieldProbe")
	var bag = player.get("inventory_component")
	var sword = _item("probe_sword", ItemScript.WeaponType.SWORD, false, 10)
	var dagger = _item("probe_dagger", ItemScript.WeaponType.DAGGER, false, 10)
	dagger.crit_chance = 0.10
	dagger.crit_damage = 0.30

	bag.add_item(sword)
	_assert(bag.equip_item(0), "the first one-hander equips in the main hand")
	var single_speed: float = player.get_attack_speed()
	var single_crit: float = player.get_crit_chance()
	var single_crit_mult: float = player.get_crit_multiplier()
	var single_power: int = player.get_attack_power()

	bag.add_item(dagger)
	var dagger_slot: int = bag.find_item("probe_dagger")
	_assert(bag.equip_item(dagger_slot), "the second one-hander equips")
	_assert(bag.get_equipped(ItemScript.EquipSlot.MAIN_HAND).id == "probe_sword",
		"dual wield leaves the first weapon in the main hand")
	_assert(bag.get_equipped(ItemScript.EquipSlot.OFF_HAND).id == "probe_dagger",
		"the second one-hander auto-fills the off hand")
	_assert(bag.is_dual_wielding(), "two one-handers are dual wielding")
	_assert(not CombatMath._has_shield(player), "dual wield opens no shield lane")
	_assert(_approx(CombatMath._shield_block_scale(player), 0.0),
		"dual wield has a zero shield block scale")
	_assert(_approx(player.get_attack_speed(), single_speed * 1.15),
		"dual wield adds the 15%% hit-speed bonus (got %.3f, single %.3f)" % [
			player.get_attack_speed(), single_speed])
	_assert(_approx(player.get_crit_chance(), single_crit + 0.10),
		"the off-hand weapon's crit chance lands")
	_assert(_approx(player.get_crit_multiplier(), single_crit_mult + 0.30),
		"the off-hand weapon's crit damage lands")
	# STR 10 x 2 + main 10 + half of the off-hand 10 = 35, then the 6% dual
	# power lift (integer truncation lands on 37).
	_assert(player.get_attack_power() == 37,
		"dual wield adds half the off-hand band and the power lift (got %d, single %d)" % [
			player.get_attack_power(), single_power])

	# A shield replaces the off-hand weapon and closes the posture.
	var shield = ItemScript.new()
	shield.id = "probe_shield"
	shield.display_name = "Probe Shield"
	shield.equip_slot = ItemScript.EquipSlot.OFF_HAND
	shield.weapon_type = ItemScript.WeaponType.SHIELD
	shield.shield_type = ItemScript.ShieldType.NORMAL
	shield.block_rating = 40.0
	shield.max_durability = 100
	shield.current_durability = 100
	bag.add_item(shield)
	var shield_slot: int = bag.find_item("probe_shield")
	_assert(bag.equip_item(shield_slot), "a shield equips over the off-hand weapon")
	_assert(not bag.is_dual_wielding(), "a shield closes dual wield")
	_assert(bag.get_offhand_weapon() == null, "the shield is not an off-hand weapon")
	_assert(CombatMath._has_shield(player), "the shield restores the block lane")
	_assert(_approx(CombatMath._shield_block_scale(player), 1.0),
		"the normal shield restores the full block fraction")

	# Two-handed weapons still forbid a one-hander in the off hand.
	var hand_player = await _player("TwoHandedProbe")
	var hand_bag = hand_player.get("inventory_component")
	var greatsword = _item("probe_greatsword", ItemScript.WeaponType.SWORD, true, 18)
	hand_bag.add_item(greatsword)
	_assert(hand_bag.equip_item(0), "a two-handed sword equips")
	var off_dagger = _item("probe_off_dagger", ItemScript.WeaponType.DAGGER, false, 8)
	hand_bag.add_item(off_dagger)
	var off_slot: int = hand_bag.find_item("probe_off_dagger")
	_assert(not hand_bag.equip_item(off_slot, ItemScript.EquipSlot.OFF_HAND),
		"a one-hander is illegal in the off hand beside a two-hander")
	_assert(not hand_bag.is_dual_wielding(),
		"a two-hander plus a rejected off hand is not dual wielding")

	# --- Magical staff/wand lane ------------------------------------------
	var mage = await _player("MagicLaneProbe")
	var mage_bag = mage.get("inventory_component")
	var wand_a = _item("probe_wand_a", ItemScript.WeaponType.WAND, false, 10,
		ItemScript.WeaponDamageType.MAGICAL)
	var wand_b = _item("probe_wand_b", ItemScript.WeaponType.WAND, false, 10,
		ItemScript.WeaponDamageType.MAGICAL)
	wand_a.crit_chance = 0.05
	wand_b.crit_chance = 0.05
	mage_bag.add_item(wand_a)
	_assert(mage_bag.equip_item(0), "a one-handed wand equips")
	mage_bag.add_item(wand_b)
	var wand_slot: int = mage_bag.find_item("probe_wand_b")
	_assert(mage_bag.equip_item(wand_slot), "a second one-handed wand equips off hand")
	# INT 10 x 2 + main 10 + half off-hand 10 = 35, then 6% = 37.
	_assert(mage.get_spell_power() == 37,
		"wand bands feed spell power with the dual-wield lift (got %d)" % mage.get_spell_power())

	var magic_skill = Skill.new()
	magic_skill.damage_type = "magical"
	magic_skill.damage = 10
	var magic_crit: float = float(CombatMath._crit_chance_for(mage, magic_skill))
	var unarmed_mage = await _player("MagicCritBaseline")
	var unarmed_crit: float = float(CombatMath._crit_chance_for(unarmed_mage, magic_skill))
	_assert(magic_crit > unarmed_crit,
		"wand crit%% reaches the INT magical crit axis (%.3f vs %.3f)" % [
			magic_crit, unarmed_crit])

	# --- Healing relic lane ------------------------------------------------
	var healer = await _player("HealLaneProbe")
	var heal_bag = healer.get("inventory_component")
	var relic_a = _item("probe_relic_a", ItemScript.WeaponType.RELIC, false, 10,
		ItemScript.WeaponDamageType.HEALING)
	var relic_b = _item("probe_relic_b", ItemScript.WeaponType.RELIC, false, 10,
		ItemScript.WeaponDamageType.HEALING)
	relic_a.crit_chance = 0.04
	relic_b.crit_chance = 0.04
	heal_bag.add_item(relic_a)
	_assert(heal_bag.equip_item(0), "a one-handed relic equips")
	heal_bag.add_item(relic_b)
	var relic_slot: int = heal_bag.find_item("probe_relic_b")
	_assert(heal_bag.equip_item(relic_slot), "a second one-handed relic equips off hand")
	# WIS 10 x 2 + main 10 + half off-hand 10 = 35, then 6% = 37.
	_assert(healer.get_healing_power() == 37,
		"relic bands feed healing power with the dual-wield lift (got %d)" % healer.get_healing_power())

	var heal_skill = Skill.new()
	heal_skill.heal_amount = 10
	var heal_crit: float = float(CombatMath._crit_chance_for(healer, heal_skill))
	var unarmed_healer = await _player("HealCritBaseline")
	var unarmed_heal_crit: float = float(CombatMath._crit_chance_for(unarmed_healer, heal_skill))
	_assert(heal_crit > unarmed_heal_crit,
		"relic crit%% reaches the WIS healing crit axis (%.3f vs %.3f)" % [
			heal_crit, unarmed_heal_crit])

	# --- New family coverage ---------------------------------------------
	var lance_2h = load("res://data/weapons/wep_iron_lance.tres")
	var lance_1h = load("res://data/weapons/wep_short_lance.tres")
	var scythe = load("res://data/weapons/wep_iron_scythe.tres")
	var relic_1h = load("res://data/weapons/wep_oak_reliquary.tres")
	var relic_2h = load("res://data/weapons/wep_grand_reliquary.tres")
	_assert(lance_2h != null and lance_2h.is_two_handed
		and lance_2h.weapon_type == ItemScript.WeaponType.LANCE,
		"the two-handed lance family is authored")
	_assert(lance_1h != null and not lance_1h.is_two_handed
		and lance_1h.weapon_type == ItemScript.WeaponType.LANCE,
		"the one-handed lance family is authored")
	_assert(scythe != null and scythe.is_two_handed
		and scythe.weapon_type == ItemScript.WeaponType.SCYTHE,
		"the two-handed scythe family is authored")
	_assert(relic_1h != null and not relic_1h.is_two_handed
		and relic_1h.weapon_damage_type == ItemScript.WeaponDamageType.HEALING,
		"the one-handed healing relic family is authored")
	_assert(relic_2h != null and relic_2h.is_two_handed
		and relic_2h.weapon_damage_type == ItemScript.WeaponDamageType.HEALING,
		"the two-handed healing relic family is authored")
	_assert(relic_1h.weapon_damage_min > 0 and relic_1h.weapon_damage_max >= relic_1h.weapon_damage_min,
		"a relic authors a real healing min/max band")

	var types := {}
	var dir = DirAccess.open("res://data/weapons")
	if dir != null:
		for filename in dir.get_files():
			if not filename.ends_with(".tres"):
				continue
			var item = load("res://data/weapons/" + filename)
			if item != null and int(item.weapon_type) > 0:
				types[int(item.weapon_type)] = true
	for wt in range(1, ItemScript.WeaponType.RELIC + 1):
		_assert(types.has(wt), "WeaponType %d has at least one authored record" % wt)

	# A saved dual-wield pair must survive the legacy off-hand migration; the
	# old loader treated every off-hand weapon as a pre-canonical copy.
	var saved_dual = InventoryComponentScript.from_dict({
		"equipment": {
			"7": {
				"id": "saved_main", "display_name": "Saved Main", "item_category": 0,
				"equip_slot": 7, "weapon_type": 1, "weapon_damage_min": 5, "weapon_damage_max": 9,
				"current_durability": 100, "max_durability": 100,
			},
			"8": {
				"id": "saved_off", "display_name": "Saved Off", "item_category": 0,
				"equip_slot": 8, "weapon_type": 4, "weapon_damage_min": 5, "weapon_damage_max": 9,
				"current_durability": 100, "max_durability": 100,
			},
		},
		"inventory": [null],
	})
	_assert(saved_dual.get_equipped(ItemScript.EquipSlot.MAIN_HAND) != null
		and saved_dual.get_equipped(ItemScript.EquipSlot.OFF_HAND) != null,
		"a saved one-hander pair survives load")
	_assert(saved_dual.is_dual_wielding(), "a saved one-hander pair loads as dual wield")
	saved_dual.free()

	# A saved one-hander + two-hander off hand is illegal and returns the off
	# hand to the bag instead of leaving an impossible pair live.
	var saved_illegal = InventoryComponentScript.from_dict({
		"equipment": {
			"7": {
				"id": "saved_main_2", "display_name": "Saved Main", "item_category": 0,
				"equip_slot": 7, "weapon_type": 1, "weapon_damage_min": 5, "weapon_damage_max": 9,
				"current_durability": 100, "max_durability": 100,
			},
			"8": {
				"id": "saved_off_2h", "display_name": "Saved Off 2H", "item_category": 0,
				"equip_slot": 8, "weapon_type": 1, "is_two_handed": true,
				"weapon_damage_min": 9, "weapon_damage_max": 15,
				"current_durability": 100, "max_durability": 100,
			},
		},
		"inventory": [null],
	})
	_assert(saved_illegal.get_equipped(ItemScript.EquipSlot.OFF_HAND) == null
		and saved_illegal.find_item("saved_off_2h") >= 0,
		"a saved two-hander off hand returns to the bag")
	saved_illegal.free()

	player.queue_free()
	hand_player.queue_free()
	mage.queue_free()
	unarmed_mage.queue_free()
	healer.queue_free()
	unarmed_healer.queue_free()
