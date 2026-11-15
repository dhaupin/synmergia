## test_crit_system.gd - crit is ONE game-wide system (StatId), not a
## per-body constant:
##
##   1. crit_chance / crit_damage are real StatId keys, and the StatId
##      formula (base + agility + delta) is the one crit source.
##   2. Entity and the player body derive crit through that formula, so a
##      crit_chance / crit_damage stat delta actually lands (the old
##      hardcoded accessors shadowed the stat block -- the bug this fixes).
##   3. A MAGICAL skill crits off INT; a physical one off agility.
##   4. A heal can crit: the heal twin of the damage crit, so a healer's
##      crit stat is worth something.
##   5. Clamps hold: crit chance <= 1.0, crit damage <= 5.0.
##
## Run headless:
##   cd game && godot --headless --path . --script res://tests/test_crit_system.gd
## Exit 0 = all pass.
extends SceneTree

const StatId = preload("res://core/schemas/stat_id.gd")
const CombatMath = preload("res://core/services/combat_math.gd")
const Skill = preload("res://core/combat/skill.gd")

var _pass := 0
var _fail := 0

func _initialize() -> void:
	await process_frame
	await _run()
	print("--- CRIT SYSTEM: %d passed, %d failed ---" % [_pass, _fail])
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
	# --- 1. StatId vocabulary + formula ---------------------------------
	_assert(StatId.is_valid("crit_chance"), "crit_chance is a StatId key")
	_assert(StatId.is_valid("crit_damage"), "crit_damage is a StatId key")
	_assert(StatId.FLAT_KEYS.has("crit_chance"), "crit_chance is a flat delta")
	_assert(StatId.FLAT_KEYS.has("crit_damage"), "crit_damage is a flat delta")
	_assert(_approx(StatId.crit_chance_of(10.0, 0.0), 0.05 + 10.0 * 0.003),
		"crit formula: base + agility")
	_assert(_approx(StatId.crit_damage_of(0.0), 1.5), "crit multiplier base is 1.5")
	_assert(_approx(StatId.crit_damage_of(0.25), 1.75), "crit_damage is additive on 1.5")

	# --- 2. A crit stat delta actually lands on a body -------------------
	var e := _entity()
	# A bare Entity seeds agility 10 => 0.05 + 0.03 = 0.08.
	_assert(_approx(e.get_crit_chance(), 0.08), "Entity base crit = 0.08 at agility 10")
	_assert(_approx(e.get_crit_multiplier(), 1.5), "Entity base crit mult = 1.5")
	e.stats["crit_chance"] = 0.20
	_assert(_approx(e.get_crit_chance(), 0.28),
		"crit_chance stat delta lands (the shadowing bug is fixed)")
	e.stats["crit_damage"] = 0.5
	_assert(_approx(e.get_crit_multiplier(), 2.0), "crit_damage stat delta lands")

	# --- 3. Magical crits off INT, physical off agility ------------------
	var mage := _entity()
	mage.stats["intelligence"] = 100
	mage.stats["agility"] = 10
	var magical := Skill.new()
	magical.damage_type = "magical"
	var physical := Skill.new()
	physical.damage_type = "physical"
	# THE one axis formula (base + axis_value * rate + delta), same shape on
	# every axis. INT 100 => 0.05 + 100*0.005 = 0.55; agility 10 => 0.08.
	var magic_crit: float = CombatMath._crit_chance_for(mage, magical)
	var phys_crit: float = CombatMath._crit_chance_for(mage, physical)
	_assert(_approx(magic_crit, 0.05 + 100.0 * StatId.CRIT_PER_INTELLIGENCE),
		"magical skill crits off INT (base + 0.5%% per int)")
	_assert(_approx(phys_crit, 0.08), "physical skill crits off agility")

	# A HEAL crits off WIS, not agility/INT -- the healer's own axis. Same body
	# as the mage, so only the axis differs.
	mage.stats["wisdom"] = 200
	var heal_skill := Skill.new()
	heal_skill.heal_amount = 100
	var heal_crit: float = CombatMath._crit_chance_for(mage, heal_skill)
	_assert(_approx(heal_crit, 0.05 + 200.0 * StatId.CRIT_PER_WISDOM),
		"a heal crits off WIS (base + 0.3%% per wis)")
	# The chooser is the one home for the axis mapping.
	_assert(StatId.crit_axis_for("magical", false) == "intelligence",
		"axis: magical damage -> intelligence")
	_assert(StatId.crit_axis_for("physical", true) == "wisdom",
		"axis: a heal -> wisdom whatever the school")
	_assert(StatId.crit_axis_for("physical", false) == "agility",
		"axis: physical damage -> agility")

	# --- 4. Crit heal ----------------------------------------------------
	# A heal skill with a guaranteed-crit caster heals more than without.
	var healer := _entity()
	healer.stats["wisdom"] = 0  # healing_power = 0
	var mend := Skill.new()
	mend.heal_amount = 100
	# Force the crit chance to 1.0 so the roll is deterministic.
	healer.stats["crit_chance"] = 1.0
	healer.stats["crit_damage"] = 0.0
	var crit_heal: int = mend.calculate_healing(healer)
	_assert(mend._last_heal_was_crit, "heal rolled a crit at crit_chance 1.0")
	_assert(crit_heal == 150, "crit heal = 1.5x (100 -> 150)")
	# crit_chance 0 => never crits, plain heal.
	healer.stats["crit_chance"] = -1.0
	var plain_heal: int = mend.calculate_healing(healer)
	_assert(not mend._last_heal_was_crit, "no crit at zero crit chance")
	_assert(plain_heal == 100, "plain heal is the raw amount")

	# --- 5. Clamps -------------------------------------------------------
	_assert(StatId.crit_chance_of(100000.0, 0.0) <= StatId.MAX_CRIT_CHANCE,
		"crit chance is clamped to 1.0")
	_assert(StatId.crit_damage_of(100.0) <= StatId.MAX_CRIT_DAMAGE,
		"crit damage is clamped to 5.0")

	# --- 6. Enemies + bosses carry crit --------------------------------
	var boss := load("res://data/enemies/enemy_void_lord.tres")
	if boss != null:
		var boss_stats: Dictionary = boss.get_stats_for_level()
		_assert(float(boss_stats.get("crit_chance", 0.0)) > 0.0,
			"a boss template authors crit_chance")
		_assert(float(boss_stats.get("crit_damage", 0.0)) > 0.0,
			"a boss template authors crit_damage")

	# --- 6b. The SPAWNED entity carries the authored crit ----------------
	# The bug this pins: five spawn paths each hand-copied the primaries and
	# three of them dropped the crit identity, so an authored boss crit never
	# reached the spawned entity (only the template "authored" it, which is all
	# the old check looked at). One seeder owns the copy now.
	if boss != null:
		var boss_body := _entity()
		boss.apply_stats_to(boss_body)
		_assert(_approx(float(boss_body.stats.get("crit_chance", 0.0)), boss.crit_chance),
				"apply_stats_to copies the template's crit_chance onto the body")
		_assert(_approx(float(boss_body.stats.get("crit_damage", 0.0)), boss.crit_damage),
				"apply_stats_to copies the template's crit_damage onto the body")
		_assert(_approx(boss_body.get_crit_chance(),
				StatId.crit_chance_of(float(boss.agility), boss.crit_chance)),
				"the seeded body's crit = the StatId formula on the seeded stats")

	# A REAL spawn through the shared pipeline: the entity, not the template,
	# must carry the crit. Guarded on the autoload so a bare script run still
	# exercises the seeder assertions above.
	var ss = root.get_node_or_null("SpawnService")
	if ss != null and ss.has_method("spawn_boss"):
		var spawned = ss.spawn_boss("void_lord", Vector3.ZERO, "zone_test", "", [], -1, -1)
		if spawned != null:
			_assert(float(spawned.stats.get("crit_chance", 0.0)) > 0.0,
					"a spawned boss ENTITY carries the authored crit_chance")
			_assert(float(spawned.stats.get("crit_damage", 0.0)) > 0.0,
					"a spawned boss ENTITY carries the authored crit_damage")
			var agility_only := StatId.crit_chance_of(
					float(spawned.stats.get("agility", 10.0)), 0.0)
			_assert(spawned.get_crit_chance() > agility_only,
					"the spawned boss crits ABOVE its agility-only fallback")
			if is_instance_valid(spawned):
				spawned.queue_free()

	# --- 7. A ranger class starts with a higher base crit ----------------
	# The ranger trio authors the highest crit_chance_bonus of any lane.
	var ranger := load("res://data/classes/class_human_marksman.tres")
	var warrior := load("res://data/classes/class_human_warrior.tres")
	if ranger != null and warrior != null:
		_assert(float(ranger.get("crit_chance_bonus")) > float(warrior.get("crit_chance_bonus")),
			"the ranger's crit_chance_bonus beats the warrior's")
		# Fold the class bonus through the same StatId formula a body uses.
		var ranger_crit := StatId.crit_chance_of(10.0, float(ranger.get("crit_chance_bonus")))
		var warrior_crit := StatId.crit_chance_of(10.0, float(warrior.get("crit_chance_bonus")))
		_assert(ranger_crit > warrior_crit,
			"a ranger body's crit chance beats a warrior body's")

	# --- 8. EVERY playable class carries a real crit identity ------------
	# "Every class needs the crit system applied." The ranger trio used to be
	# the only lanes authoring crit; the other 15 sat at the 0.0/0.0 default,
	# so a warrior/tank/mage/healer/cleric had no crit identity at all. Each
	# playable class must now author a positive crit chance AND damage, and the
	# damage must be a real multiplier bump (not just a cosmetic chance).
	var cls_dir := DirAccess.open("res://data/classes")
	var no_crit: Array = []
	var checked := 0
	if cls_dir != null:
		cls_dir.list_dir_begin()
		var fn := cls_dir.get_next()
		while fn != "":
			if fn.ends_with(".tres") and not fn.begins_with("class_gm_"):
				var cd = load("res://data/classes/%s" % fn)
				if cd != null:
					checked += 1
					var ch := float(cd.get("crit_chance_bonus"))
					var dm := float(cd.get("crit_damage_bonus"))
					if ch <= 0.0 or dm <= 0.0:
						no_crit.append("%s (chance %.3f, dmg %.3f)" % [fn, ch, dm])
			fn = cls_dir.get_next()
	_assert(checked == 18, "18 playable classes checked (got %d)" % checked)
	_assert(no_crit.is_empty(),
		"every playable class authors crit chance AND damage: %s" % ", ".join(no_crit))
	# The crit damage is a real multiplier on the 1.5 base, not a no-op.
	if warrior != null:
		var w_dmg := StatId.crit_damage_of(float(warrior.get("crit_damage_bonus")))
		_assert(w_dmg > StatId.BASE_CRIT_DAMAGE,
			"a warrior's crit_damage_bonus lifts the 1.5 multiplier")
