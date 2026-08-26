## StatusEffectData - Status effect template definition
## Defines reusable status effects for skills and items
class_name StatusEffectData
extends Resource

## Effect Categories
enum EffectCategory {
	BUFF,           # Positive effect
	DEBUFF,         # Negative effect
	NEUTRAL         # Neither
}

## Effect Types
enum EffectType {
	STAT_MODIFIER,      # Modifies stats (speed, damage, etc.)
	HEALTH_MODIFIER,    # Healing or damage over time
	IMMUNITY,           # Grants immunity
	STEALTH,            # Invisibility/stealth
	CONTROL,            # Stun, root, fear, etc.
	SPECIAL             # Custom effects
}

## Control Types (for crowd control effects)
enum ControlType {
	NONE,
	STUN,           # Cannot move or act
	ROOT,           # Cannot move
	SNARE,          # Slowed movement
	FEAR,           # Run away
	SILENCE,        # Cannot cast
	KNOCKBACK,      # Pushed away
	INCAPACITATE,   # Disabled (sleep, charm, etc.)
}

## Stat modification types
enum StatType {
	STRENGTH,
	AGILITY,
	INTELLIGENCE,
	VITALITY,
	ENDURANCE,
	WISDOM,
	MAX_HEALTH,
	MAX_MANA,
	MAX_STAMINA,
	HEALTH_REGEN,
	MANA_REGEN,
	STAMINA_REGEN,
	ARMOR,
	RESISTANCE,
	ATTACK_POWER,
	SPELL_POWER,
	CRIT_CHANCE,
	CRIT_MULTIPLIER,
	HASTE,
	MOVEMENT_SPEED,
	ALL_STATS,
}

## Stealth types
enum StealthType {
	NONE,
	INVISIBLE,      # Cannot be seen
	STEALTH,        # Hard to target
	VANISH,         # Complete removal from aggro
}

@export var id: String = ""
@export var display_name: String = "Effect"
@export var description: String = ""

# Classification
@export var category: EffectCategory = EffectCategory.BUFF
@export var effect_type: EffectType = EffectType.STAT_MODIFIER
@export var control_type: ControlType = ControlType.NONE

# Duration & Stacking
@export var duration: float = 0.0          # 0 = instant/permanent
@export var max_stacks: int = 1            # 1 = no stacking
@export var stack_behavior: String = "replace"  # replace, add, refresh
@export var can_refresh: bool = true       # Can refresh duration

# Stat Modifiers (for STAT_MODIFIER type)
@export var stat_modifiers: Dictionary = {}  # StatType -> value (int or float)
@export var stat_multipliers: Dictionary = {} # StatType -> multiplier (float)
@export var speed_type: String = ""         # slow, haste, root, snare (if effect_type == CONTROL)
@export var speed_percent: float = 0.0      # -50 = 50% slower, +30 = 30% faster
@export var flat_speed_change: float = 0.0  # Flat movement speed change

# Health Modifiers (for HEALTH_MODIFIER type)
@export var heal_amount: int = 0            # Instant heal
@export var heal_per_tick: int = 0           # HoT amount
@export var damage_per_tick: int = 0         # DoT amount
@export var tick_interval: float = 1.0       # Seconds between ticks
@export var dot_type: String = "physical"    # physical, magical, true
@export var can_cleanse: bool = true         # Can be removed by cleanse

# Immunity Settings (for IMMUNITY type)
@export var immune_stun: bool = false
@export var immune_slow: bool = false
@export var immune_silence: bool = false
@export var immune_fear: bool = false
@export var immune_root: bool = false
@export var immune_knockback: bool = false
@export var immune_dot: bool = false
@export var immune_interrupt: bool = false
@export var immune_all: bool = false         # Complete immunity

# Stealth Settings (for STEALTH type)
@export var stealth_type: StealthType = StealthType.NONE
@export var break_on_damage: bool = true
@export var break_on_action: bool = false
@export var detection_radius: float = 5.0

# Visual/Audio
@export var icon_path: String = ""
@export var particle_effect: String = ""
@export var sound_effect: String = ""

# Behavior
@export var show_in_buff_bar: bool = true
@export var can_stack_with_same: bool = false  # Multiple instances allowed
@export var priority: int = 0                   # Higher = applied later (for same-type effects)

# Combat integration
@export var trigger_gcd: bool = false           # Triggers global cooldown
@export var school: String = "physical"         # Magic school (for dispel categorization)

func _init() -> void:
	if id == "":
		id = display_name.to_lower().replace(" ", "_")

## Get stat modifier value for a stat
func get_stat_modifier(stat: String) -> float:
	return stat_modifiers.get(stat, 0.0)

## Get stat multiplier for a stat
func get_stat_multiplier(stat: String) -> float:
	return stat_multipliers.get(stat, 1.0)

## Check if this effect modifies a specific stat
func modifies_stat(stat: String) -> bool:
	return stat in stat_modifiers or stat in stat_multipliers

## Check if grants immunity to an effect type
func grants_immunity_to(effect_name: String) -> bool:
	if immune_all:
		return true
	match effect_name.to_lower():
		"stun": return immune_stun
		"slow": return immune_slow
		"silence": return immune_silence
		"fear": return immune_fear
		"root": return immune_root
		"knockback": return immune_knockback
		"dot", "damage_over_time": return immune_dot
		"interrupt": return immune_interrupt
	return false

## Get categorized immunities as list
func get_immunity_list() -> Array[String]:
	var immunities: Array[String] = []
	if immune_all:
		return ["all"]
	if immune_stun: immunities.append("stun")
	if immune_slow: immunities.append("slow")
	if immune_silence: immunities.append("silence")
	if immune_fear: immunities.append("fear")
	if immune_root: immunities.append("root")
	if immune_knockback: immunities.append("knockback")
	if immune_dot: immunities.append("dot")
	if immune_interrupt: immunities.append("interrupt")
	return immunities
