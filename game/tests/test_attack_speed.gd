## test_attack_speed.gd - attack speed is ONE multiplier (StatId) that fans
## out to four effects, and a haste buff actually lands:
##
##   1. attack_speed_of is the one formula (1.0 base + agility + delta), and
##      Entity.get_attack_speed reads the attack_speed_multiplier stat delta
##      -- the field a haste writes. Before this, the field was declared but
##      never folded into the stat block, so a haste was inert.
##   2. A haste status effect (speed_type "haste") raises attack speed and
##      lifts movement by only a FRACTION of it -- the rogue's axis is attack
##      speed, not raw speed.
##   3. Attack speed fans out: it adds hit chance, shortens cooldowns (CDR),
##      and speeds DoT/HoT ticks.
##   4. Clamps hold: attack speed <= 2.5, CDR <= MAX_COOLDOWN_REDUCTION.
##
## Run headless:
##   cd game && godot --headless --path . --script res://tests/test_attack_speed.gd
## Exit 0 = all pass.
extends SceneTree

const StatId = preload("res://core/schemas/stat_id.gd")
const CombatMath = preload("res://core/services/combat_math.gd")
const Skill = preload("res://core/combat/skill.gd")
const Factory = preload("res://core/combat/status_effect_factory.gd")
const StatusEffectData = preload("res://core/schemas/status_effect_data.gd")
const PlayerBaseScript = preload("res://entities/player/player_base.gd")

var _pass := 0
var _fail := 0

func _initialize() -> void:
	await process_frame
	await _run()
	print("--- ATTACK SPEED: %d passed, %d failed ---" % [_pass, _fail])
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
	var e: Node = load("res://core/entities/entity.gd").new()
	root.add_child(e)
	e.max_health = 100000
	e.current_health = 100000
	return e

func _run() -> void:
	# --- 1. The one formula + the stat delta -----------------------------
	_assert(_approx(StatId.attack_speed_of(10.0, 0.0), 1.10),
		"attack_speed_of: 1.0 base + agility*0.01")
	_assert(_approx(StatId.attack_speed_of(10.0, 0.2), 1.30),
		"attack_speed_of folds the haste delta")

	var e := _entity()
	# A bare Entity seeds agility 10 => 1.10.
	_assert(_approx(e.get_attack_speed(), 1.10), "Entity base attack speed = 1.10")
	e.stats["attack_speed_multiplier"] = 1.2  # a +20% haste already applied
	_assert(_approx(e.get_attack_speed(), 1.30),
		"Entity.get_attack_speed reads the haste stat delta (was inert)")

	# --- 2. A haste effect lands, and lifts movement only slightly -------
	var data := StatusEffectData.new()
	data.id = "test_haste"
	data.display_name = "Test Haste"
	data.speed_type = "haste"
	data.speed_percent = 20.0
	data.duration = 10.0
	var fx = Factory.from_data(data)
	_assert(fx != null, "haste data builds a status effect")
	_assert(_approx(float(fx.attack_speed_multiplier), 0.2),
		"haste stores +0.2 attack speed")
	_assert(_approx(float(fx.movement_speed_multiplier), 0.06),
		"haste lifts movement by only HASTE_MOVE_FRACTION (0.3) of +0.2")

	var body := _entity()
	body.apply_status_effect(fx)
	_assert(_approx(float(body.stats.get("attack_speed_multiplier", 1.0)), 1.2),
		"the haste folded into the body's stat block (the inert bug is fixed)")
	_assert(body.get_attack_speed() > 1.1, "the hasted body swings faster")

	# --- 3. Fan-out: hit, CDR, DoT tick ----------------------------------
	_assert(StatId.hit_bonus_for_attack_speed(1.2) > 0.0, "haste adds hit chance")
	_assert(_approx(StatId.hit_bonus_for_attack_speed(1.2), 0.2 * StatId.HIT_PER_ATTACK_SPEED),
		"hit bonus scales with the attack-speed surplus")
	_assert(_approx(StatId.hit_bonus_for_attack_speed(0.8), 0.0),
		"a slow grants no hit bonus")
	_assert(StatId.cdr_for_attack_speed(1.2) > 0.0, "haste shortens cooldowns")
	_assert(StatId.dot_rate_for_attack_speed(1.5) > 1.0, "haste speeds DoT ticks")

	# A hasted caster's DoT interval is shorter than a plain caster's.
	var plain := _entity()
	var hasted := _entity()
	hasted.stats["attack_speed_multiplier"] = 1.5
	var dot_skill := Skill.new()
	dot_skill.skill_id = "test_dot"
	dot_skill.skill_name = "Test DoT"
	dot_skill.dot_damage = 10
	dot_skill.dot_duration = 6.0
	dot_skill.dot_tick_rate = 1.0
	var dot_target := _entity()
	dot_skill.applyDoT(hasted, dot_target)
	var found_fast := false
	for f in dot_target.status_effects:
		if float(f.tick_interval) < 1.0:
			found_fast = true
	_assert(found_fast, "a hasted caster's DoT ticks faster (interval < 1.0)")

	# --- 4. Clamps -------------------------------------------------------
	_assert(_approx(StatId.attack_speed_of(100000.0, 0.0), StatId.MAX_ATTACK_SPEED_MULT),
		"attack speed is clamped to MAX_ATTACK_SPEED_MULT")
	_assert(StatId.cdr_for_attack_speed(StatId.MAX_ATTACK_SPEED_MULT) + 0.0 <= 1.0 + 0.0001,
		"haste CDR stays in a sane band")

	# --- 5. The rogue class starts faster than a warrior -----------------
	var rogue := load("res://data/classes/class_human_marksman.tres")
	var warrior := load("res://data/classes/class_human_warrior.tres")
	if rogue != null and warrior != null:
		_assert(float(rogue.get("attack_speed_bonus")) > float(warrior.get("attack_speed_bonus")),
			"the rogue's attack_speed_bonus beats the warrior's")
		var rogue_speed := StatId.attack_speed_of(10.0, float(rogue.get("attack_speed_bonus")))
		var warrior_speed := StatId.attack_speed_of(10.0, float(warrior.get("attack_speed_bonus")))
		_assert(rogue_speed > warrior_speed,
			"a rogue body swings faster than a warrior body")

		# The class cadence must reach the actual player body, not just the
		# data file: _apply_class_crit_identity folds attack_speed_bonus into
		# the same stat block CombatMath/Skill read.
		var rogue_body = PlayerBaseScript.new()
		rogue_body.stats["agility"] = 10
		rogue_body._apply_class_crit_identity(rogue)
		_assert(_approx(rogue_body.get_attack_speed(), 1.25),
			"a marksman body reaches 1.25 attack speed from class cadence")
		var warrior_body = PlayerBaseScript.new()
		warrior_body.stats["agility"] = 10
		warrior_body._apply_class_crit_identity(warrior)
		_assert(warrior_body.get_attack_speed() > 1.10 \
				and warrior_body.get_attack_speed() < rogue_body.get_attack_speed(),
			"the warrior has cadence above base but below the rogue")
		var guardian := load("res://data/classes/class_human_guardian.tres")
		var guardian_body = PlayerBaseScript.new()
		guardian_body.stats["agility"] = 5
		guardian_body._apply_class_crit_identity(guardian)
		_assert(_approx(guardian_body.get_attack_speed(), 1.0),
			"the guardian's slower class cadence lands at 1.0 with agility 5")
