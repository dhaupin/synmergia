## Species - Character race/species definition
## Defines species-specific stat modifiers and relationships
extends Resource
class_name Species

@export var id: String = ""
@export var display_name: String = "Unknown"
@export var description: String = ""

# Visual
@export var model_path: String = ""
@export var icon_path: String = ""
@export var default_skin_color: Color = Color.WHITE

# Base stat modifiers (compared to base 10)
@export var stat_modifiers: Dictionary = {
	"strength": 0,
	"agility": 0,
	"intelligence": 0,
	"vitality": 0,
	"endurance": 0,
	"wisdom": 0
}

# Starting location
@export var home_zone: String = "zone_starter_plains"
@export var home_faction: String = ""

# Species relationships
@export var allied_species: Array[String] = []  # Can party, trade, can't fight in PvP
@export var hostile_species: Array[String] = []  # Can fight in PvP zones

# Base health/mana modifiers (multiplier, 1.0 = normal)
@export var health_modifier: float = 1.0
@export var mana_modifier: float = 1.0
@export var stamina_modifier: float = 1.0

# Movement speed modifier
@export var speed_modifier: float = 1.0

# Controller type (for fairness system - agents/humans are equals)
@export var is_agent_controlled: bool = false  # Can be AI-controlled
@export var is_human_controlled: bool = true   # Can be human-controlled

# Visual customization options
@export var available_skin_tones: Array[Color] = []
@export var available_hair_colors: Array[Color] = []
@export var available_eye_colors: Array[Color] = []

func _init() -> void:
	if id == "":
		id = display_name.to_lower().replace(" ", "_")

## Get stat modifier for a given stat
func get_stat_modifier(stat: String) -> int:
	return stat_modifiers.get(stat, 0)

## Calculate actual stat from base + species modifier
func calculate_stat(base_stat: int, stat: String) -> int:
	return base_stat + get_stat_modifier(stat)

## Check if this species is allied with another
func is_allied_with(other_species_id: String) -> bool:
	return allied_species.has(other_species_id)

## Check if this species is hostile to another
func is_hostile_to(other_species_id: String) -> bool:
	return hostile_species.has(other_species_id)

## Get display info for UI
func get_info() -> Dictionary:
	return {
		"id": id,
		"name": display_name,
		"description": description,
		"stat_modifiers": stat_modifiers,
		"home_zone": home_zone,
		"allied_species": allied_species,
		"hostile_species": hostile_species
	}
