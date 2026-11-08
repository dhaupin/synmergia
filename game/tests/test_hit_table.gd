## Hit-table tests: CombatMath.calculate_hit single-roll combat table,
## stat-derived defense chances, duck-typed access, hit_label, and the
## pipeline wiring (Skill.calculate_damage -> whiff skip, EventHub.
## hit_resolved). Run:
## godot --headless --path . --script res://tests/test_hit_table.gd
extends SceneTree

const CombatMathScript = preload("res://core/services/combat_math.gd")

## entity.gd and skill.gd reference the EventHub autoload at compile time.
## A parse-time preload in --script mode (which runs BEFORE autoloads
## exist) poisons the cached script: compile fails, and .new() vanishes
## with "Nonexistent function 'new' in base 'GDScript'" mid-test while
## _fails stays 0. load() at runtime -- after autoloads are up -- is the
## repo's de-flake pattern (see test_aggro_system.gd, test_kill_rewards.gd).
var EntityScript: GDScript = null
var SkillScript: GDScript = null

var _fails: int = 0

func _init() -> void:
	call_deferred("_run")

func _check(cond: bool, label: String) -> void:
	if cond:
		print("PASS  ", label)
	else:
		printerr("FAIL  ", label)
		_fails += 1

func _run() -> void:
	await process_frame
	root.get_node_or_null("GameLog")

	# Resolve combatant/skill scripts AFTER autoloads exist, and fail loud
	# instead of erroring silently inside the pipeline groups.
	EntityScript = load("res://core/entities/entity.gd")
	SkillScript = load("res://core/combat/skill.gd")
	if EntityScript == null or not EntityScript.can_instantiate():
		printerr("FAIL  entity.gd failed to compile after boot (EventHub ordering regression)")
		_fails += 1
		quit(1)
		return
	if SkillScript == null or not SkillScript.can_instantiate():
		printerr("FAIL  skill.gd failed to compile after boot (EventHub ordering regression)")
		_fails += 1
		quit(1)
		return

	# Await each group: several suspend on process_frame (entity _ready),
	# and an un-awaited call would let quit() race them -- the summary
	# would print while async groups are still pending.
	await _test_level_penalty_direction()
	await _test_zero_chance_helpers()
	await _test_table_shape_and_ducktyping()
	await _test_defender_stats_shift_the_table()
	await _test_is_whiff_and_calculate_damage()
	await _test_hit_label()
	await _test_pipeline_skill_whiff_no_chip()
	await _test_pipeline_hit_resolved_signal()

	print("SUMMARY: 8 groups, %d failed" % _fails)
	quit(0 if _fails == 0 else 1)


func _mk_attacker(lvl: int = 1) -> Node:
	var a = EntityScript.new()
	a.display_name = "HitTester"
	a.level = lvl
	return a


func _mk_defender(lvl: int = 1) -> Node:
	var d = EntityScript.new()
	d.display_name = "HitTarget"
	d.level = lvl
	return d


## The old formula clamped the wrong way: attackers were penalized for
## fighting DOWN. Defender 10 levels higher must reduce hit chance;
## defender 10 levels lower must not.
func _test_level_penalty_direction() -> void:
	var even := CombatMathScript.calculate_hit_chance(10, 10)
	var up := CombatMathScript.calculate_hit_chance(10, 20)
	var down := CombatMathScript.calculate_hit_chance(10, 1)
	_check(even > 0.9, "even-level hit chance near base (got %.2f)" % even)
	_check(up < even, "attacking a higher level reduces hit chance (%.2f < %.2f)" % [up, even])
	_check(down >= even, "attacking a lower level does not reduce hit chance (%.2f >= %.2f)" % [down, even])
	_check(up >= 0.05, "hit chance floors at 5%% even vs much higher level (got %.2f)" % up)


## A fresh level-1 entity has ~3% dodge and ~1% parry (no shield), and
## block is 0 without a shield.
func _test_zero_chance_helpers() -> void:
	var dodge := CombatMathScript.calculate_dodge_chance(1, 0.0, 10.0)
	var parry := CombatMathScript.calculate_parry_chance(1, 0.0, false, 10.0)
	var block := CombatMathScript.calculate_block_chance(1, 0.0, false, 10.0)
	_check(absf(dodge - 0.03) < 0.001, "base dodge ~3%% at agi 10 (got %.3f)" % dodge)
	_check(parry <= 0.02, "parry without shield is halved (got %.3f)" % parry)
	_check(block == 0.0, "block is shield-gated (0.0 without a shield)")


## Basic shape and the duck-typed families: bare Entity (this test) AND
## player-body-shaped stubs (stats dict, no combat_component). The
## old implementation dereferenced combat_component and would have thrown
## on the first real call.
func _test_table_shape_and_ducktyping() -> void:
	var a := _mk_attacker(5)
	var d := _mk_defender(5)
	root.add_child(a)
	root.add_child(d)
	await process_frame

	# Deterministic-ish: one call must return the full documented shape.
	var r := CombatMathScript.calculate_hit(a, d)
	_check(r.has("hit_result") and r.has("is_crit") and r.has("damage_multiplier")
		and r.has("blocked_damage") and r.has("hit_chance"),
		"hit table returns the documented result shape")
	_check(r["hit_result"] is int, "hit_result is a HitResult enum int")
	_check(r["hit_chance"] > 0.0 and r["hit_chance"] <= 1.0,
		"hit_chance in (0,1] (got %.2f)" % r["hit_chance"])

	# Null defenders must not throw (defensive callers pass through).
	var null_result := CombatMathScript.calculate_hit(a, null)
	_check(null_result["hit_result"] == CombatMathScript.HitResult.HIT,
		"null defender returns default HIT without throwing")

	# player-body-shaped stub: stats dict + level, no combat_component.
	var stub := Node3D.new()
	stub.set("level", 3)
	stub.set("stats", {"strength": 10, "agility": 10, "intelligence": 10, "vitality": 10, "wisdom": 10})
	root.add_child(stub)
	await process_frame
	var stub_ok := true
	for i in range(20):
		var rr := CombatMathScript.calculate_hit(a, stub)
		if not (rr["hit_result"] is int):
			stub_ok = false
			break
	_check(stub_ok, "hit table works on player-body-shaped stubs (20 rolls)")

	# Statistical sanity: over 400 even-level rolls, plain hits dominate
	# (~95% band) and miss-family outcomes stay rare.
	var hits := 0
	var whiffs := 0
	for i in range(400):
		var rr := CombatMathScript.calculate_hit(a, d)
		if rr["hit_result"] == CombatMathScript.HitResult.HIT:
			hits += 1
		elif CombatMathScript.is_whiff(int(rr["hit_result"])):
			whiffs += 1
	_check(hits > 300, "even-level rolls mostly hit (%d/400)" % hits)
	_check(whiffs < 80, "miss-family outcomes stay rare (%d/400)" % whiffs)

	a.free()
	d.free()
	stub.free()


## Dodging happens more for agile defenders, and a shielded defender can
## block. The chance curves are verified deterministically against the
## pure helpers (no randomness); a wide-gap distribution comparison then
## smoke-checks the assembled table.
func _test_defender_stats_shift_the_table() -> void:
	# Deterministic curves: dodge grows with agility, parry with strength.
	var dodge_low := CombatMathScript.calculate_dodge_chance(5, 0.0, 10.0)
	var dodge_high := CombatMathScript.calculate_dodge_chance(5, 0.0, 40.0)
	_check(dodge_high > dodge_low,
		"dodge chance curve rises with agility (%.3f -> %.3f)" % [dodge_low, dodge_high])
	var parry_low := CombatMathScript.calculate_parry_chance(5, 0.0, false, 10.0)
	var parry_high := CombatMathScript.calculate_parry_chance(5, 0.0, false, 40.0)
	_check(parry_high > parry_low,
		"parry chance curve rises with strength (%.3f -> %.3f)" % [parry_low, parry_high])

	var a := _mk_attacker(5)
	root.add_child(a)
	await process_frame

	var d_low = _mk_defender(5)
	d_low.stats["agility"] = 10
	root.add_child(d_low)
	await process_frame

	var d_high = _mk_defender(5)
	# agi 250: dodge curve hits its 35% cap (3% + (250-10)*0.0015 = 0.39).
	d_high.stats["agility"] = 250
	root.add_child(d_high)
	await process_frame

	var whiffs_low := 0
	var whiffs_high := 0
	for i in range(600):
		if CombatMathScript.is_whiff(int(CombatMathScript.calculate_hit(a, d_low)["hit_result"])):
			whiffs_low += 1
		if CombatMathScript.is_whiff(int(CombatMathScript.calculate_hit(a, d_high)["hit_result"])):
			whiffs_high += 1
	# Expected: d_low ~9.5% (5 miss + 3.25 dodge + 1.25 parry) -> ~57/600;
	# d_high ~41% (5 + capped 35 dodge + 1.25 parry) -> ~247/600. Ratio
	# threshold 2x clears the worst realistic 3-sigma tails (~208 vs ~79).
	_check(whiffs_high > whiffs_low * 2,
		"agile defenders whiff far more attacks (%d vs %d of 600)" % [whiffs_high, whiffs_low])

	a.free()
	d_low.free()
	d_high.free()


func _test_is_whiff_and_calculate_damage() -> void:
	_check(CombatMathScript.is_whiff(CombatMathScript.HitResult.MISS), "MISS is a whiff")
	_check(CombatMathScript.is_whiff(CombatMathScript.HitResult.EVADE), "EVADE is a whiff")
	_check(CombatMathScript.is_whiff(CombatMathScript.HitResult.PARRY), "PARRY is a whiff")
	_check(not CombatMathScript.is_whiff(CombatMathScript.HitResult.BLOCK), "BLOCK is not a whiff")
	_check(not CombatMathScript.is_whiff(CombatMathScript.HitResult.HIT), "HIT is not a whiff")

	# calculate_damage: whiffs deal 0; blocks chip; crits multiply.
	var block_result := {
		"hit_result": CombatMathScript.HitResult.BLOCK,
		"damage_multiplier": 1.0,
		"blocked_damage": 30,
	}
	var chip := CombatMathScript.calculate_damage(10, block_result)
	_check(chip == 1, "10 dmg blocked by 30-value shield chips exactly 1 (got %d)" % chip)

	var crit_result := {"hit_result": CombatMathScript.HitResult.HIT, "damage_multiplier": 1.5, "blocked_damage": 0}
	_check(CombatMathScript.calculate_damage(10, crit_result) == 15, "crit multiplier applied (10 -> 15)")

	var miss_result := {"hit_result": CombatMathScript.HitResult.MISS, "damage_multiplier": 1.0}
	_check(CombatMathScript.calculate_damage(999, miss_result) == 0, "miss deals 0 damage")


func _test_hit_label() -> void:
	_check(CombatMathScript.hit_label({"hit_result": CombatMathScript.HitResult.MISS}) == "Miss",
		"hit_label MISS -> 'Miss'")
	_check(CombatMathScript.hit_label({"hit_result": CombatMathScript.HitResult.EVADE}) == "Dodge",
		"hit_label EVADE -> 'Dodge'")
	_check(CombatMathScript.hit_label({"hit_result": CombatMathScript.HitResult.PARRY}) == "Parry",
		"hit_label PARRY -> 'Parry'")
	_check(CombatMathScript.hit_label({"hit_result": CombatMathScript.HitResult.BLOCK}) == "Block",
		"hit_label BLOCK -> 'Block'")
	_check(CombatMathScript.hit_label({"hit_result": CombatMathScript.HitResult.HIT, "is_crit": true}) == "Critical Hit",
		"hit_label crit -> 'Critical Hit'")
	_check(CombatMathScript.hit_label({"hit_result": CombatMathScript.HitResult.HIT}) == "Hit",
		"hit_label plain hit -> 'Hit'")


## The enemy-armor-floor regression: a whiffed player skill must NOT
## call take_damage (Enemy.take_damage floors any amount at 1), so a
## 30-hp dummy at full health stays exactly full after a dodge/parry.
func _test_pipeline_skill_whiff_no_chip() -> void:
	var es = root.get_node_or_null("EntityService")
	_check(es != null, "EntityService autoload present")
	if es == null:
		return

	var caster = _mk_attacker(10)
	root.add_child(caster)
	await process_frame

	var enemy = load("res://entities/enemy.gd").new()
	enemy.display_name = "WhiffDummy"
	# Huge pool: a LANDED execute (dodge caps at 35%, so most executes hit)
	# must never kill the dummy and queue_free it mid-test -- that used to
	# throw "health_component on a previously freed instance".
	enemy.starting_health = 100000
	root.add_child(enemy)
	await process_frame
	es.register_entity(caster)
	es.register_entity(enemy)
	await process_frame

	# Untyped: a `var skill: Skill` annotation would drag skill.gd into
	# this script's boot-time compile (autoloads not ready yet).
	var skill = SkillScript.new()
	skill.skill_name = "WhiffStrike"
	skill.damage = 25
	skill.mana_cost = 0

	# Force a guaranteed miss-family outcome: dodge chance 100%.
	enemy.stats["agility"] = 1000
	await process_frame

	var hp_before: int = enemy.health_component.current_health
	var dealt := 0
	for i in range(20):
		dealt = skill.calculate_damage(caster, enemy)
		if CombatMathScript.is_whiff(int(skill._last_hit_result.get("hit_result", -1))):
			break
	_check(dealt == 0, "forced-dodge calculate_damage returns 0 (got %d)" % dealt)
	# agi 1000 stacks the whole miss family: 5% miss, capped 35% dodge, 25%
	# parry -- so the first whiff is not necessarily EVADE. Assert the
	# contract (a miss-family outcome) rather than the specific flavor.
	_check(CombatMathScript.is_whiff(int(skill._last_hit_result.get("hit_result", -1))),
		"forced-dodge outcome is a miss-family whiff (got %d)" % int(skill._last_hit_result.get("hit_result", -1)))

	# skill.execute re-rolls the table, and dodge caps at 35%, so execute
	# until one swing actually whiffs (P(no whiff in 100) ~= 0). HP pool is
	# huge, so the landed executes along the way are harmless.
	var whiffed_result: Dictionary = {}
	var hp_before_exec: int = enemy.health_component.current_health
	for i in range(100):
		skill.remaining_cooldown = 0.0
		hp_before_exec = enemy.health_component.current_health
		whiffed_result = skill.execute(caster, enemy)
		if bool(whiffed_result.get("whiff", false)):
			break
	await process_frame
	_check(is_instance_valid(enemy), "enemy still valid after execute loop")
	var hp_after_exec: int = enemy.health_component.current_health
	_check(bool(whiffed_result.get("whiff", false)), "skill.execute reports whiff in result")
	_check(hp_after_exec == hp_before_exec,
		"whiffed skill does not chip enemy HP through the armor floor (%d -> %d)" % [hp_before_exec, hp_after_exec])

	es.unregister_entity(caster, "test_cleanup")
	es.unregister_entity(enemy, "test_cleanup")
	caster.free()
	enemy.free()


## The HUD contract: EventHub.hit_resolved fires for BOTH outcomes, with
## the full outcome dictionary riding along.
func _test_pipeline_hit_resolved_signal() -> void:
	var es = root.get_node_or_null("EntityService")
	if es == null:
		_check(false, "EntityService autoload present (hit_resolved test)")
		return
	var hub = root.get_node_or_null("EventHub")
	if hub == null:
		_check(false, "EventHub autoload present (hit_resolved test)")
		return

	var a = _mk_attacker(5)
	root.add_child(a)
	await process_frame
	var d = _mk_defender(5)
	root.add_child(d)
	await process_frame
	es.register_entity(a)
	es.register_entity(d)
	await process_frame

	var events: Array = []
	var cb := func(attacker, defender, outcome, skill, amount: int):
		events.append({"outcome": outcome, "amount": amount})
	hub.hit_resolved.connect(cb)

	var skill = SkillScript.new()
	skill.skill_name = "SignalStrike"
	skill.damage = 8
	skill.mana_cost = 0

	for i in range(10):
		skill.remaining_cooldown = 0.0
		skill.execute(a, d)
		await process_frame

	hub.hit_resolved.disconnect(cb)
	_check(events.size() == 10, "hit_resolved fired once per executed swing (%d/10)" % events.size())
	var carry_outcome := true
	for e in events:
		if not (e["outcome"] is Dictionary and e["outcome"].has("hit_result")):
			carry_outcome = false
			break
	_check(carry_outcome, "hit_resolved carries the full outcome dictionary")

	es.unregister_entity(a, "test_cleanup")
	es.unregister_entity(d, "test_cleanup")
	a.free()
	d.free()
