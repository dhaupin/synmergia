## test_power_scaling.gd - general power scaling is a separate law from
## instance power normalization.
##
##   1. The level gap scales damage everywhere (lower level deals less,
##      higher level deals more) even at identical stats and gear.
##   2. Arena/duel/TDM/elimination/Royale normalized fighters bypass the
##      world law and read one shared level for hit/armor penalties.
##   3. A bare fixture or a null combatant never invents a level gap.
##
## Run headless:
##   godot --headless --path game --script res://tests/test_power_scaling.gd
## Exit 0 = all pass.
extends SceneTree

const CombatMathScript = preload("res://core/services/combat_math.gd")
const EntityScript = preload("res://core/entities/entity.gd")
const HealthComponentScript = preload("res://core/components/health_component.gd")
const BalanceScript = preload("res://core/schemas/combat_balance_data.gd")

var _pass := 0
var _fail := 0

func _initialize() -> void:
	await process_frame
	# Pin the tuning record so this receipt never depends on a designer's
	# live .tres edit; the shipped file carries the same defaults.
	var record = BalanceScript.new()
	CombatMathScript.set_balance_override(record)
	await _run(record)
	CombatMathScript.set_balance_override(null)
	print("--- POWER SCALING: %d passed, %d failed ---" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  [FAIL] ", msg)

func _approx(a: float, b: float, eps: float = 0.001) -> bool:
	return absf(a - b) <= eps

func _body(level: int) -> Node:
	var body = EntityScript.new()
	body.level = level
	root.add_child(body)
	return body

func _run(record) -> void:
	# --- 1. The level law itself -----------------------------------------
	_assert(_approx(CombatMathScript.level_power_multiplier(10, 10), 1.0),
		"equal levels are 1.0")
	_assert(_approx(CombatMathScript.level_power_multiplier(5, 50), 0.2),
		"a level-5 attacker against 50 hits the 0.2 floor")
	_assert(_approx(CombatMathScript.level_power_multiplier(50, 5), 2.35),
		"a level-50 attacker against 5 deals 2.35x")
	_assert(CombatMathScript.level_power_multiplier(1, 60) > 0.0,
		"the floor keeps a huge gap from becoming zero")
	_assert(_approx(CombatMathScript.level_power_multiplier_for(null, null), 1.0),
		"a bare fixture never invents a level gap")

	# --- 2. Damage at equal stats/gear (terminal receiver) --------------
	var low = _body(5)
	var high = _body(50)
	for body in [low, high]:
		body.stats["vitality"] = 0
		body.max_health = 1000
		body.current_health = 1000
	_assert(CombatMathScript.apply_level_power(100, low, high) == 20,
		"level 5 -> 50 scales an incoming 100 to 20")
	_assert(CombatMathScript.apply_level_power(100, high, low) >= 234,
		"level 50 -> 5 scales an incoming 100 to 2.35x")
	var low_to_high: int = high.take_damage(100, low)
	var high_to_low: int = low.take_damage(100, high)
	var equal_hit: int = low.take_damage(100, low)
	_assert(low_to_high == 20, "level 5 -> 50 deals 20 (got %d)" % low_to_high)
	_assert(high_to_low >= 234 and high_to_low <= 235,
		"level 50 -> 5 deals 2.35x, floored to 234/235 (got %d)" % high_to_low)
	_assert(equal_hit == 100, "equal levels deal the base 100 (got %d)" % equal_hit)
	_assert(low_to_high < equal_hit and high_to_low > equal_hit,
		"the world law bites in both directions")

	# The component is the terminal for projectile/DoT/direct lanes; it must
	# apply the same law as Entity's own receiver.
	var component = HealthComponentScript.new()
	low.add_child(component)
	component.max_health = 1000
	component.current_health = 1000
	var component_hit: int = component.take_damage(100, high)
	_assert(component_hit >= 234 and component_hit <= 235,
		"HealthComponent applies the world law to a direct/projectile hit (got %d)" % component_hit)

	# --- 3. Instance normalization bypasses the world law ----------------
	low.current_health = 1000
	low.set_meta("arena_power_normalized", true)
	high.set_meta("arena_power_normalized", true)
	var normalized_hit: int = low.take_damage(100, high)
	_assert(normalized_hit == 100,
		"an arena-normalized bout does not pay the open-world level law (got %d)" % normalized_hit)
	_assert(_approx(CombatMathScript.level_power_multiplier_for(low, high), 1.0),
		"the object-facing helper honors the normalization mark")
	low.remove_meta("arena_power_normalized")
	high.remove_meta("arena_power_normalized")

	# The armor curve reads the same shared level once normalized.
	var raw_armor: int = CombatMathScript.calculate_mitigation(100, 100.0, 5, 50)
	var norm_armor: int = CombatMathScript.calculate_mitigation(100, 100.0, 5, 50, 1.0, 1.0, 0.0, true)
	_assert(norm_armor > raw_armor,
		"normalized armor mitigation uses one reference level (%d > %d)" % [norm_armor, raw_armor])

	# Hit chance follows the same rule (the level penalty is world-side).
	var raw_table := CombatMathScript.calculate_hit(low, high)
	low.set_meta("arena_power_normalized", true)
	high.set_meta("arena_power_normalized", true)
	var norm_table := CombatMathScript.calculate_hit(low, high)
	_assert(float(norm_table.get("hit_chance", 0.0)) > float(raw_table.get("hit_chance", 0.0)),
		"normalized hit chance ignores the raw level penalty (%.2f > %.2f)" % [
			float(norm_table.get("hit_chance", 0.0)), float(raw_table.get("hit_chance", 0.0))])
	low.remove_meta("arena_power_normalized")
	high.remove_meta("arena_power_normalized")

	# The record's caps are structural, not decorative.
	var invalid = BalanceScript.new()
	invalid.level_power_min_multiplier = 0.0
	_assert(not invalid.is_valid(), "a zero power floor is rejected by the balance record")
	_assert(record.is_valid(), "the shipped defaults are a valid record")

	low.queue_free()
	high.queue_free()
