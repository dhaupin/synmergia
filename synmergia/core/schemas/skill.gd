## SkillSchema - Combat skill definition
## Base schema for all skills (spells, attacks, abilities)
## The runtime Skill class lives in core/combat/skill.gd
class_name SkillSchema
extends Resource

enum SkillType {
	MELEE,
	RANGED,
	INSTANT,
	GROUND_TARGETED,
	TARGETED_AOE,
	SELF,
	CHANNEL,
	PROJECTILE_AOE,
	REVIVE  # Resurrect a dead ally
}

enum TargetType {
	SINGLE_ENEMY,
	MULTIPLE_ENEMY,
	SELF,
	ALLY,
	DEAD_ALLY,  # Target dead allies for revive
	GROUND,
	TARGETED_AOE
}

@export var id: String = ""
@export var display_name: String = "Skill"
@export var description: String = ""
@export var icon_path: String = ""

# Classification
@export var skill_type: SkillType = SkillType.MELEE
@export var target_type: TargetType = TargetType.SINGLE_ENEMY

# Costs
@export var mana_cost: int = 0
@export var stamina_cost: float = 0.0
@export var health_cost: int = 0
@export var cooldown: float = 0.0

# Timing
@export var cast_time: float = 0.0  # 0 = instant
@export var animation_duration: float = 0.4
@export var recovery_time: float = 0.0
@export var can_interrupt: bool = true  # Can be interrupted by damage
@export var uses_gcd: bool = true       # Triggers global cooldown

# Targeting
@export var range: float = 2.5
@export var aoe_radius: float = 0.0
@export var targeted_aoe_radius: float = 0.0
@export var max_targets: int = 0  # 0 = unlimited

# Effects (array of EffectData dictionaries)
@export var effects: Array[Dictionary] = []

# Requirements
@export var required_level: int = 1
@export var required_class: String = ""  # Empty = all classes
@export var required_stance: String = ""

# Visual/Audio
@export var vfx_cast: String = ""
@export var vfx_impact: String = ""
@export var sfx_cast: String = ""
@export var sfx_impact: String = ""

# Skill Academy — skill book upgrades
# Signature/ultimate skills should set upgradable = false in their .tres.
# Skill Academy — skill book upgrades
# Signature/ultimate skills should set upgradable = false in their .tres.
@export var upgradable: bool = true

## Charge system — set charge_time_max > 0 to enable charging.
## charge_damage_curve: "linear" | "stepped" | "exponential"
## Skills without charge_time_max are instant or have fixed cast_time.
@export var charge_time_max: float = 0.0
@export var charge_damage_curve: String = "linear"

## Delta fields per upgrade tier (cumulative):
##   damage_mult      — direct damage multiplier
##   heal_mult        — heal amount multiplier
##   range_mult       — targeting/cast range
##   radius_mult      — AOE radius
##   cooldown_mult    — lower = faster (multiplicative with gear CDR)
##   cast_time_mult   — longer cast at higher tiers (higher = slower)
##   duration_mult    — buff/DoT/HoT duration
##   dot_mult         — damage-over-time tick multiplier
##   hot_mult         — heal-over-time tick multiplier
##   cost_mult        — mana/stamina cost multiplier (lower = cheaper)
##   charge_mult      — max charge time multiplier (higher = longer charge window)
##   max_targets_mult — additional targets at higher tiers
##   unlocks[]        — mechanics unlocked at this tier
##     { "type": "aoe", "radius": float }
##     { "type": "knockback", "force": float }
##     { "type": "shield", "amount_mult": float }
##     { "type": "dot", "ticks": int, "damage_mult": float }
##     { "type": "hot", "ticks": int, "heal_mult": float }
##     { "type": "chain", "max_targets": int, "damage_mult": float }
##     { "type": "armor_pierce", "percent": float }
## Stat thresholds for upgrade tiers (30-point intervals)
## min_stat: which stat is required (e.g., "intelligence", "strength")
## min_stat_value: minimum stat value needed (30=common, 60=rare, 90=epic, 120=legendary, 150=mythic)
const STAT_TIER_THRESHOLDS: Dictionary = {
	"common": {"min_stat_value": 30},
	"rare": {"min_stat_value": 60},
	"epic": {"min_stat_value": 90},
	"legendary": {"min_stat_value": 120},
	"mythic": {"min_stat_value": 150}
}

@export var upgrade_tiers: Array[Dictionary] = [
	{"level": 1, "books_required": 4, "tier": "common", "min_stat": "", "min_stat_value": 30,
		"delta": {
			"damage_mult": 1.12, "heal_mult": 1.12, "range_mult": 1.05,
			"cooldown_mult": 0.95, "cast_time_mult": 1.05, "aoe_mult": 1.03,
			"duration_mult": 1.05, "dot_mult": 1.12, "hot_mult": 1.12,
			"cost_mult": 0.97, "charge_mult": 1.05, "max_targets_mult": 1.0
		},
		"unlocks": []},
	{"level": 2, "books_required": 4, "tier": "rare", "min_stat": "", "min_stat_value": 60,
		"delta": {
			"damage_mult": 1.24, "heal_mult": 1.24, "range_mult": 1.10,
			"cooldown_mult": 0.90, "cast_time_mult": 1.10, "aoe_mult": 1.06,
			"duration_mult": 1.10, "dot_mult": 1.24, "hot_mult": 1.24,
			"cost_mult": 0.94, "charge_mult": 1.10, "max_targets_mult": 1.0
		},
		"unlocks": []},
	{"level": 3, "books_required": 4, "tier": "epic", "min_stat": "", "min_stat_value": 90,
		"delta": {
			"damage_mult": 1.36, "heal_mult": 1.36, "range_mult": 1.15,
			"cooldown_mult": 0.85, "cast_time_mult": 1.15, "aoe_mult": 1.09,
			"duration_mult": 1.15, "dot_mult": 1.36, "hot_mult": 1.36,
			"cost_mult": 0.91, "charge_mult": 1.15, "max_targets_mult": 1.0
		},
		"unlocks": []},
	{"level": 4, "books_required": 4, "tier": "legendary", "min_stat": "", "min_stat_value": 120,
		"delta": {
			"damage_mult": 1.48, "heal_mult": 1.48, "range_mult": 1.20,
			"cooldown_mult": 0.80, "cast_time_mult": 1.20, "aoe_mult": 1.12,
			"duration_mult": 1.20, "dot_mult": 1.48, "hot_mult": 1.48,
			"cost_mult": 0.88, "charge_mult": 1.20, "max_targets_mult": 1.0
		},
		"unlocks": []},
	{"level": 5, "books_required": 4, "tier": "mythic", "min_stat": "", "min_stat_value": 150,
		"delta": {
			"damage_mult": 1.60, "heal_mult": 1.60, "range_mult": 1.25,
			"cooldown_mult": 0.75, "cast_time_mult": 1.25, "aoe_mult": 1.15,
			"duration_mult": 1.25, "dot_mult": 1.60, "hot_mult": 1.60,
			"cost_mult": 0.85, "charge_mult": 1.25, "max_targets_mult": 1.0
		},
		"unlocks": []}
]

var remaining_cooldown: float = 0.0

func _init() -> void:
	if id == "":
		id = display_name.to_lower().replace(" ", "_")

## Check if entity can cast this skill
func can_cast(caster: Node) -> bool:
	if remaining_cooldown > 0:
		return false
	if mana_cost > 0 and "current_mana" in caster and caster.current_mana < mana_cost:
		return false
	if stamina_cost > 0 and "current_stamina" in caster and caster.current_stamina < stamina_cost:
		return false
	if health_cost > 0 and "current_health" in caster and caster.current_health < health_cost:
		return false
	if "level" in caster and caster.level < required_level:
		return false
	return true

## Execute the skill
func execute(caster, target= null, ground_pos: Vector3 = Vector3.ZERO) -> Dictionary:
	var result := {
		"success": false,
		"damage_dealt": 0,
		"effects_applied": [],
		"targets_hit": []
	}
	
	if not can_cast(caster):
		return result
	
	# Consume resources
	_consume_resources(caster)
	
	# Start cooldown
	remaining_cooldown = cooldown
	
	# Apply effects
	_apply_effects(caster, target, ground_pos, result)
	
	result["success"] = true
	return result

func _consume_resources(caster: ) -> void:
	caster.current_mana -= mana_cost
	caster.current_stamina -= stamina_cost
	caster.current_health -= health_cost

func _apply_effects(caster, target, ground_pos: Vector3, result: Dictionary) -> void:
	for effect in effects:
		match effect.get("type", ""):
			"damage":
				var dmg: int = int(effect.get("value", 0))
				if target:
					target.take_damage(dmg, caster)
					result["targets_hit"].append(target)
					result["damage_dealt"] += dmg
			"heal":
				var amount: int = int(effect.get("value", 0))
				if caster:
					caster.heal(amount)
			"revive":
				# Handle revive effect
				var success: bool = _apply_revive(caster, target, effect, result)
				if success:
					result["targets_hit"].append(target)
			"buff":
				# Apply buff from effect data
				pass
			"debuff":
				# Apply debuff to target
				pass

## Apply revive effect
func _apply_revive(caster, target, effect: Dictionary, result: Dictionary) -> bool:
	if not target or not caster:
		return false
	
	# Check if target is actually dead
	if not target.health_component or not target.health_component.is_dead():
		result["failure_reason"] = "Target is not dead"
		return false
	
	# Check range if specified
	if range > 0:
		var distance: float = caster.global_position.distance_to(target.global_position)
		if distance > range:
			result["failure_reason"] = "Target out of range"
			return false
	
	# Use RespawnService to perform the revive
	var context: String = effect.get("context", "open_world")
	if RespawnService:
		# Start the revival process
		var success: bool = RespawnService.start_revival(caster, target, context)
		if success:
			result["revive_started"] = true
			return true
		else:
			result["failure_reason"] = "Revive failed (abuse detection or restrictions)"
			return false
	
	# Fallback if no RespawnService
	result["failure_reason"] = "Revive system not available"
	return false

func _physics_process(delta: float) -> void:
	if remaining_cooldown > 0:
		remaining_cooldown = max(0, remaining_cooldown - delta)

func get_cooldown_remaining() -> float:
	return remaining_cooldown

## Find dead allies within range (for revive skills)
static func find_dead_allies(caster, max_range: float) -> Array:
	var dead_allies: Array = []
	
	if not caster or not caster.health_component:
		return dead_allies
	
	var caster_pos: Vector3 = caster.global_position
	
	# Get all entities in range from EntityService
	var nearby_entities := []
	
	for entity in nearby_entities:
		# Skip self
		if entity == caster:
			continue
		
		# Check if it's a dead ally (same team/faction, dead)
		if entity.health_component and entity.health_component.is_dead():
			# Check if ally (same team or friendly)
			if _is_ally(caster, entity):
				dead_allies.append(entity)
	
	return dead_allies

## Check if two entities are allies
static func _is_ally(entity_a, entity_b) -> bool:
	# Same entity
	if entity_a == entity_b:
		return true
	
	# Check party
	if entity_a.has("party_id") and entity_b.has("party_id"):
		if entity_a.party_id != "" and entity_a.party_id == entity_b.party_id:
			return true
	
	# Check guild
	if entity_a.has("guild_id") and entity_b.has("guild_id"):
		if entity_a.guild_id != "" and entity_a.guild_id == entity_b.guild_id:
			return true
	
	# Check faction (friendly)
	if entity_a.has("faction_id") and entity_b.has("faction_id"):
		if entity_a.faction_id == entity_b.faction_id:
			return true
	
	# Check team (for PvP)
	if entity_a.has("team_id") and entity_b.has("team_id"):
		if entity_a.team_id == entity_b.team_id:
			return true
	
	return false

func get_info() -> Dictionary:
	return {
		"id": id,
		"name": display_name,
		"type": SkillType.keys()[skill_type],
		"mana_cost": mana_cost,
		"cooldown": cooldown,
		"range": range
	}

## Get the upgrade tier definition for upgrade level 1-5.
func get_upgrade_tier(level: int) -> Dictionary:
	for tier in upgrade_tiers:
		if tier.get("level") == level:
			return tier
	return {}

## Get cumulative deltas for upgrade levels 1 through upgrade_level.
## Apply these multipliers to the base skill attributes.
f
## Get unlock entries that are active at upgrade_level.
## Returns an array of unlock dictionaries (empty if not upgradable or no unlocks at this level).
func get_unlocks_at_level(upgrade_level: int) -> Array:
	if upgrade_level <= 0 or not upgradable:
		return []
	var result: Array = []
	for tier in upgrade_tiers:
		if tier.get("level") <= upgrade_level:
			var unlocks: Array = tier.get("unlocks", [])
			for unlock in unlocks:
				result.append(unlock)
	return result

## Get the tier name (common/rare/epic/legendary/mythic) for a given upgrade level.
func get_tier_name(upgrade_level: int) -> String:
	for tier in upgrade_tiers:
		if tier.get("level") == upgrade_level:
			return tier.get("tier", "common")
	return "common"

func get_upgrade_deltas(upgrade_level: int) -> Dictionary:
	var total := {
		"damage_mult": 1.0, "heal_mult": 1.0, "range_mult": 1.0,
		"cooldown_mult": 1.0, "cast_time_mult": 1.0, "aoe_mult": 1.0,
		"duration_mult": 1.0, "dot_mult": 1.0, "hot_mult": 1.0,
		"cost_mult": 1.0, "charge_mult": 1.0, "max_targets_mult": 1.0,
		"chain_count": 0, "projectile_count": 0,
		"effect_strength_mult": 1.0, "effect_duration_mult": 1.0
	}
	for tier in upgrade_tiers:
		if tier.get("level") <= upgrade_level:
			var d: Dictionary = tier.get("delta", {})
			for key in d:
				if key in ["chain_count", "projectile_count"]:
					total[key] += int(d[key])  # additive for counts
				else:
					total[key] *= d[key]       # multiplicative for multipliers
	return total

## ============================================================================
## STAT THRESHOLD METHODS
## ============================================================================

## Get the stat required for a given upgrade level
func get_required_stat_for_tier(upgrade_level: int) -> Dictionary:
	if upgrade_level <= 0:
		return {"stat": "", "value": 0}
	for tier in upgrade_tiers:
		if tier.get("level") == upgrade_level:
			return {
				"stat": tier.get("min_stat", ""),
				"value": tier.get("min_stat_value", 0)
			}
	return {"stat": "", "value": 0}

## Check if player stat meets the requirement for an upgrade tier
func check_stat_requirement(player_stat_value: int, upgrade_level: int) -> Dictionary:
	var required := get_required_stat_for_tier(upgrade_level)
	var stat_name := required.get("stat", "")
	var required_value := required.get("value", 0)
	
	# No stat required for this tier
	if stat_name == "" or required_value == 0:
		return {"meets_requirement": true, "stat": "", "required": 0, "current": player_stat_value}
	
	var meets := player_stat_value >= required_value
	return {
		"meets_requirement": meets,
		"stat": stat_name,
		"required": required_value,
		"current": player_stat_value
	}

## Get the max upgrade tier achievable with current stat value
func get_max_upgrade_tier_for_stat(stat_name: String, stat_value: int) -> int:
	var max_tier := 0
	for tier in upgrade_tiers:
		var tier_stat: String = tier.get("min_stat", "")
		var tier_value: int = tier.get("min_stat_value", 0)
		if tier_stat == stat_name and stat_value >= tier_value:
			max_tier = tier.get("level", 0)
	return max_tier

## Check all skills and return which would be downgraded
func get_skills_affected_by_stat_reduction(stats: Dictionary) -> Array[Dictionary]:
	var affected := []
	for stat_name in stats.keys():
		var current_value: int = stats[stat_name]
		# Check if any upgrade tier requires this stat
		for tier in upgrade_tiers:
			var tier_stat: String = tier.get("min_stat", "")
			var tier_value: int = tier.get("min_stat_value", 0)
			if tier_stat == stat_name and tier_value > current_value:
				affected.append({
					"tier": tier.get("tier", ""),
					"level": tier.get("level", 0),
					"required_stat": stat_name,
					"required_value": tier_value,
					"current_value": current_value
				})
	return affected
