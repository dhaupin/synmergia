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

## Filter: exclude GM class from player-facing lists.
static func _is_gm_class(cls: CharacterClass) -> bool:
	return cls.role == CharacterClass.Role.GM

static func get_available_classes_for_species(species_id: String) -> Array[CharacterClass]:
	var result: Array[CharacterClass] = []
	var dir := DirAccess.open("res://data/classes/")
	if dir:
		dir.list_dir_begin()
		var file := dir.get_next()
		while file != "":
			if file.ends_with(".tres"):
				var res := load("res://data/classes/" + file)
				if res is CharacterClass and not _is_gm_class(res):
					result.append(res)
			file = dir.get_next()
	return result

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
