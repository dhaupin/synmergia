## CombatMath - Hit calculation for combat
## Handles hit chance, miss, evade, block, parry, crush
class_name CombatMath
extends Node
const Skill = preload("res://core/combat/skill.gd")


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

## Get combat ratings from entity
static func get_entity_ratings(entity) -> CombatRatings:
	var ratings := CombatRatings.new()
	if entity == null:
		return ratings
	
	# Check for ratings in entity stats
	if entity.stats.has("crit_rating"):
		ratings.crit_rating = entity.stats.get("crit_rating", 0.0)
	if entity.stats.has("hit_rating"):
		ratings.hit_rating = entity.stats.get("hit_rating", 0.0)
	
	return ratings

## Calculate hit chance
static func calculate_hit_chance(attacker_level: int, defender_level: int, hit_rating: float = 0.0) -> float:
	var base_hit := 0.95  # 95% base hit
	
	# Level penalty (bosses have higher miss chance)
	var level_diff := defender_level - attacker_level
	var level_penalty := clamp(level_diff * 0.01, -0.30, 0.0)  # -30% to +0%
	
	# Rating contribution (each rating point gives small bonus)
	# At level 60, ~40 rating = 1% hit
	var rating_contribution := hit_rating / (attacker_level * 10.0)
	
	var final_hit := base_hit + level_penalty + rating_contribution
	return clamp(final_hit, 0.0, 1.0)

## Calculate crit chance
static func calculate_crit_chance(base_crit: float, crit_rating: float, target_crit_avoidance: float = 0.0) -> float:
	var rating_contribution := crit_rating / 45.0  # ~45 rating = 1% crit at level 60
	var final_crit := base_crit + rating_contribution - target_crit_avoidance
	return clamp(final_crit, 0.0, 1.0)

## Calculate dodge chance
static func calculate_dodge_chance(defender_level: int, dodge_rating: float) -> float:
	var base_dodge := 0.03  # 3% base dodge
	var rating_contribution := dodge_rating / 40.0  # ~40 rating = 1% dodge
	var level_bonus := defender_level * 0.0005  # Small bonus per level
	return clamp(base_dodge + rating_contribution + level_bonus, 0.0, 0.95)

## Calculate parry chance
static func calculate_parry_chance(defender_level: int, parry_rating: float, has_shield: bool = false) -> float:
	var base_parry := 0.03  # 3% base parry
	if not has_shield:
		base_parry *= 0.5  # Reduced without shield
	
	var rating_contribution := parry_rating / 40.0
	var level_bonus := defender_level * 0.0005
	return clamp(base_parry + rating_contribution + level_bonus, 0.0, 0.75)

## Calculate block chance
static func calculate_block_chance(defender_level: int, block_rating: float, has_shield: bool = false) -> float:
	if not has_shield:
		return 0.0
	
	var base_block := 0.05  # 5% base with shield
	var rating_contribution := block_rating / 45.0
	return clamp(base_block + rating_contribution, 0.0, 0.75)

## Calculate block value (damage reduction)
static func calculate_block_value(block_rating: float, strength: int) -> float:
	var base_block := 30.0  # Base block value
	var strength_contribution := strength * 0.5
	var rating_contribution := block_rating / 25.0
	return base_block + strength_contribution + rating_contribution

## Calculate full hit result
static func calculate_hit(attacker, defender, skill: Skill = null) -> Dictionary:
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
	
	# Get levels
	var attacker_level: int = attacker.level
	var defender_level: int = defender.level
	
	# Calculate hit chance
	var hit_chance := calculate_hit_chance(attacker_level, defender_level)
	result["hit_chance"] = hit_chance
	
	# Roll for hit
	var hit_roll := randf()
	if hit_roll > hit_chance:
		result["hit_result"] = HitResult.MISS
		return result
	
	# Roll for crit
	var attacker_ratings := get_entity_ratings(attacker)
	var crit_chance := calculate_crit_chance(
		attacker.combat_component.crit_chance if attacker.combat_component else 0.05,
		attacker_ratings.crit_rating
	)
	
	if randf() < crit_chance:
		result["is_crit"] = true
		result["damage_multiplier"] = attacker.combat_component.crit_multiplier if attacker.combat_component else 1.5
	
	# Check defender defenses (only if not a crit from behind)
	var defense_roll := randf()
	var dodge_chance := calculate_dodge_chance(defender_level, 0.0)
	var parry_chance := calculate_parry_chance(defender_level, 0.0, _has_shield(defender))
	var block_chance := calculate_block_chance(defender_level, 0.0, _has_shield(defender))
	
	# Dodge (checked first)
	if defense_roll < dodge_chance:
		result["hit_result"] = HitResult.EVADE
		return result
	
	defense_roll -= dodge_chance
	
	# Parry
	if defense_roll < parry_chance:
		result["hit_result"] = HitResult.PARRY
		# Parry might trigger counter-attack
		return result
	
	defense_roll -= parry_chance
	
	# Block (reduces damage but still hits)
	if defense_roll < block_chance:
		result["hit_result"] = HitResult.BLOCK
		result["blocked_damage"] = int(calculate_block_value(0.0, defender.stats.get("strength", 10)))
	
	# Check for crush (boss bonus vs low level)
	if defender_level >= attacker_level + 3:
		if randf() < 0.15:  # 15% crushing blow chance
			result["hit_result"] = HitResult.CRUSH
			result["damage_multiplier"] *= 1.5
	
	return result

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
	
	var defender_level: int = defender.level
	
	# Spell hit chance (higher than melee)
	var hit_chance := 0.96 + (attacker.stats.get("intelligence", 10) / 1000.0)
	result["hit_chance"] = clamp(hit_chance, 0.0, 1.0)
	
	# Check hit
	if randf() > hit_chance:
		result["hit_result"] = HitResult.MISS
		return result
	
	# Spell crit
	var crit_chance := (attacker.stats.get("intelligence", 10) / 200.0)  # ~0.5% per int
	if randf() < crit_chance:
		result["is_crit"] = true
		result["damage_multiplier"] = 1.5
	
	# Resistance
	var resistance := defender.stats.get("%s_resistance" % spell_school, 0.0)
	resistance = clamp(resistance, 0.0, 0.75)  # Cap at 75% resist
	
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

## Calculate damage with hit result
static func calculate_damage(base_damage: int, hit_result: Dictionary) -> int:
	var damage := float(base_damage)
	
	# Apply damage multiplier (crits)
	damage *= hit_result.get("damage_multiplier", 1.0)
	
	# Apply resist
	if hit_result["hit_result"] == HitResult.RESIST:
		damage *= (1.0 - hit_result["resist_percent"])
	
	# Apply block reduction (blocks still deal partial damage)
	if hit_result["hit_result"] == HitResult.BLOCK:
		damage = max(1.0, damage - hit_result.get("blocked_damage", 0))
	
	return max(1, int(damage))

## Helper to check if defender has shield equipped
static func _has_shield(entity) -> bool:
	if entity.inventory_component:
		var offhand := entity.inventory_component.get_equipped(Item.EquipSlot.OFF_HAND)
		if offhand and offhand.equip_slot == Item.EquipSlot.OFF_HAND:
			return true
	return false

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
	
	var base := base_ratings.get(stat_type, 40.0)
	# Scale with level (roughly linear)
	var scale_factor := level / 60.0
	return base * scale_factor
