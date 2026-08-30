## CharacterData - Runtime player character definition
## Created at character selection, used to instantiate the player entity
class_name CharacterData
extends Resource

@export var character_id: String = ""
@export var display_name: String = "Hero"
@export var species_id: String = "human"
@export var class_id: String = "warrior"
@export var level: int = 1
@export var zone_id: String = "zone_starter_plains"
@export var spawn_position: Vector3 = Vector3(0, 1, 0)

# Skill Academy
@export var spent_skill_points: int = 0         # total points consumed on upgrades
@export var skill_upgrades: Dictionary = {}    # { skill_id: upgrade_level (0-5) }
@export var active_signature: String = ""        # selected signature skill ID (non-upgradable)
@export var signature_switches: int = 0         # number of times signature has been changed
@export var signature_change_cost: int = 1000   # gold cost to change signature (after first free switch)

var species_data: Species
var class_data: CharacterClass

func _init(p_species: String = "human", p_class: String = "warrior", p_name: String = "Hero") -> void:
	species_id = p_species
	class_id = p_class
	display_name = p_name
	character_id = str(Time.get_unix_time_from_system()) + "_" + species_id

static func load_species(species_id: String) -> Species:
	var path := "res://data/species/species_%s.tres" % species_id
	var res := load(path)
	return res if res is Species else null

static func load_class(class_id: String) -> CharacterClass:
	var path := "res://data/classes/class_%s.tres" % class_id
	var res := load(path)
	return res if res is CharacterClass else null

## Check if a class is GM-only (role = 0)
static func is_gm_class(cls_or_role) -> bool:
	if cls_or_role is CharacterClass:
		return cls_or_role.role == CharacterClass.Role.GM
	return cls_or_role == CharacterClass.Role.GM

## Check if this character data is a GM character
func is_gm() -> bool:
	return is_gm_class(class_id)

## Get available classes for a species.
## FILTERS OUT GM classes by default for security.
## For admin use, get_all_classes_for_species() includes GM classes.
static func get_available_classes_for_species(species_id: String) -> Array[CharacterClass]:
	var result: Array[CharacterClass] = []
	var dir := DirAccess.open("res://data/classes/")
	if dir:
		dir.list_dir_begin()
		var file := dir.get_next()
		while file != "":
			if file.ends_with(".tres"):
				var res := load("res://data/classes/" + file)
				if res is CharacterClass and not is_gm_class(res):
					result.append(res)
			file = dir.get_next()
	return result

## Get ALL classes for a species (including GM classes).
## ONLY for server-side use when sending class list to admin clients.
static func get_all_classes_for_species(species_id: String) -> Array[CharacterClass]:
	var result: Array[CharacterClass] = []
	var dir := DirAccess.open("res://data/classes/")
	if dir:
		dir.list_dir_begin()
		var file := dir.get_next()
		while file != "":
			if file.ends_with(".tres"):
				var res := load("res://data/classes/" + file)
				if res is CharacterClass:
					result.append(res)
			file = dir.get_next()
	return result

## Server-side validation: Can this account play this class?
## Returns {allowed: bool, reason: String}
## Call this when a player clicks "Play" to validate class selection.
static func play_accepted(class_id: String, account_level: int) -> Dictionary:
	var cls := load_class(class_id)
	if cls == null:
		return {"allowed": false, "reason": "Class not found"}
	
	# GM classes require admin level
	if is_gm_class(cls) and account_level < GameConfig.Security.ADMIN_LEVEL:
		return {"allowed": false, "reason": "GM class requires admin privileges"}
	
	return {"allowed": true, "reason": ""}

static func get_all_species() -> Array[Species]:
	var result: Array[Species] = []
	var dir := DirAccess.open("res://data/species/")
	if dir:
		dir.list_dir_begin()
		var file := dir.get_next()
		while file != "":
			if file.ends_with(".tres"):
				var res := load("res://data/species/" + file)
				if res is Species:
					result.append(res)
			file = dir.get_next()
	return result

func get_stats() -> Dictionary:
	if not class_data:
		class_data = load_class(class_id)
	if not class_data:
		return {}
	var stats := class_data.base_stats.duplicate()
	if species_data:
		for key in stats:
			stats[key] = species_data.calculate_stat(stats[key], key)
	return stats

func get_resource_type_name() -> String:
	if not class_data:
		class_data = load_class(class_id)
	if class_data:
		return CharacterClass.ResourceType.keys()[class_data.resource_type]
	return "MANA"

## Skill Academy helpers

## Total skill points earned based on current level (floor(level * 2.5))
func get_earned_skill_points() -> int:
	return int(30 + level * 2)

## Available (unspent) skill points
func get_available_skill_points() -> int:
	return get_earned_skill_points() - spent_skill_points

## Get upgrade level for a skill (0 if not upgraded)
func get_skill_upgrade_level(skill_id: String) -> int:
	return skill_upgrades.get(skill_id, 0)

## Total upgrade levels across all skills
func get_total_upgrade_levels() -> int:
	var total := 0
	for v in skill_upgrades.values():
		total += v as int
	return total

## Signature helpers

## Get the cost to change signature (free on first switch)
func get_signature_change_cost() -> int:
	if signature_switches == 0:
		return 0  # First switch is free
	return signature_change_cost

## Check if signature has been set
func has_signature() -> bool:
	return active_signature != ""

## Check if signature can be changed (must be level 10+)
func can_change_signature(player_level: int) -> bool:
	return player_level >= 10
