## CombatMath - Hit calculation for combat
## Handles hit chance, miss, evade, block, parry, crush
extends Node
class_name CombatMath
const Item = preload("res://core/schemas/item.gd")


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
	var crit_rating: float = 0.0
	var haste_rating: float = 0.0
	var mastery_rating: float = 0.0
	var versatility_rating: float = 0.0
	var leech_rating: float = 0.0

	# Defense ratings
	var dodge_rating: float = 0.0
	var parry_rating: float = 0.0
	var block_rating: float = 0.0
	var crit_avoidance_rating: float = 0.0

	func _init():
		pass

## Get combat ratings from entity. Duck-typed: bare Entity, Enemy and
## PlayerController all carry a `stats` dictionary; anything without one
## simply has no ratings.
static func get_entity_ratings(entity) -> CombatRatings:
	var ratings := CombatRatings.new()
	if entity == null or not ("stats" in entity) or not (entity.stats is Dictionary):
		return ratings

	# Check for ratings in entity stats
	if entity.stats.has("crit_rating"):
		ratings.crit_rating = float(entity.stats.get("crit_rating", 0.0))
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
## Entity and PlayerController both do), raw stats dictionary otherwise.
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

## Calculate hit chance
static func calculate_hit_chance(attacker_level: int, defender_level: int, hit_rating: float = 0.0) -> float:
	var base_hit := 0.95  # 95% base hit

	# Level penalty: attacking UP is harder. The old formula clamped
	# (defender - attacker) into [-0.30, 0.0], which clamped every
	# positive (defender higher) to 0.0 and instead penalized attackers
	# for fighting DOWN -- exactly backwards. (attacker - defender) goes
	# negative when the defender is higher, which is when the attacker
	# should miss more.
	var level_penalty: float = clampf(float(attacker_level - defender_level) * 0.01, -0.30, 0.0)

	# Rating contribution (each rating point gives small bonus)
	# At level 60, ~40 rating = 1% hit
	var rating_contribution: float = 0.0
	if attacker_level > 0:
		rating_contribution = hit_rating / (float(attacker_level) * 10.0)

	var final_hit: float = base_hit + level_penalty + rating_contribution
	# Floor at 5%: no target is fully unhittable.
	return clampf(final_hit, 0.05, 1.0)

## Calculate crit chance
static func calculate_crit_chance(base_crit: float, crit_rating: float, target_crit_avoidance: float = 0.0) -> float:
	var rating_contribution := crit_rating / 45.0  # ~45 rating = 1% crit at level 60
	var final_crit := base_crit + rating_contribution - target_crit_avoidance
	return clampf(final_crit, 0.0, 1.0)

## Calculate dodge chance. Stat-derived: 3% base plus 0.15% per agility
## point above 10, so a fresh level-1 human (agi 10) sits at ~3%.
static func calculate_dodge_chance(defender_level: int, dodge_rating: float, agility: float = 10.0) -> float:
	var base_dodge := 0.03  # 3% base dodge
	var rating_contribution := dodge_rating / 40.0  # ~40 rating = 1% dodge
	var agility_contribution: float = (agility - 10.0) * 0.0015
	var level_bonus := defender_level * 0.0005  # Small bonus per level
	return clampf(base_dodge + rating_contribution + agility_contribution + level_bonus, 0.0, 0.35)

## Calculate parry chance. Stat-derived from strength; halved without a
## shield (a two-hander parries less than a sword-and-board).
static func calculate_parry_chance(defender_level: int, parry_rating: float, has_shield: bool = false, strength: float = 10.0) -> float:
	var base_parry := 0.02  # 2% base parry
	var rating_contribution := parry_rating / 40.0
	var strength_contribution: float = (strength - 10.0) * 0.001
	var level_bonus := defender_level * 0.0005
	var chance: float = base_parry + rating_contribution + strength_contribution + level_bonus
	if not has_shield:
		chance *= 0.5  # Reduced without shield
	return clampf(chance, 0.0, 0.25)

## Calculate block chance. Shield-gated: without a shield there is no
## block at all. Vitality feeds the block rate once a shield is equipped.
static func calculate_block_chance(defender_level: int, block_rating: float, has_shield: bool = false, vitality: float = 10.0) -> float:
	if not has_shield:
		return 0.0

	var base_block := 0.05  # 5% base with shield
	var rating_contribution := block_rating / 45.0
	var vitality_contribution: float = (vitality - 10.0) * 0.002
	return clampf(base_block + rating_contribution + vitality_contribution, 0.0, 0.40)

## Calculate block value (damage reduction)
static func calculate_block_value(block_rating: float, strength: int) -> float:
	var base_block := 30.0  # Base block value
	var strength_contribution := strength * 0.5
	var rating_contribution := block_rating / 25.0
	return base_block + strength_contribution + rating_contribution

## Calculate full hit result -- the MWo-style single-roll combat table.
##
## ONE randf() in [0, 1) is split into cumulative segments, in order:
## MISS -> DODGE -> PARRY -> BLOCK -> CRIT -> HIT. Crit takes whatever
## the defensive segments leave, so a defender-heavy target eats into
## the attacker's crit rate instead of the table summing past 1. Misses
## are rolled first and can never crit (MWo rule).
##
## Duck-typed for both combatant families: bare Entity / Enemy nodes AND
## PlayerController (a CharacterBody3D with no combat_component). Every
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

	var attacker_level: int = int(attacker.get("level")) if "level" in attacker else 1
	var defender_level: int = int(defender.get("level")) if "level" in defender else 1

	# --- Segments -----------------------------------------------------
	var hit_chance := calculate_hit_chance(attacker_level, defender_level, attacker_ratings.hit_rating)
	result["hit_chance"] = hit_chance
	var miss_chance: float = maxf(0.0, 1.0 - hit_chance)

	var has_shield := _has_shield(defender)
	var dodge_chance := calculate_dodge_chance(
		defender_level, defender_ratings.dodge_rating, _stat(defender, "agility", 10.0))
	var parry_chance := calculate_parry_chance(
		defender_level, defender_ratings.parry_rating, has_shield,
		_stat(defender, "strength", 10.0))
	var block_chance := calculate_block_chance(
		defender_level, defender_ratings.block_rating, has_shield,
		_stat(defender, "vitality", 10.0))

	var crit_chance := _crit_chance_for(attacker)
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
			defender_ratings.block_rating, int(_stat(defender, "strength", 10.0))))
		return result

	cursor += crit_chance
	if roll < cursor:
		result["is_crit"] = true
		result["damage_multiplier"] = _crit_multiplier_for(attacker)
		return result

	# Remaining roll width is the plain-hit segment.
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

## Calculate magic hit
static func calculate_magic_hit(attacker, defender, spell_school: String = "arcane") -> Dictionary:
	var result := {
		"hit_result": HitResult.HIT,
		"hit_chance": 0.96,  # Base spell hit is higher
		"is_crit": false,
		"damage_multiplier": 1.0,
		"resist_percent": 0.0,
		"damage": 0,
		"attacker": attacker,
		"defender": defender
	}

	var defender_level: int = int(defender.get("level")) if "level" in defender else 1

	# Spell hit chance (higher than melee)
	var hit_chance: float = 0.96 + (_stat(attacker, "intelligence", 10.0) / 1000.0)
	result["hit_chance"] = clampf(hit_chance, 0.0, 1.0)

	# Check hit
	if randf() > hit_chance:
		result["hit_result"] = HitResult.MISS
		return result

	# Spell crit
	var crit_chance := (_stat(attacker, "intelligence", 10.0) / 200.0)  # ~0.5% per int
	if randf() < crit_chance:
		result["is_crit"] = true
		result["damage_multiplier"] = 1.5

	# Resistance
	var resistance: float = 0.0
	if "stats" in defender and defender.stats is Dictionary:
		resistance = float(defender.stats.get("%s_resistance" % spell_school, 0.0))
	resistance = clampf(resistance, 0.0, 0.75)  # Cap at 75% resist

	if randf() < resistance:
		result["hit_result"] = HitResult.RESIST
		result["resist_percent"] = resistance
		return result

	# Check for full immunity
	if resistance >= 1.0:
		result["hit_result"] = HitResult.IMMUNE
		return result

	result["resist_percent"] = resistance * randf_range(0.25, 1.0)  # Partial resist

	return result

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

	# Apply resist
	if outcome == HitResult.RESIST:
		damage *= (1.0 - float(hit_result.get("resist_percent", 0.0)))

	# Apply block reduction (blocks still deal partial damage)
	if outcome == HitResult.BLOCK:
		damage = maxf(1.0, damage - float(hit_result.get("blocked_damage", 0)))

	return maxi(1, int(damage))

## Crit chance off the combatant's own roll when it has one (Entity /
## PlayerController get_crit_chance), stat-derived otherwise.
static func _crit_chance_for(attacker) -> float:
	if attacker != null and attacker.has_method("get_crit_chance"):
		return float(attacker.get_crit_chance())
	return 0.05 + _stat(attacker, "agility", 10.0) * 0.003

static func _crit_multiplier_for(attacker) -> float:
	if attacker != null and attacker.has_method("get_crit_multiplier"):
		return float(attacker.get_crit_multiplier())
	return 1.5

## Helper to check if defender has shield equipped. Duck-typed: only
## PlayerController carries an inventory_component; bare Entity / Enemy
## simply have no off-hand, hence no block.
static func _has_shield(entity) -> bool:
	if entity == null or not ("inventory_component" in entity):
		return false
	var inv = entity.inventory_component
	if inv == null or not inv.has_method("get_equipped"):
		return false
	var offhand = inv.get_equipped(Item.EquipSlot.OFF_HAND)
	return offhand != null

## Get rating for level (for scaling)
static func get_rating_per_percent(level: int, stat_type: String) -> float:
	# Base ratings at level 60
	var base_ratings: Dictionary = {
		"hit": 40.0,
		"crit": 45.0,
		"haste": 32.0,
		"mastery": 50.0,
		"versatility": 40.0,
		"dodge": 40.0,
		"parry": 40.0,
		"block": 45.0
	}

	var base: float = base_ratings.get(stat_type, 40.0)
	# Scale with level (roughly linear)
	var scale_factor := level / 60.0
	return base * scale_factor
