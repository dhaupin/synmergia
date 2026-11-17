## test_damage_ranges.gd - min/max damage is one contract across weapons,
## enemy bodies, magic skills, and the crit multiplier.
##
## Run headless:
##   godot --headless --path game --script res://tests/test_damage_ranges.gd
## Exit 0 = all pass.
extends SceneTree

const ItemScript = preload("res://core/schemas/item.gd")
const EnemyDataScript = preload("res://core/schemas/enemy_data.gd")
const InventoryScript = preload("res://core/components/inventory_component.gd")
const SkillScript = preload("res://core/combat/skill.gd")
const CombatMath = preload("res://core/services/combat_math.gd")

var _pass := 0
var _fail := 0

func _initialize() -> void:
	await process_frame
	await _run()
	print("--- DAMAGE RANGES: %d passed, %d failed ---" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  [FAIL] ", msg)

func _range_hits(rolls: Array, lo: int, hi: int) -> bool:
	for roll in rolls:
		if int(roll) < lo or int(roll) > hi:
			return false
	return true

func _rolls_for(callable: Callable, count: int = 60) -> Array:
	var out: Array = []
	for i in range(count):
		out.append(int(callable.call()))
	return out

func _run() -> void:
	# Load Enemy after the autoloads exist; a parse-time preload would compile
	# its bare GameLog references before `--script` registers that singleton.
	var EnemyScript = load("res://entities/enemy.gd")
	# --- Enemy-authored body band ---------------------------------------
	var data = EnemyDataScript.new()
	data.id = "range_probe"
	data.display_name = "Range Probe"
	data.level = 1
	data.attack_power = 20
	data.attack_damage_min = 10
	data.attack_damage_max = 30
	var enemy = EnemyScript.new()
	enemy.entity_id = "range_probe"
	enemy.display_name = "Range Probe"
	enemy.enemy_data = data
	root.add_child(enemy)
	await process_frame
	var enemy_rolls := _rolls_for(Callable(enemy, "get_attack_power"))
	_assert(_range_hits(enemy_rolls, 10, 30),
		"enemy body damage stays inside its authored min/max band")
	var distinct := {}
	for roll in enemy_rolls:
		distinct[roll] = true
	_assert(distinct.size() > 2, "enemy body damage is a real roll")

	# Inverted authored bounds are normalized just like weapons.
	data.attack_damage_min = 30
	data.attack_damage_max = 10
	data.apply_stats_to(enemy)
	var inverted_rolls := _rolls_for(Callable(enemy, "get_attack_power"))
	_assert(_range_hits(inverted_rolls, 10, 30),
		"an inverted enemy band still rolls lower..higher")

	# --- Weapon on an enemy ---------------------------------------------
	var bag = InventoryScript.new()
	bag.name = "InventoryComponent"
	enemy.add_child(bag)
	enemy.inventory_component = bag
	var axe = ItemScript.new()
	axe.id = "range_axe"
	axe.equip_slot = ItemScript.EquipSlot.MAIN_HAND
	axe.weapon_type = ItemScript.WeaponType.AXE
	axe.weapon_damage_min = 5
	axe.weapon_damage_max = 9
	bag.add_item(axe)
	_assert(bag.equip_item(0), "an enemy can equip a main-hand weapon")
	var weapon_rolls := _rolls_for(Callable(enemy, "get_attack_power"))
	_assert(_range_hits(weapon_rolls, 15, 39),
		"enemy body band plus weapon band reaches the live attack")

	# --- Skill-authored band (magic) ------------------------------------
	var skill = SkillScript.new()
	skill.damage_type = "magical"
	skill.damage_min = 40
	skill.damage_max = 60
	var skill_rolls := _rolls_for(Callable(skill, "get_damage_roll"))
	_assert(_range_hits(skill_rolls, 40, 60),
		"a magical skill rolls inside its authored min/max band")
	var fireball = load("res://data/skills/mage/human_sorcerer_fireball.tres")
	var runtime = SkillScript.from_schema(fireball)
	_assert(runtime.get_damage_range().x == 34 and runtime.get_damage_range().y == 46,
		"the Fireball data flattens to its 34..46 magic band")
	var fireball_rolls := _rolls_for(Callable(runtime, "get_damage_roll"))
	_assert(_range_hits(fireball_rolls, 34, 46), "Fireball rolls inside its data band")

	# --- Crit multiplies every band after the roll ----------------------
	var crit_hit := {
		"hit_result": CombatMath.HitResult.HIT,
		"is_crit": true,
		"damage_multiplier": 2.5,
	}
	var crit_ok := true
	for source in [enemy_rolls, skill_rolls, weapon_rolls]:
		for roll in source:
			var expected := int(float(roll) * 2.5)
			if CombatMath.calculate_damage(int(roll), crit_hit) != expected:
				crit_ok = false
	_assert(crit_ok, "crit multiplies enemy, skill, and weapon rolls after the band")

	# The live Skill path must roll the band first, then apply the one crit
	# multiplier. A forced-crit magical caster proves the whole route, not just
	# the CombatMath helper.
	var EntityScript = load("res://core/entities/entity.gd")
	var caster = EntityScript.new()
	caster.stats["intelligence"] = 0
	caster.stats["crit_chance"] = 2.0
	caster.stats["crit_damage"] = 0.0
	var target = EntityScript.new()
	var live_ok := true
	var live_hits := 0
	for i in range(40):
		var dealt: int = skill.calculate_damage(caster, target)
		if dealt > 0:
			live_hits += 1
			if dealt < 60 or dealt > 90:
				live_ok = false
			if not skill._last_was_crit:
				live_ok = false
	_assert(live_hits > 0 and live_ok,
		"Skill.calculate_damage rolls magic 40..60 then applies the 1.5 crit")

	# --- Two-handed + wrist-shield loadouts on real enemy records --------
	var ds = root.get_node_or_null("DataService")
	var bandit_data = ds.get_enemy("bandit") if ds != null and ds.has_method("get_enemy") else null
	if bandit_data != null:
		var bandit = EnemyScript.new()
		bandit.entity_id = "range_bandit"
		bandit.enemy_data = bandit_data
		root.add_child(bandit)
		await process_frame
		_assert(bandit.inventory_component != null, "a template loadout creates an enemy inventory")
		var main = bandit.inventory_component.get_equipped(ItemScript.EquipSlot.MAIN_HAND)
		var off = bandit.inventory_component.get_equipped(ItemScript.EquipSlot.OFF_HAND)
		_assert(main != null and main.id == "wep_iron_axe", "bandit loadout equips its authored axe")
		_assert(bandit.inventory_component.get_equipment_armor() > 0,
			"bandit loadout equips armor, not just a weapon")
		_assert(off != null and off.is_wrist_shield(), "bandit carries the wrist shield")
		_assert(CombatMath._has_shield(bandit) and is_equal_approx(
			CombatMath._shield_block_scale(bandit), 0.4),
			"a wrist shield opens only the lesser block lane")

	var saint_data = ds.get_enemy("clockwork_saint") if ds != null and ds.has_method("get_enemy") else null
	if saint_data != null:
		var saint = EnemyScript.new()
		saint.entity_id = "range_saint"
		saint.enemy_data = saint_data
		root.add_child(saint)
		await process_frame
		var saint_main = saint.inventory_component.get_equipped(ItemScript.EquipSlot.MAIN_HAND)
		var saint_off = saint.inventory_component.get_equipped(ItemScript.EquipSlot.OFF_HAND)
		_assert(saint_main != null and saint_main.is_two_handed,
			"the Clockwork Saint carries a two-handed maul")
		_assert(saint_off != null and saint_off.is_wrist_shield(),
			"the two-handed Saint keeps the wrist shield legal")
		_assert(_range_hits(_rolls_for(Callable(saint, "get_attack_power")), 122, 172),
			"the Saint's body band plus two-handed weapon stays in contract")

	enemy.queue_free()
