## CombatMath - Hit calculation for combat
## Handles hit chance, miss, evade, block, parry, crush
extends Node
class_name CombatMath
const Item = preload("res://core/schemas/item.gd")
const StatId = preload("res://core/schemas/stat_id.gd")
const CombatBalanceData = preload("res://core/schemas/combat_balance_data.gd")


## Hit results
enum HitResult {
	HIT,         # Normal hit
	MISS,        # Attacker missed
	EVADE,       # Target evaded (dodge)
	BLOCK,       # Target blocked (partial damage)
	PARRY,       # Target parried (counter-attack chance)
	CRUSH,       # Crushing blow (boss bonus)
	RESIST,      # Magic resistance
	IMMUNE       # Fully immune
}

## Combat ratings (for scaling)
class CombatRatings:
	var hit_rating: float = 0.0

	# Defense ratings
	var dodge_rating: float = 0.0
	var parry_rating: float = 0.0
	var block_rating: float = 0.0

	func _init():
		pass

## Get combat ratings from entity. Duck-typed: bare Entity, Enemy and
## the player body all carry a `stats` dictionary; anything without one
## simply has no ratings.
static func get_entity_ratings(entity) -> CombatRatings:
	var ratings := CombatRatings.new()
	if entity == null or not ("stats" in entity) or not (entity.stats is Dictionary):
		return ratings

	# Check for ratings in entity stats
	if entity.stats.has("hit_rating"):
		ratings.hit_rating = float(entity.stats.get("hit_rating", 0.0))
	if entity.stats.has("dodge_rating"):
		ratings.dodge_rating = float(entity.stats.get("dodge_rating", 0.0))
	if entity.stats.has("parry_rating"):
		ratings.parry_rating = float(entity.stats.get("parry_rating", 0.0))
	if entity.stats.has("block_rating"):
		ratings.block_rating = float(entity.stats.get("block_rating", 0.0))

	return ratings

## Duck-typed stat read: get_stat() when the combatant exposes it (bare
## Entity and the player body both do), raw stats dictionary otherwise.
static func _stat(entity, stat_name: String, default_value: float) -> float:
	if entity == null:
		return default_value
	if entity.has_method("get_stat"):
		return float(entity.get_stat(stat_name))
	if "stats" in entity and entity.stats is Dictionary:
		return float(entity.stats.get(stat_name, default_value))
	return default_value

## Combat ratings live in the `stats` dictionary (hit_rating, dodge_rating,
## ...); unset means unrated.
static func _rating(entity, rating_name: String) -> float:
	if entity == null or not ("stats" in entity) or not (entity.stats is Dictionary):
		return 0.0
	return float(entity.stats.get(rating_name, 0.0))

## The level a combatant actually fights at. Bare Entity, Enemy and the
## player body all carry `level`; a fixture without one is level 1.
static func level_of(entity) -> int:
	if entity == null or not ("level" in entity):
		return 1
	return maxi(int(entity.get("level")), 1)

## An instanced bout's power book marks its fighters after scaling their
## primaries. While that mark is present, the world's general level law
## is OFF (the instance has already brought the fighters together) and
## the level-side hit/armor penalties use one shared reference level.
## Meta is used instead of a stats key so the normalization stays
## bout-local and never leaks into saved character data.
static func is_power_normalized(entity) -> bool:
	if entity == null or not entity.has_method("has_meta"):
		return false
	return entity.has_meta("arena_power_normalized") and bool(entity.get_meta("arena_power_normalized"))

## GENERAL POWER SCALING: the open-world/PvE level law. Equal levels are
## 1.0; a lower-level attacker is scaled down and a higher-level attacker
## up, even when both bodies somehow carry the same stats and gear. This
## is deliberately separate from InstanceContract.power_scale (the bout
## normalization, which moves the other direction for fun): arena and
## duel instances mark their fighters and bypass this multiplier.
## Levels below 1 are treated as 1; invalid tuning falls back to 1.0.
static func level_power_multiplier(attacker_level: int, defender_level: int) -> float:
	var balance := _balance()
	var atk: int = maxi(attacker_level, 1)
	var def: int = maxi(defender_level, 1)
	var gap: int = def - atk
	var raw: float = 1.0 - float(gap) * balance.level_power_per_level
	return clampf(raw, balance.level_power_min_multiplier, balance.level_power_max_multiplier)

## Object-facing form of the general level law. Null refs and normalized
## fighters both resolve to 1.0, so a bare roll fixture cannot invent a
## level gap and an instance bout cannot double-scale.
static func level_power_multiplier_for(attacker, defender) -> float:
	if attacker == null or defender == null:
		return 1.0
	if is_power_normalized(attacker) or is_power_normalized(defender):
		return 1.0
	return level_power_multiplier(level_of(attacker), level_of(defender))

## Apply the world level law to an incoming damage number. THE one home:
## every terminal damage receiver (HealthComponent, Entity, Enemy) calls this
## before armor/shields, so projectiles, DoTs, traps and direct take_damage
## paths that never build a hit table still scale honestly. A source-less
## hit (fall, environment) is 1.0.
static func apply_level_power(amount: int, attacker, defender) -> int:
	if amount <= 0:
		return 0
	var multiplier := level_power_multiplier_for(attacker, defender)
	if is_equal_approx(multiplier, 1.0):
		return amount
	return maxi(1, int(float(amount) * multiplier))

## The record-backed hit/defense tuning. Tests inject a record with
## set_balance_override; the live game resolves it through DataService.
static var _balance_override = null
static var _balance_cache = null

static func set_balance_override(balance) -> void:
	_balance_override = balance
	_balance_cache = null

static func _balance() -> CombatBalanceData:
	if _balance_override != null:
		return _balance_override
	if _balance_cache != null:
		return _balance_cache
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		var ds = tree.root.get_node_or_null(NodePath("DataService"))
		if ds != null and ds.has_method("get_combat_balance"):
			var record = ds.get_combat_balance()
			if record is CombatBalanceData:
				_balance_cache = record
				return _balance_cache
	# A missing record falls back to the schema's declared defaults; the
	# shipped record is the tuning surface, not a second literal table.
	_balance_cache = CombatBalanceData.new()
	return _balance_cache

## Calculate hit chance
static func calculate_hit_chance(attacker_level: int, defender_level: int, hit_rating: float = 0.0) -> float:
	var balance := _balance()

	# Level penalty: attacking UP is harder. (attacker - defender) goes
	# negative when the defender is higher, which is when the attacker
	# should miss more.
	var level_penalty: float = clampf(
		float(attacker_level - defender_level) * balance.hit_level_penalty_per_level,
		-balance.hit_level_penalty_cap, 0.0)

	var rating_contribution: float = 0.0
	if attacker_level > 0:
		rating_contribution = hit_rating / (float(attacker_level) * balance.hit_rating_level_factor)

	var final_hit: float = balance.hit_base + level_penalty + rating_contribution
	# No target is fully unhittable.
	return clampf(final_hit, balance.hit_floor, 1.0)

## Calculate dodge chance. The record owns the base, the agility curve,
## the level bonus, the rating divisor and the cap.
static func calculate_dodge_chance(defender_level: int, dodge_rating: float, agility: float = 10.0) -> float:
	var balance := _balance()
	var rating_contribution := dodge_rating / balance.dodge_rating_divisor
	var agility_contribution: float = (agility - 10.0) * balance.dodge_per_agility
	var level_bonus := defender_level * balance.dodge_level_bonus
	return clampf(balance.dodge_base + rating_contribution + agility_contribution + level_bonus, 0.0, balance.dodge_cap)

## Calculate parry chance. The record owns the base, strength curve,
## level bonus, rating divisor, shield multiplier and cap.
static func calculate_parry_chance(defender_level: int, parry_rating: float, has_shield: bool = false, strength: float = 10.0) -> float:
	var balance := _balance()
	var rating_contribution := parry_rating / balance.parry_rating_divisor
	var strength_contribution: float = (strength - 10.0) * balance.parry_per_strength
	var level_bonus := defender_level * balance.parry_level_bonus
	var chance: float = balance.parry_base + rating_contribution + strength_contribution + level_bonus
	if not has_shield:
		chance *= balance.parry_no_shield_multiplier
	return clampf(chance, 0.0, balance.parry_cap)

## Calculate block chance. Shield-gated: without a shield there is no
## block at all. The record owns the base, vitality curve, rating divisor
## and cap.
static func calculate_block_chance(defender_level: int, block_rating: float, has_shield: bool = false, vitality: float = 10.0) -> float:
	if not has_shield:
		return 0.0

	var balance := _balance()
	var rating_contribution := block_rating / balance.block_rating_divisor
	var vitality_contribution: float = (vitality - 10.0) * balance.block_per_vitality
	return clampf(balance.block_base + rating_contribution + vitality_contribution, 0.0, balance.block_cap)

## Calculate block value (damage reduction)
static func calculate_block_value(block_rating: float, strength: int) -> float:
	var balance := _balance()
	var strength_contribution := strength * balance.block_value_per_strength
	var rating_contribution := block_rating / balance.block_value_rating_divisor
	return balance.block_value_base + strength_contribution + rating_contribution

## Percentage armor curve. Flat armor (item armor_value for players,
## EnemyData.armor/resistance for mobs, or a bare Entity's stat defense)
## is divided by itself plus a level-scaled constant. The attacker's level
## is the penetration scale: a low-level attacker faces a much larger
## relative armor pool, while a high-level attacker cuts through it. A
## defender above the attacker adds effective armor, so level gaps bite in
## both directions.
static func calculate_armor_reduction(armor: float, attacker_level: int, defender_level: int) -> float:
	if armor <= 0.0:
		return 0.0
	var balance := _balance()
	var gap: int = maxi(0, defender_level - attacker_level)
	var effective_armor: float = armor * (1.0 + float(gap) * balance.armor_defender_level_bonus)
	var level_scale: float = balance.armor_curve_base \
			+ float(maxi(attacker_level, 1)) * balance.armor_curve_per_attacker_level
	var denominator: float = effective_armor + level_scale
	if denominator <= 0.0:
		return 0.0
	return clampf(effective_armor / denominator, 0.0, balance.armor_mitigation_cap)

## Apply the shared percentage mitigation to one hit. `defense_multiplier`
## and `armor_multiplier` are the full StatId multipliers (1.0 base plus any
## authored delta); `flat_reduction` is the damage_reduction payload, stacked
## after the armor curve. The result always leaves at least 1 point so chip
## damage still lands.
##
## power_normalized is the instance flag: an arena/duel fighter has already
## been stat-normalized, so the armor curve reads one shared level instead
## of the raw level gap. Damage call sites pass CombatMath.is_power_normalized
## for either combatant; hand-built callers keep the default and the normal
## world law.
static func calculate_mitigation(amount: int, armor: float, attacker_level: int, defender_level: int,
		defense_multiplier: float = 1.0, armor_multiplier: float = 1.0,
		flat_reduction: float = 0.0, power_normalized: bool = false,
		school_resist: float = 0.0) -> int:
	if amount <= 0:
		return 0
	if power_normalized:
		attacker_level = defender_level
	var effective_armor: float = maxf(0.0, armor * defense_multiplier * armor_multiplier)
	var reduction := calculate_armor_reduction(effective_armor, attacker_level, defender_level)
	var flat: float = clampf(flat_reduction, 0.0, StatId.MAX_DAMAGE_REDUCTION)
	var total: float = reduction + flat * (1.0 - reduction)
	# Per-school resistance is a separate ward layered after armor and flat
	# reduction, so a fire ward protects a cloth wearer who has no plate.
	var resist: float = clampf(school_resist, 0.0, StatId.MAX_RESIST)
	total = 1.0 - (1.0 - total) * (1.0 - resist)
	return maxi(1, int(float(amount) * (1.0 - total)))

## A body's resistance to one damage school, read from the canonical
## `stats` block. Null/statless bodies and unknown schools take no ward;
## the value is clamped by StatId.school_resist_of.
static func school_resist_for(entity, damage_type: String) -> float:
	if entity == null or not ("stats" in entity) or not (entity.stats is Dictionary):
		return 0.0
	return StatId.school_resist_of(entity.stats, damage_type)

## Calculate full hit result -- the MWo-style single-roll combat table.
##
## ONE randf() in [0, 1) is split into cumulative segments, in order:
## MISS -> DODGE -> PARRY -> BLOCK -> CRIT -> HIT. Crit takes whatever
## the defensive segments leave, so a defender-heavy target eats into
## the attacker's crit rate instead of the table summing past 1. Misses
## are rolled first and can never crit (MWo rule).
##
## Duck-typed for both combatant families: bare Entity / Enemy nodes AND
## the player body (a CharacterBody3D with no combat_component). Every
## property access is guarded with `in` / has_method(); the old version
## dereferenced attacker.combat_component directly and would have thrown
## on the live player the first time it was ever called.
static func calculate_hit(attacker, defender, skill = null) -> Dictionary:
	var result := {
		"hit_result": HitResult.HIT,
		"hit_chance": 1.0,
		"is_crit": false,
		"damage_multiplier": 1.0,
		"blocked_damage": 0,
		"damage": 0,
		"attacker": attacker,
		"defender": defender
	}
	if attacker == null or defender == null:
		return result

	var attacker_ratings := get_entity_ratings(attacker)
	var defender_ratings := get_entity_ratings(defender)

	var attacker_level: int = level_of(attacker)
	var defender_level: int = level_of(defender)
	# The room's power book already normalized the bout: level-side hit
	# penalties read one shared reference, exactly like the stat book.
	if is_power_normalized(attacker) or is_power_normalized(defender):
		var reference: int = maxi(attacker_level, defender_level)
		attacker_level = reference
		defender_level = reference

	# --- Segments -----------------------------------------------------
	var hit_chance := calculate_hit_chance(attacker_level, defender_level, attacker_ratings.hit_rating)
	# A haste helps you land: fold the attacker's attack-speed bonus into hit
	# chance before the miss segment is derived from it. The record's hit floor
	# is the same floor the helper applies.
	hit_chance = clampf(hit_chance + StatId.hit_bonus_for_attack_speed(_attack_speed_for(attacker)), _balance().hit_floor, 1.0)
	result["hit_chance"] = hit_chance
	var miss_chance: float = maxf(0.0, 1.0 - hit_chance)

	var has_shield := _has_shield(defender)
	var dodge_chance := calculate_dodge_chance(
		defender_level, defender_ratings.dodge_rating, _stat(defender, "agility", 10.0))
	var parry_chance := calculate_parry_chance(
		defender_level, defender_ratings.parry_rating, has_shield,
		_stat(defender, "strength", 10.0))
	# Wrist shields are a lesser family: they open the lane but only a
	# fraction of the block chance/value of a normal shield.
	var shield_scale := _shield_block_scale(defender)
	var block_chance := calculate_block_chance(
		defender_level, defender_ratings.block_rating, has_shield,
		_stat(defender, "vitality", 10.0)) * shield_scale

	var crit_chance := _crit_chance_for(attacker, skill)
	var crit_segment: float = maxf(0.0, 1.0 - (miss_chance + dodge_chance + parry_chance + block_chance))
	crit_chance = minf(crit_chance, crit_segment)

	# --- The single roll -----------------------------------------------
	var roll := randf()
	var cursor := 0.0

	cursor += miss_chance
	if roll < cursor:
		result["hit_result"] = HitResult.MISS
		return result

	cursor += dodge_chance
	if roll < cursor:
		result["hit_result"] = HitResult.EVADE
		return result

	cursor += parry_chance
	if roll < cursor:
		result["hit_result"] = HitResult.PARRY
		return result

	cursor += block_chance
	if roll < cursor:
		result["hit_result"] = HitResult.BLOCK
		result["blocked_damage"] = int(calculate_block_value(
			defender_ratings.block_rating, int(_stat(defender, "strength", 10.0))) * shield_scale)
		return result

	cursor += crit_chance
	if roll < cursor:
		result["is_crit"] = true
		result["damage_multiplier"] = _crit_multiplier_for(attacker)
		result["blessing_multiplier"] = _blessing_multiplier_for(attacker)
		return result

	# Remaining roll width is the plain-hit segment.
	result["blessing_multiplier"] = _blessing_multiplier_for(attacker)
	return result

## HUD-facing label for a hit-result dictionary (floats, log lines,
## toasts). Kept next to the table so the palette and the roll cannot
## drift apart; keys match DamageNumbers.show_miss's palette entries.
static func hit_label(hit_result: Dictionary) -> String:
	match hit_result.get("hit_result", HitResult.HIT):
		HitResult.MISS:
			return "Miss"
		HitResult.EVADE:
			return "Dodge"
		HitResult.PARRY:
			return "Parry"
		HitResult.BLOCK:
			return "Block"
		HitResult.CRUSH:
			return "Crush"
		HitResult.RESIST:
			return "Resist"
		HitResult.IMMUNE:
			return "Immune"
		_:
			return "Critical Hit" if hit_result.get("is_crit", false) else "Hit"

## True when the outcome deals no damage and no on-hit effects (used by
## Skill.execute and CombatSystem._apply_hit to skip take_damage(0) --
## the Enemy armor floor would turn a miss into a 1-damage chip).
static func is_whiff(outcome: int) -> bool:
	return outcome == HitResult.MISS \
			or outcome == HitResult.EVADE \
			or outcome == HitResult.PARRY \
			or outcome == HitResult.IMMUNE

## Calculate damage with hit result. Miss-family outcomes deal nothing
## (the callers skip take_damage entirely); blocks deal partial damage
## with a 1-point floor so a blocked hit still chips.
static func calculate_damage(base_damage: int, hit_result: Dictionary) -> int:
	var outcome: int = int(hit_result.get("hit_result", HitResult.HIT))
	if is_whiff(outcome):
		return 0

	var damage := float(base_damage)

	# Apply damage multiplier (crits)
	damage *= float(hit_result.get("damage_multiplier", 1.0))

	# Daily Class Blessing (prd-psy.md section 8): the shard's lucky
	# class deals +20% for the day. Read from the hit_result so every
	# damage path through calculate_hit carries it (skill.gd callsites,
	# basic attacks, traps). Stamp in calculate_hit below.
	damage *= float(hit_result.get("blessing_multiplier", 1.0))

	# Apply resist
	if outcome == HitResult.RESIST:
		damage *= (1.0 - float(hit_result.get("resist_percent", 0.0)))

	# Apply block reduction (blocks still deal partial damage)
	if outcome == HitResult.BLOCK:
		damage = maxf(1.0, damage - float(hit_result.get("blocked_damage", 0)))

	return maxi(1, int(damage))


## Daily Class Blessing lookup, duck-typed: the player body carries
## character_class; bare Entity/Enemy do not (enemies are never
## blessed -- the sky favors the playable classes). Static + null-safe
## so callers never crash when SignService is absent (script-mode
## tests, headless probes).
static func _blessing_multiplier_for(attacker) -> float:
	if attacker == null or not ("character_class" in attacker):
		return 1.0
	var cid := str(attacker.get("character_class"))
	if cid.is_empty():
		return 1.0
	# Resolve the autoload late (parse-time bare identifiers would break
	# --script mode compilation of this file).
	var ml := Engine.get_main_loop()
	if ml == null or not (ml is SceneTree):
		return 1.0
	var svc = (ml as SceneTree).root.get_node_or_null("SignService")
	if svc == null or not svc.has_method("is_class_blessed"):
		return 1.0
	return float(svc.BLESSED_DAMAGE_MULTIPLIER) if svc.is_class_blessed(cid) else 1.0

## Weapon crit identity on the caster axes. get_crit_chance already folds
## the main hand in on the agility axis; a magical/heal crit derives off
## INT/WIS instead, so it must add the same weapon (and dual-wield off-hand)
## crit here or a wand/relic's authored crit% would never land.
static func _weapon_crit_chance_delta(attacker) -> float:
	if attacker == null or "inventory_component" not in attacker:
		return 0.0
	var bag = attacker.get("inventory_component")
	if bag == null or not bag.has_method("get_equipped"):
		return 0.0
	var delta := 0.0
	var main = bag.get_equipped(Item.EquipSlot.MAIN_HAND)
	if main != null and main.has_method("get_effective_crit_chance"):
		delta += float(main.get_effective_crit_chance())
	if bag.has_method("get_offhand_crit_chance"):
		delta += float(bag.get_offhand_crit_chance())
	return delta

## Crit chance off the combatant's own roll when it has one (Entity /
## the player body get_crit_chance), stat-derived otherwise. Both paths read
## the crit_chance stat delta through StatId, so a crit buff lands on any body
## (the accessor no longer shadows the stat block).
##
## The crit AXIS is the caster's identity, chosen by StatId.crit_axis_for: a
## MAGICAL skill crits off INT (a mage's crit climbs with the stat its damage
## already scales on), a HEAL off WIS (a healer's crit is restoration power),
## and anything else off agility (the weapon lanes). The `crit_chance` delta is
## added on top on every axis, so a crit buff helps any class, and
## `_crit_multiplier_for` supplies the body's crit_damage.
static func _crit_chance_for(attacker, skill = null) -> float:
	var delta := _stat(attacker, "crit_chance", 0.0)
	var is_heal: bool = skill != null and "heal_amount" in skill and int(skill.heal_amount) > 0
	var school: String = "physical"
	if skill != null and "damage_type" in skill:
		school = str(skill.damage_type)
	var axis: String = StatId.crit_axis_for(school, is_heal)
	# A caster axis (int/wis) derives straight off the stat; the agility axis
	# prefers the body's own roll so a weapon/class crit buff lands.
	if axis != "agility":
		delta += _weapon_crit_chance_delta(attacker)
		return StatId.crit_chance_on_axis(axis, _stat(attacker, axis, 10.0), delta)
	if attacker != null and attacker.has_method("get_crit_chance"):
		return float(attacker.get_crit_chance())
	return StatId.crit_chance_of(_stat(attacker, "agility", 10.0), delta)

static func _crit_multiplier_for(attacker) -> float:
	if attacker != null and attacker.has_method("get_crit_multiplier"):
		return float(attacker.get_crit_multiplier())
	return StatId.crit_damage_of(_stat(attacker, "crit_damage", 0.0))

## The attacker's attack-speed multiplier, duck-typed through the body's own
## get_attack_speed when it has one, else the StatId formula off the raw stat
## block -- the same two-path read the crit helpers use.
static func _attack_speed_for(attacker) -> float:
	if attacker != null and attacker.has_method("get_attack_speed"):
		return float(attacker.get_attack_speed())
	var delta := _stat(attacker, "attack_speed_multiplier", 1.0) - 1.0
	return StatId.attack_speed_of(_stat(attacker, "agility", 10.0), delta)

## The off-hand block scale: 1.0 for a normal shield, 0.4 for a wrist
## shield, 0.0 when there is no legal off-hand. Duck-typed so the player
## body and an equipped Enemy read the same lane.
static func _shield_block_scale(entity) -> float:
	if entity == null or not ("inventory_component" in entity):
		return 0.0
	var inv = entity.inventory_component
	if inv == null or not inv.has_method("get_offhand_block_scale"):
		return 0.0
	return float(inv.get_offhand_block_scale())

## Helper to check if defender has shield equipped. The block scale owns
## shield identity, brokenness, and the wrist family in one place.
static func _has_shield(entity) -> bool:
	return _shield_block_scale(entity) > 0.0
