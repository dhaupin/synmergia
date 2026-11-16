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
	_check(is_equal_approx(record.mana_regen_pct_per_sec, 0.02), "mana regen is 2%")

	var ds = root.get_node_or_null("DataService")
	if ds != null:
		_check(ds.get_combat_balance() == record, "DataService resolves the authored record")
	var ts = root.get_node_or_null("TickService")
	if ts != null and ts.has_method("_combat_balance_record"):
		_check(ts._combat_balance_record() == record, "TickService reads the authored record")

	var malformed = record.duplicate()
	malformed.dodge_cap = 2.0
	_check(not malformed.is_valid(), "out-of-range dodge cap is rejected")
	var malformed_hit_cap = record.duplicate()
	malformed_hit_cap.hit_level_penalty_cap = 1.5
	_check(not malformed_hit_cap.is_valid(), "out-of-range hit penalty cap is rejected")

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

	CombatMathScript.set_balance_override(record)
	print("--- COMBAT BALANCE: %d passed, %d failed ---" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
