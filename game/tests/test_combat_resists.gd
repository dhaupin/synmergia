## test_combat_resists.gd - the canonical school-resist lane, plus the
## weapon/shield/class data that feeds it.
##
## Run headless:
##   godot --headless --path game --script res://tests/test_combat_resists.gd
## Exit 0 = all pass.
extends SceneTree

const StatId = preload("res://core/schemas/stat_id.gd")
const CombatMath = preload("res://core/services/combat_math.gd")
const EntityScript = preload("res://core/entities/entity.gd")
const EnemyDataScript = preload("res://core/schemas/enemy_data.gd")
const ItemScript = preload("res://core/schemas/item.gd")
const StatusEffectScript = preload("res://core/entities/status_effect.gd")
const PlayerBaseScript = preload("res://entities/player/player_base.gd")

var _pass := 0
var _fail := 0

func _initialize() -> void:
	await process_frame
	await _run()
	print("--- COMBAT RESISTS: %d passed, %d failed ---" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  [FAIL] ", msg)

func _approx(a: float, b: float, eps: float = 0.0001) -> bool:
	return absf(a - b) <= eps

func _entity() -> Node:
	var e: Node = EntityScript.new()
	root.add_child(e)
	e.max_health = 100000
	e.current_health = 100000
	return e

func _run() -> void:
	# --- 1. One school vocabulary, one resist key per school --------------
	_assert(StatId.resist_key_for("fire") == "resist_fire",
		"fire maps to resist_fire")
	_assert(StatId.resist_key_for("magic") == "resist_magical",
		"the legacy 'magic' spelling aliases to magical")
	_assert(StatId.resist_key_for("storm") == "",
		"an unknown future school has no guessed ward")
	_assert(StatId.is_valid("resist_frost") and StatId.FLAT_KEYS.has("resist_frost"),
		"every school key is a real flat StatId")
	_assert(_approx(StatId.school_resist_of({"resist_fire": 0.5}, "fire"), 0.5),
		"school_resist_of reads the canonical key")
	_assert(_approx(StatId.school_resist_of({"resist_fire": 2.0}, "fire"), StatId.MAX_RESIST),
		"a ward is clamped to MAX_RESIST")
	_assert(_approx(StatId.school_resist_of({"resist_fire": 0.5}, "storm"), 0.0),
		"an unknown school is not warded by a fire key")

	# --- 2. The damage pipeline applies the ward --------------------------
	var plain := _entity()
	var warded := _entity()
	warded.stats["resist_fire"] = 0.5
	var plain_hit: int = plain.take_damage(200, null, "fire")
	var warded_hit: int = warded.take_damage(200, null, "fire")
	_assert(warded_hit < plain_hit,
		"a fire ward reduces a fire hit (%d -> %d)" % [plain_hit, warded_hit])
	_assert(_approx(CombatMath.school_resist_for(warded, "fire"), 0.5),
		"CombatMath reads the body's fire ward")

	# --- 3. EnemyData seeds the same keys onto spawned bodies -------------
	var template = EnemyDataScript.new()
	template.id = "test_elemental"
	template.damage_resists = {"fire": 0.25, "magic": 0.1}
	var spawned := _entity()
	template.apply_stats_to(spawned)
	_assert(_approx(float(spawned.stats.get("resist_fire", 0.0)), 0.25),
		"EnemyData.apply_stats_to seeds the fire ward")
	_assert(_approx(float(spawned.stats.get("resist_magical", 0.0)), 0.1),
		"EnemyData.apply_stats_to aliases magic to magical")

	# --- 4. A status effect can grant and remove a ward -------------------
	var body := _entity()
	var ward = StatusEffectScript.new()
	ward.effect_name = "Test Fire Ward"
	ward.duration = 10.0
	ward.tick_behavior = StatusEffectScript.TickBehavior.DURATION
	ward.damage_resists = {"fire": 0.2}
	body.apply_status_effect(ward)
	_assert(_approx(float(body.stats.get("resist_fire", 0.0)), 0.2),
		"a status effect folds its fire ward into the stat block")
	body.remove_status_effect(ward)
	_assert(_approx(float(body.stats.get("resist_fire", 0.0)), 0.0),
		"removing the status effect removes the ward")

	# --- 5. Class movement and class wards are data -----------------------
	var marksman = load("res://data/classes/class_human_marksman.tres")
	var guardian = load("res://data/classes/class_human_guardian.tres")
	if marksman != null and guardian != null:
		_assert(float(marksman.movement_speed_bonus) > float(guardian.movement_speed_bonus),
			"the rogue class authors more movement than the tank")
		var body2 = PlayerBaseScript.new()
		body2._apply_class_crit_identity(marksman)
		_assert(_approx(float(body2.stats.get("movement_speed_multiplier", 1.0)), 1.06),
			"the class movement lane reaches the player stat block")
		_assert(_approx(float(body2.stats.get("resist_physical", 0.0)), 0.02),
			"the class ward reaches the player stat block")
		body2.free()

	# --- 6. Existing gear now carries the identity ------------------------
	var sword = load("res://data/weapons/wep_iron_sword.tres")
	if sword != null:
		_assert(int(sword.equip_slot) == ItemScript.EquipSlot.MAIN_HAND,
			"a hand weapon equips in MAIN_HAND, not OFF_HAND")
		_assert(float(sword.attack_speed) > 1.0,
			"the iron sword authors a cadence override")
		_assert(float(sword.crit_chance) > 0.0 and float(sword.crit_damage) > 0.0,
			"the iron sword authors crit chance and crit damage")
	var tower = load("res://data/weapons/wep_bulwark_towershield.tres")
	if tower != null:
		_assert(int(tower.equip_slot) == ItemScript.EquipSlot.OFF_HAND \
			and int(tower.weapon_type) == ItemScript.WeaponType.SHIELD,
			"a tower shield is an off-hand shield")
		_assert(int(tower.armor_value) > 0 and float(tower.block_rating) > 0.0,
			"a tower shield carries armor and block rating")
		_assert(float(tower.damage_resists.get("physical", 0.0)) > 0.0,
			"a tower shield carries a physical ward")
	var haven = load("res://data/armors/arm_shield_haven_wall.tres")
	if haven != null:
		_assert(int(haven.equip_slot) == ItemScript.EquipSlot.OFF_HAND,
			"the Haven Wall equips in the off hand (not shoulders)")
		_assert(int(haven.armor_value) == 14 and float(haven.block_rating) > 0.0,
			"the Haven Wall keeps its authored armor and gains a block rating")
	var plate = load("res://data/armors/arm_guardian_chest.tres")
	if plate != null:
		_assert(not plate.damage_resists.is_empty(),
			"a class armor piece authors per-school resists")

	# --- 7. Thematic enemies use the same enemy lane ---------------------
	var void_lord = load("res://data/enemies/enemy_void_lord.tres")
	if void_lord != null:
		_assert(float(void_lord.damage_resists.get("shadow", 0.0)) > 0.0,
			"the Void Lord authors a shadow ward")
	var tide = load("res://data/enemies/enemy_tidebound_ancient.tres")
	if tide != null:
		_assert(float(tide.damage_resists.get("frost", 0.0)) > 0.0,
			"the Tidebound Ancient authors a frost ward")
