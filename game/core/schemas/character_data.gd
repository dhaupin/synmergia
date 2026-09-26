## CharacterData - Runtime player character definition
## Created at character selection, used to instantiate the player entity
extends Resource
class_name CharacterData
const CharacterClass = preload("res://core/schemas/character_class.gd")
const Species = preload("res://core/schemas/species.gd")


@export var character_id: String = ""
@export var display_name: String = "Hero"
@export var species_id: String = "human"
@export var class_id: String = "human_warrior"
@export var level: int = 1
@export var zone_id: String = "zone_starter_plains"
@export var spawn_position: Vector3 = Vector3(0, 1, 0)

# Skill Academy
@export var spent_skill_points: int = 0         # total points consumed on upgrades
@export var skill_upgrades: Dictionary = {}    # { skill_id: upgrade_level (0-5) }
@export var active_signature: String = ""        # selected signature skill ID (non-upgradable)
@export var signature_switches: int = 0         # number of times signature has been changed
@export var signature_change_cost: int = 1000   # gold cost to change signature (after first free switch)

# Action Bar (8 slots)
@export var action_bar_slots: Array[String] = []  # skill IDs bound to slots 0-7

# Player Titles
@export var unlocked_titles: Array[String] = []  # unlocked title IDs
@export var equipped_prefix: String = ""         # currently equipped prefix title ID
@export var equipped_suffix: String = ""         # currently equipped suffix title ID

# Stat Allocation (player-assigned points)
@export var allocated_stats: Dictionary = {
	"strength": 0,
	"agility": 0,
	"intelligence": 0,
	"vitality": 0,
	"endurance": 0,
	"wisdom": 0
}
@export var total_stat_respecs: int = 0        # track respec usage

# Visual identity. Colors come from the species' available_*_colors
# lists (character creation validates against them); hairstyle/body
# are string ids the renderer resolves. Skins may add more keys via
# extra_appearance (beards, markings, prosthetics).
@export var skin_tone: Color = Color(0, 0, 0, 0)   # a=0 = species default
@export var hair_color: Color = Color(0, 0, 0, 0)  # a=0 = species default
@export var eye_color: Color = Color(0, 0, 0, 0)   # a=0 = species default
@export var hairstyle: String = ""                 # renderer hairstyle id
@export var body_type: String = ""                 # renderer body id
@export var extra_appearance: Dictionary = {}       # species-specific keys

var species_data: Species
var class_data: CharacterClass

func _init(p_species: String = "human", p_class: String = "human_warrior", p_name: String = "Hero") -> void:
	species_id = p_species
	class_id = p_class
	display_name = p_name
	character_id = str(Time.get_unix_time_from_system()) + "_" + species_id

## Script-mode-safe DataService resolution: a bare autoload identifier
## aborts --script-mode compilation (parse-time autoload edge), which
## took the whole CharacterData class down in test harnesses. Same
## pattern as is_gm_class below.
static func _data_service() -> Node:
	var ml := Engine.get_main_loop()
	if ml == null or not (ml is SceneTree):
		return null
	return (ml as SceneTree).root.get_node_or_null("DataService")

static func load_species(species_id: String) -> Species:
	var ds := _data_service()
	if ds != null:
		return ds.get_species(species_id) as Species
	var path := "res://data/species/species_%s.tres" % species_id
	var res := load(path)
	return res if res is Species else null

static func load_class(class_id: String) -> CharacterClass:
	var ds := _data_service()
	if ds != null:
		return ds.get_character_class(class_id) as CharacterClass
	var path := "res://data/classes/class_%s.tres" % class_id
	var res := load(path)
	return res if res is CharacterClass else null

## Check if a class is GM-only (role = 0)
## Accepts a CharacterClass, a class_id String, or a Role int. Callers
## used to pass class_id strings straight in and hit a String == int
## runtime error; resolve strings through DataService instead.
static func is_gm_class(cls_or_role) -> bool:
	if cls_or_role is CharacterClass:
		return cls_or_role.role == CharacterClass.Role.GM
	if cls_or_role is String:
		var ds = Engine.get_main_loop().root.get_node_or_null("DataService")
		if ds == null or not ds.has_method("get_character_class"):
			return false
		var cls = ds.get_character_class(cls_or_role)
		return cls != null and cls.role == CharacterClass.Role.GM
	if cls_or_role is int:
		return cls_or_role == CharacterClass.Role.GM
	return false

## Check if this character data is a GM character
func is_gm() -> bool:
	return is_gm_class(class_id)

## Get available classes for a species.
## FILTERS OUT GM classes by default for security.
## For admin use, get_all_classes_for_species() includes GM classes.
static func get_available_classes_for_species(species_id: String) -> Array[CharacterClass]:
	var result: Array[CharacterClass] = []
	var ds := _data_service()
	if ds != null:
		var all_classes: Array = ds.get_all_classes()
		for cls in all_classes:
			if cls is CharacterClass and not is_gm_class(cls):
				# Filter by species prefix: classes follow pattern {species}_{class}
				# e.g., human_warrior, akkan_bulwark, synthetic_warden
				if cls.id.begins_with(species_id + "_"):
					result.append(cls)
		return result
	
	# Fallback to filesystem if DataService not available
	var dir := DirAccess.open("res://data/classes/")
	if dir:
		dir.list_dir_begin()
		var file := dir.get_next()
		while file != "":
			if file.ends_with(".tres"):
				var res := load("res://data/classes/" + file)
				if res is CharacterClass and not is_gm_class(res):
					if res.id.begins_with(species_id + "_"):
						result.append(res)
			file = dir.get_next()
	return result

## Get ALL classes for a species (including GM classes).
## ONLY for server-side use when sending class list to admin clients.
static func get_all_classes_for_species(species_id: String) -> Array[CharacterClass]:
	var result: Array[CharacterClass] = []
	var ds := _data_service()
	if ds != null:
		var all_classes: Array = ds.get_all_classes()
		for cls in all_classes:
			if cls is CharacterClass:
				# Filter by species prefix
				if cls.id.begins_with(species_id + "_"):
					result.append(cls)
		return result
	
	# Fallback to filesystem if DataService not available
	var dir := DirAccess.open("res://data/classes/")
	if dir:
		dir.list_dir_begin()
		var file := dir.get_next()
		while file != "":
			if file.ends_with(".tres"):
				var res := load("res://data/classes/" + file)
				if res is CharacterClass:
					if res.id.begins_with(species_id + "_"):
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
	var ds := _data_service()
	if ds != null:
		var all_species: Array = ds.get_all_species()
		for sp in all_species:
			if sp is Species:
				result.append(sp)
		return result
	
	# Fallback to filesystem if DataService not available
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

## Set action bar slot to a skill ID
func set_action_slot(slot_index: int, skill_id: String) -> void:
	if slot_index < 0 or slot_index > 7:
		return
	while action_bar_slots.size() < 8:
		action_bar_slots.append("")
	action_bar_slots[slot_index] = skill_id

## Get skill ID at action bar slot
func get_action_slot(slot_index: int) -> String:
	if slot_index < 0 or slot_index > 7:
		return ""
	if slot_index >= action_bar_slots.size():
		return ""
	return action_bar_slots[slot_index]

## Get all action bar slots as array
func get_action_bar() -> Array[String]:
	var result: Array[String] = []
	for i in range(8):
		result.append(get_action_slot(i))
	return result

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

## Stat Allocation helpers

## Total stat points earned based on current level
func get_earned_stat_points() -> int:
	if not class_data:
		class_data = load_class(class_id)
	if class_data:
		return class_data.get_allocatable_points_for_level(level)
	return 0

## Available (unspent) stat points
func get_available_stat_points() -> int:
	return get_earned_stat_points() - get_total_allocated_points()

## Total points allocated across all stats
func get_total_allocated_points() -> int:
	var total := 0
	for v in allocated_stats.values():
		total += v as int
	return total

## Allocate a point to a stat (returns false if not enough points available)
func allocate_stat_point(stat_name: String) -> bool:
	if not allocated_stats.has(stat_name):
		return false
	if get_available_stat_points() <= 0:
		return false

	var cls := load_class(class_id)
	if cls:
		var current_total := get_stat_total(stat_name)
		if current_total >= cls.MAX_STAT_VALUE:
			return false  # Max stat cap reached

	allocated_stats[stat_name] += 1
	return true

## Remove a point from a stat (returns false if stat is at 0)
func deallocate_stat_point(stat_name: String) -> bool:
	if not allocated_stats.has(stat_name):
		return false
	if allocated_stats[stat_name] <= 0:
		return false
	allocated_stats[stat_name] -= 1
	return true

## Get allocated points for a specific stat
func get_allocated_points(stat_name: String) -> int:
	return allocated_stats.get(stat_name, 0)

## Get total stat value (base + allocated)
## Daily Class Blessing (prd-psy.md section 8): when THIS character's
## class is the sky-blessed one (and the tribe earned the day), stats
## compute as if level were +5 -- the "their level multiple goes like
## 5 lvls higher" beat. Late-resolves SignService via the main loop so
## --script-mode compilation never touches a bare autoload identifier.
func get_stat_total(stat_name: String) -> int:
	if not class_data:
		class_data = load_class(class_id)
	if not class_data:
		return 0

	var effective_level := level
	var ml := Engine.get_main_loop()
	if ml != null and (ml is SceneTree):
		var svc = (ml as SceneTree).root.get_node_or_null("SignService")
		if svc != null and svc.has_method("is_class_blessed") and svc.is_class_blessed(class_id):
			effective_level = level + int(svc.BLESSED_LEVEL_BONUS)

	var base := class_data.calculate_stat(stat_name, effective_level)
	var allocated := get_allocated_points(stat_name)
	return base + allocated

## Get all stats with allocated values
func get_all_stats_with_allocated() -> Dictionary:
	var result := {}
	for stat in allocated_stats.keys():
		result[stat] = get_stat_total(stat)
	return result

## Calculate derived stats (max health, mana, attack, defense)
## These are estimates based on class/species/level/allocated stats
func get_derived_stats() -> Dictionary:
	if not class_data:
		class_data = load_class(class_id)
	if not class_data:
		return {}
	
	var stats := get_all_stats_with_allocated()
	if stats.is_empty():
		return {}
	
	var vit: int = stats.get("vitality", 10)
	var end: int = stats.get("endurance", 10)
	var str: int = stats.get("strength", 10)
	var intel: int = stats.get("intelligence", 10)
	
	# Base formulas - can be overridden by class/species
	var max_health: int = int(100 + vit * 10)
	var max_mana: int = int(50 + intel * 5)
	var p_attack: int = int(10 + str * 2)
	var m_attack: int = int(10 + intel * 2)
	var p_defense: int = int(5 + end * 1.5)
	var m_defense: int = int(5 + intel * 1.5)
	
	# Apply class-specific modifiers if available
	if class_data.has_method("modify_derived_stats"):
		var modified: Dictionary = class_data.modify_derived_stats({
			"max_health": max_health,
			"max_mana": max_mana,
			"p_attack": p_attack,
			"m_attack": m_attack,
			"p_defense": p_defense,
			"m_defense": m_defense
		}, stats)
		if modified:
			max_health = modified.get("max_health", max_health)
			max_mana = modified.get("max_mana", max_mana)
			p_attack = modified.get("p_attack", p_attack)
			m_attack = modified.get("m_attack", m_attack)
			p_defense = modified.get("p_defense", p_defense)
			m_defense = modified.get("m_defense", m_defense)
	
	return {
		"max_health": max_health,
		"max_mana": max_mana,
		"p_attack": p_attack,
		"m_attack": m_attack,
		"p_defense": p_defense,
		"m_defense": m_defense
	}

## Serialize to a plain Dictionary for disk persistence.
## Server-authoritative fields (level, zone, etc.) are stored client-side
## for offline / single-machine mode; in a real network session the
## server is the source of truth.
func to_dict() -> Dictionary:
	return {
		"character_id": character_id,
		"display_name": display_name,
		"species_id": species_id,
		"class_id": class_id,
		"level": level,
		"zone_id": zone_id,
		"spawn_position": [spawn_position.x, spawn_position.y, spawn_position.z],
		"allocated_stats": allocated_stats.duplicate(),
		"skill_upgrades": skill_upgrades.duplicate(),
		"active_signature": active_signature,
		"signature_switches": signature_switches,
		"spent_skill_points": spent_skill_points,
		"total_stat_respecs": total_stat_respecs,
	}
