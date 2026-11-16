## Combat balance receipt: the authored record is valid, its current
## values match the live defaults, and CombatMath reads the record instead
## of carrying a second set of bases/caps.
## Run: godot --headless --path . --script res://tests/test_combat_balance.gd
extends SceneTree

const CombatBalanceData = preload("res://core/schemas/combat_balance_data.gd")
const CombatMathScript = preload("res://core/services/combat_math.gd")

var _pass: int = 0
var _fail: int = 0


func _init() -> void:
	call_deferred("_run")


func _check(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("PASS  ", label)
	else:
		_fail += 1
		printerr("FAIL  ", label)


func _run() -> void:
	await process_frame

	var record = load("res://data/balance/combat_balance.tres")
	_check(record is CombatBalanceData, "combat balance record loads")
	if not (record is CombatBalanceData):
		quit(1)
		return
	_check(record.id == "combat_balance", "record id is combat_balance")
	_check(record.is_valid(), "record passes the structural gate")
	_check(is_equal_approx(record.hit_base, 0.95), "hit base is 0.95")
	_check(is_equal_approx(record.hit_level_penalty_cap, 0.30), "hit level penalty cap is 0.30")
	_check(is_equal_approx(record.dodge_base, 0.03), "dodge base is 0.03")
	_check(is_equal_approx(record.parry_base, 0.02), "parry base is 0.02")
	_check(is_equal_approx(record.block_base, 0.05), "block base is 0.05")
	_check(is_equal_approx(record.health_regen_pct_per_sec, 0.01), "health regen is 1%")
	_check(is_equal_approx(record.health_regen_combat_pct_per_sec, 0.01), "combat health regen is 1% for now")
	_check(is_equal_approx(record.mana_regen_pct_per_sec, 0.02), "mana regen is 2%")
	_check(is_equal_approx(record.mana_regen_combat_pct_per_sec, 0.02), "combat mana regen is 2% for now")
	_check(is_equal_approx(record.stamina_regen_pct_per_sec, 0.02), "stamina regen is 2%")
	_check(is_equal_approx(record.stamina_regen_combat_pct_per_sec, 0.01), "combat stamina regen is 1%")
	_check(is_equal_approx(record.armor_curve_base, 100.0), "armor curve base is 100")
	_check(is_equal_approx(record.armor_curve_per_attacker_level, 2.0), "armor curve scales with attacker level")
	_check(is_equal_approx(record.armor_defender_level_bonus, 0.02), "defender level gap adds armor")
	_check(is_equal_approx(record.armor_mitigation_cap, 0.90), "armor mitigation cap is 90%")

	var ds = root.get_node_or_null("DataService")
	if ds != null:
		_check(ds.get_combat_balance() == record, "DataService resolves the authored record")
	var ts = root.get_node_or_null("TickService")
	if ts != null and ts.has_method("_combat_balance_record"):
		_check(ts._combat_balance_record() == record, "TickService reads the authored record")
		var prior_balance = ts._combat_balance
		var tuned_regen = record.duplicate()
		tuned_regen.health_regen_pct_per_sec = 0.03
		tuned_regen.health_regen_combat_pct_per_sec = 0.07
		tuned_regen.mana_regen_pct_per_sec = 0.04
		tuned_regen.mana_regen_combat_pct_per_sec = 0.08
		tuned_regen.stamina_regen_pct_per_sec = 0.06
		tuned_regen.stamina_regen_combat_pct_per_sec = 0.09
		ts._combat_balance = tuned_regen
		var rest_rates: Dictionary = ts._regen_rates(false)
		var combat_rates: Dictionary = ts._regen_rates(true)
		_check(is_equal_approx(float(rest_rates.get("health_pct", 0.0)), 0.03) \
				and is_equal_approx(float(rest_rates.get("mana_pct", 0.0)), 0.04) \
				and is_equal_approx(float(rest_rates.get("stamina_pct", 0.0)), 0.06),
				"rest regen reads all three rest rates")
		_check(is_equal_approx(float(combat_rates.get("health_pct", 0.0)), 0.07) \
				and is_equal_approx(float(combat_rates.get("mana_pct", 0.0)), 0.08) \
				and is_equal_approx(float(combat_rates.get("stamina_pct", 0.0)), 0.09),
				"combat regen reads all three combat rates")
		ts._combat_balance = prior_balance

	var malformed = record.duplicate()
	malformed.dodge_cap = 2.0
	_check(not malformed.is_valid(), "out-of-range dodge cap is rejected")
	var malformed_hit_cap = record.duplicate()
	malformed_hit_cap.hit_level_penalty_cap = 1.5
	_check(not malformed_hit_cap.is_valid(), "out-of-range hit penalty cap is rejected")
	var malformed_armor_cap = record.duplicate()
	malformed_armor_cap.armor_mitigation_cap = 1.5
	_check(not malformed_armor_cap.is_valid(), "out-of-range armor mitigation cap is rejected")

	CombatMathScript.set_balance_override(record)
	var tuned = record.duplicate()
	tuned.hit_base = 0.80
	tuned.hit_floor = 0.10
	tuned.dodge_base = 0.12
	tuned.dodge_per_agility = 0.0
	tuned.dodge_level_bonus = 0.0
	tuned.dodge_cap = 0.50
	tuned.parry_base = 0.10
	tuned.parry_per_strength = 0.0
	tuned.parry_level_bonus = 0.0
	tuned.parry_cap = 0.50
	tuned.block_base = 0.20
	tuned.block_per_vitality = 0.0
	tuned.block_cap = 0.60
	CombatMathScript.set_balance_override(tuned)

	_check(is_equal_approx(CombatMathScript.calculate_hit_chance(10, 10), 0.80),
		"hit base reads the record")
	var cap_tuned = record.duplicate()
	cap_tuned.hit_base = 0.95
	cap_tuned.hit_level_penalty_per_level = 0.01
	cap_tuned.hit_level_penalty_cap = 0.10
	CombatMathScript.set_balance_override(cap_tuned)
	_check(is_equal_approx(CombatMathScript.calculate_hit_chance(1, 100), 0.85),
		"hit level penalty cap reads the record")
	CombatMathScript.set_balance_override(tuned)
	_check(is_equal_approx(CombatMathScript.calculate_dodge_chance(1, 0.0, 10.0), 0.12),
		"dodge base reads the record")
	_check(is_equal_approx(CombatMathScript.calculate_parry_chance(1, 0.0, true, 10.0), 0.10),
		"parry base reads the record with a shield")
	_check(is_equal_approx(CombatMathScript.calculate_parry_chance(1, 0.0, false, 10.0), 0.05),
		"parry no-shield multiplier reads the record")
	_check(is_equal_approx(CombatMathScript.calculate_block_chance(1, 0.0, true, 10.0), 0.20),
		"block base reads the record with a shield")
	_check(CombatMathScript.calculate_block_chance(1, 0.0, false, 10.0) == 0.0,
		"block remains shield-gated")

	# --- Armor curve: level gap and flat stat behavior -------------------
	var low_vs_high: int = CombatMathScript.calculate_mitigation(100, 100.0, 5, 50)
	var high_vs_low: int = CombatMathScript.calculate_mitigation(100, 44.0, 50, 5)
	_check(low_vs_high < 40, "a level-5 attacker chips a level-50 armor target")
	_check(high_vs_low > 75, "a level-50 attacker mostly ignores level-5 armor")
	_check(low_vs_high < high_vs_low, "the level gap is asymmetric in the defender's favor")
	var capped: int = CombatMathScript.calculate_mitigation(100, 10000.0, 5, 60)
	_check(capped >= 9 and capped <= 10, "the armor cap leaves roughly 10% chip damage")
	var base_hit: int = CombatMathScript.calculate_mitigation(100, 100.0, 10, 10)
	var armored_hit: int = CombatMathScript.calculate_mitigation(100, 100.0, 10, 10, 1.0, 2.0)
	_check(armored_hit < base_hit, "armor_multiplier raises the flat armor before the curve")
	var flat_hit: int = CombatMathScript.calculate_mitigation(100, 0.0, 10, 10, 1.0, 1.0, 0.50)
	_check(flat_hit == 50, "flat damage_reduction stacks after the armor curve")

	CombatMathScript.set_balance_override(record)
	print("--- COMBAT BALANCE: %d passed, %d failed ---" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
