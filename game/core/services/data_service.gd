## DataService - Resource discovery and loading
## Scans data/ folder for .tres files and provides access by ID
extends Node



const SkillBook = preload("res://core/schemas/skill_book.gd")
const Item = preload("res://core/schemas/item.gd")
const EnemyData = preload("res://core/schemas/enemy_data.gd")
const CharacterClass = preload("res://core/schemas/character_class.gd")
const Species = preload("res://core/schemas/species.gd")
const Faction = preload("res://core/schemas/faction.gd")
const ZoneData = preload("res://core/schemas/zone_data.gd")
const EventData = preload("res://core/schemas/event_data.gd")
const DwellingData = preload("res://core/schemas/dwelling_data.gd")
const NPCData = preload("res://core/schemas/npc_data.gd")
const StatusEffectData = preload("res://core/schemas/status_effect_data.gd")
const QuestData = preload("res://core/schemas/quest_data.gd")
const AchievementData = preload("res://core/schemas/achievement_data.gd")
const GatewayData = preload("res://core/schemas/gateway_data.gd")
const HordeData = preload("res://core/schemas/horde_data.gd")
const Skill = preload("res://core/combat/skill.gd")
var _skills: Dictionary = {}
var _items: Dictionary = {}

# Item subcategories
var _weapons: Dictionary = {}
var _armors: Dictionary = {}
var _accessories: Dictionary = {}
var _consumables: Dictionary = {}
var _resources: Dictionary = {}
var _misc: Dictionary = {}

var _enemies: Dictionary = {}
var _classes: Dictionary = {}
var _species: Dictionary = {}
var _factions: Dictionary = {}
var _zones: Dictionary = {}

var _currencies: Dictionary = {}
var _mounts: Dictionary = {}
var _vehicles: Dictionary = {}
var _events: Dictionary = {}
var _dwellings: Dictionary = {}
var _npcs: Dictionary = {}
var _status_effects: Dictionary = {}
var _quests: Dictionary = {}
var _achievements: Dictionary = {}
var _gateways: Dictionary = {}
var _titles: Dictionary = {}
var _hordes: Dictionary = {}

var _data_path: String = "res://data/"
var _loaded: bool = false

func _ready() -> void:
	load_all_data()

## Load all data from data/ folder
func load_all_data() -> void:
	if _loaded:
		return

	load_skills()
	load_items()
	load_enemies()
	load_classes()
	load_species()
	load_factions()
	load_zones()
	load_events()
	load_dwellings()
	load_npcs()
	load_status_effects()
	load_quests()
	load_titles()
	load_achievements()
	load_gateways()
	load_hordes()
	load_currencies()
	load_mounts()
	load_vehicles()
	load_accessories()

	_loaded = true
	GameLog.info("DataService: Loaded all data")

## Scan directory for .tres files
func _scan_directory(path: String, resource_type: String) -> Dictionary:
	var results: Dictionary = {}

	var dir := DirAccess.open(path)
	if dir == null:
		GameLog.warn("DataService: Cannot open directory: " + path)
		return results

	dir.list_dir_begin()
	var file_name := dir.get_next()

	while file_name != "":
		if dir.current_is_dir():
			if file_name != "." and file_name != "..":
				var sub_results := _scan_directory(path + "/" + file_name, resource_type)
				results.merge(sub_results)
		else:
			if file_name.ends_with(".tres"):
				var resource_path := path + "/" + file_name
				var resource = load_resource(resource_path)
				if resource:
					var id := _get_resource_id(resource, file_name)
					results[id] = resource
					GameLog.debug("DataService: Loaded " + resource_type + ": " + id)

		file_name = dir.get_next()

	dir.list_dir_end()
	return results

## Load a single resource
func load_resource(path: String) -> Resource:
	var resource = load(path)
	if resource == null:
		GameLog.warn("DataService: Failed to load: " + path)
	return resource

## Extract ID from resource or filename
func _get_resource_id(resource: Resource, filename: String) -> String:
	if resource and resource.get("id") != null:
		return resource.get("id")
	return filename.replace(".tres", "").to_lower()

## Load skills from data/skills/
func load_skills() -> void:
	_skills = _scan_directory(_data_path + "skills", "skill")
	GameLog.info("DataService: Loaded %d skills" % _skills.size())

## Load items from categorized subdirectories
func load_items() -> void:
	_items.clear()
	_weapons.clear()
	_armors.clear()
	_consumables.clear()
	_resources.clear()
	_misc.clear()

	var weapon_paths := _scan_directory(_data_path + "weapons", "item")
	_items.merge(weapon_paths)
	_weapons = weapon_paths
	var armor_paths := _scan_directory(_data_path + "armors", "item")
	_items.merge(armor_paths)
	_armors = armor_paths

	var consumable_paths := _scan_directory(_data_path + "consumables", "item")
	_items.merge(consumable_paths)
	_consumables = consumable_paths

	var resource_paths := _scan_directory(_data_path + "resources", "item")
	_items.merge(resource_paths)
	_resources = resource_paths

	# data/items/ holds every leftover item class: coins, quest tokens,
	# vanity, garbage loot. item_quest_* files are quest items (the
	# naming lint enforces their quest_id ref).
	var item_paths := _scan_directory(_data_path + "items", "item")
	_items.merge(item_paths)
	_misc = item_paths

	GameLog.info("DataService: Loaded %d items" % _items.size())

## Load enemies from data/enemies/
func load_enemies() -> void:
	_enemies = _scan_directory(_data_path + "enemies", "enemy")
	GameLog.info("DataService: Loaded %d enemies" % _enemies.size())

## Load classes from data/classes/
func load_classes() -> void:
	_classes = _scan_directory(_data_path + "classes", "class")
	GameLog.info("DataService: Loaded %d classes" % _classes.size())

## Load species from data/species/
func load_species() -> void:
	_species = _scan_directory(_data_path + "species", "species")
	GameLog.info("DataService: Loaded %d species" % _species.size())

## Load factions from data/factions/
func load_factions() -> void:
	_factions = _scan_directory(_data_path + "factions", "faction")
	GameLog.info("DataService: Loaded %d factions" % _factions.size())

## Load zones from data/zones/
func load_zones() -> void:
	_zones = _scan_directory(_data_path + "zones", "zone")
	GameLog.info("DataService: Loaded %d zones" % _zones.size())

## Load events from data/events/
func load_events() -> void:
	_events = _scan_directory(_data_path + "events", "event")
	GameLog.info("DataService: Loaded %d events" % _events.size())

## Load dwellings from data/dwellings/
func load_dwellings() -> void:
	_dwellings = _scan_directory(_data_path + "dwellings", "dwelling")
	GameLog.info("DataService: Loaded %d dwellings" % _dwellings.size())

## Load NPCs from data/npc/
func load_npcs() -> void:
	_npcs = _scan_directory(_data_path + "npc", "npc")
	GameLog.info("DataService: Loaded %d NPCs" % _npcs.size())

## Load currencies from data/currencies/
func load_currencies() -> void:
	_currencies = _scan_directory(_data_path + "currencies", "currency")
	GameLog.info("DataService: Loaded %d currencies" % _currencies.size())

## Load mounts from data/mounts/
func load_mounts() -> void:
	_mounts = _scan_directory(_data_path + "mounts", "mount")
	GameLog.info("DataService: Loaded %d mounts" % _mounts.size())

## Load vehicles from data/vehicles/
func load_vehicles() -> void:
	_vehicles = _scan_directory(_data_path + "vehicles", "vehicle")
	GameLog.info("DataService: Loaded %d vehicles" % _vehicles.size())

## Load accessories (rings, necklaces, cloaks, belts) from data/accessories/.
## Merged into _items so inventory/equip paths see them as plain Items.
func load_accessories() -> void:
	var acc_paths := _scan_directory(_data_path + "accessories", "item")
	_items.merge(acc_paths)
	GameLog.info("DataService: Loaded %d accessories" % acc_paths.size())

## Load status effects from data/status_effects/
func load_status_effects() -> void:
	_status_effects = _scan_directory(_data_path + "status_effects", "status_effect")
	GameLog.info("DataService: Loaded %d status effects" % _status_effects.size())

## Load quests from data/quests/
func load_quests() -> void:
	_quests = _scan_directory(_data_path + "quests", "quest")
	GameLog.info("DataService: Loaded %d quests" % _quests.size())

## Load titles from data/titles/
func load_titles() -> void:
	_titles = _scan_directory(_data_path + "titles", "title")
	GameLog.info("DataService: Loaded %d titles" % _titles.size())

## Load achievements from data/achievements/
func load_achievements() -> void:
	_achievements = _scan_directory(_data_path + "achievements", "achievement")
	GameLog.info("DataService: Loaded %d achievements" % _achievements.size())

## Load gateways from data/gateways/
func load_gateways() -> void:
	_gateways = _scan_directory(_data_path + "gateways", "gateway")
	GameLog.info("DataService: Loaded %d gateways" % _gateways.size())

## Load horde event configs from data/hordes/
func load_hordes() -> void:
	_hordes = _scan_directory(_data_path + "hordes", "horde")
	GameLog.info("DataService: Loaded %d horde configs" % _hordes.size())

## Get methods. Returns SkillSchema (the .tres class); the return type
## must be SkillSchema -- the global class_name Skill (combat) shadowed
## the intended annotation here, which made every actual load a
## runtime type error once this path was finally exercised.
func get_skill(id: String) -> SkillSchema:
	if _skills.has(id):
		return _skills.get(id)
	GameLog.warn("DataService: Skill not found: " + id)
	return null

func get_item(id: String) -> Item:
	if _items.has(id):
		return _items.get(id)
	# Handle dynamically-generated SkillBook IDs (book_<skill_id>_<tier>)
	if id.begins_with("book_"):
		return _create_skill_book_from_id(id)
	GameLog.warn("DataService: Item not found: " + id)
	return null

func get_enemy(id: String) -> EnemyData:
	if _enemies.has(id):
		return _enemies.get(id)
	GameLog.warn("DataService: Enemy not found: " + id)
	return null

func get_character_class(id: String) -> CharacterClass:
	if _classes.has(id):
		return _classes.get(id)
	GameLog.warn("DataService: CharacterClass not found: " + id)
	return null

func get_species(id: String) -> Species:
	if _species.has(id):
		return _species.get(id)
	GameLog.warn("DataService: Species not found: " + id)
	return null

func get_faction(id: String) -> Faction:
	if _factions.has(id):
		return _factions.get(id)
	GameLog.warn("DataService: Faction not found: " + id)
	return null

func get_currency(id: String) -> CurrencyData:
	if _currencies.has(id):
		return _currencies.get(id)
	GameLog.warn("DataService: Currency not found: " + id)
	return null

func get_all_currencies() -> Array:
	return _currencies.values()

func get_mount(id: String) -> MountData:
	if _mounts.has(id):
		return _mounts.get(id)
	GameLog.warn("DataService: Mount not found: " + id)
	return null

func get_vehicle(id: String) -> VehicleData:
	if _vehicles.has(id):
		return _vehicles.get(id)
	GameLog.warn("DataService: Vehicle not found: " + id)
	return null

func get_zone(id: String) -> ZoneData:
	if _zones.has(id):
		return _zones.get(id)
	GameLog.warn("DataService: Zone not found: " + id)
	return null

func get_event(id: String) -> EventData:
	if _events.has(id):
		return _events.get(id)
	GameLog.warn("DataService: Event not found: " + id)
	return null

func get_dwelling(id: String) -> DwellingData:
	if _dwellings.has(id):
		return _dwellings.get(id)
	GameLog.warn("DataService: Dwelling not found: " + id)
	return null

func get_npc(id: String) -> NPCData:
	if _npcs.has(id):
		return _npcs.get(id)
	GameLog.warn("DataService: NPC not found: " + id)
	return null

func get_status_effect(id: String) -> StatusEffectData:
	if _status_effects.has(id):
		return _status_effects.get(id)
	GameLog.warn("DataService: StatusEffect not found: " + id)
	return null

func get_quest(id: String) -> QuestData:
	if _quests.has(id):
		return _quests.get(id)
	GameLog.warn("DataService: Quest not found: " + id)
	return null

func get_gateway(id: String) -> GatewayData:
	if _gateways.has(id):
		return _gateways.get(id)
	GameLog.warn("DataService: Gateway not found: " + id)
	return null

## Horde event config lookup (data/hordes/*.tres). The HordeDataResolver
## probes for this hook after its convention paths, so catalog-driven
## consumers (and the /horde trigger command's listing) share one source.
## The catalog keys on the resource's id field ("vault_seal"), but
## callers may pass the file-stem form ("horde_vault_seal") -- the
## prefix is normalized away so both naming styles resolve.
func get_horde(id: String):
	var cid := id.strip_edges().trim_prefix("horde_")
	if _hordes.has(cid):
		return _hordes.get(cid)
	if _hordes.has("horde_" + cid):
		return _hordes.get("horde_" + cid)
	GameLog.warn("DataService: Horde config not found: " + id)
	return null

func get_all_hordes() -> Array:
	return _hordes.values()

## Get all of a type
func get_all_skills() -> Array:
	return _skills.values()

func get_all_items() -> Array:
	return _items.values()

func get_all_enemies() -> Array:
	return _enemies.values()

func get_all_classes() -> Array:
	return _classes.values()

func get_all_species() -> Array:
	return _species.values()

func get_all_factions() -> Array:
	return _factions.values()

func get_all_zones() -> Array:
	return _zones.values()

func get_all_events() -> Array:
	return _events.values()

func get_all_dwellings() -> Array:
	return _dwellings.values()

func get_all_npcs() -> Array:
	return _npcs.values()

func get_all_status_effects() -> Array:
	return _status_effects.values()

func get_all_quests() -> Array:
	return _quests.values()

func get_achievement(id: String) -> AchievementData:
	if _achievements.has(id):
		return _achievements.get(id)
	GameLog.warn("DataService: Achievement not found: " + id)
	return null

func get_all_titles() -> Array:
	return _titles.values()


func get_all_achievements() -> Array:
	return _achievements.values()

func get_all_gateways() -> Array:
	return _gateways.values()

## Reload data (for development)
func reload_all() -> void:
	_loaded = false
	_skills.clear()
	_items.clear()
	_weapons.clear()
	_armors.clear()
	_consumables.clear()
	_resources.clear()
	_misc.clear()
	_enemies.clear()
	_classes.clear()
	_species.clear()
	_factions.clear()
	_zones.clear()
	_events.clear()
	_dwellings.clear()
	_npcs.clear()
	_status_effects.clear()
	_quests.clear()
	_achievements.clear()
	_gateways.clear()
	_titles.clear()
	load_all_data()

## Reload specific category
func reload_category(category: String) -> void:
	match category:
		"skills":
			_skills.clear()
			load_skills()
		"items":
			_items.clear()
			_weapons.clear()
			_armors.clear()
			_consumables.clear()
			_resources.clear()
			_misc.clear()
			load_items()
		"enemies":
			_enemies.clear()
			load_enemies()
		"classes":
			_classes.clear()
			load_classes()
		"species":
			_species.clear()
			load_species()
		"factions":
			_factions.clear()
			load_factions()
		"currencies":
			_currencies.clear()
			load_currencies()
		"mounts":
			_mounts.clear()
			load_mounts()
		"vehicles":
			_vehicles.clear()
			load_vehicles()
		"zones":
			_zones.clear()
			load_zones()
		"npcs":
			_npcs.clear()
			load_npcs()
		"status_effects":
			_status_effects.clear()
			load_status_effects()
		"quests":
			_quests.clear()
			load_quests()
		"achievements":
			_achievements.clear()
			load_achievements()
		"gateways":
			_gateways.clear()
			load_gateways()
		_:
			GameLog.warn("DataService: Unknown category: " + category)

## Get counts
func get_counts() -> Dictionary:
	return {
		"skills": _skills.size(),
		"items": _items.size(),
		"enemies": _enemies.size(),
		"classes": _classes.size(),
		"species": _species.size(),
		"factions": _factions.size(),
		"zones": _zones.size(),
		"npcs": _npcs.size(),
		"currencies": _currencies.size(),
		"mounts": _mounts.size(),
		"vehicles": _vehicles.size(),
		"status_effects": _status_effects.size(),
		"quests": _quests.size(),
		"achievements": _achievements.size(),
		"gateways": _gateways.size()
	}

## Construct a SkillBook from a loot-table item_id string (book_<skill_id>_<tier>).
## tier names: common/rare/epic/legendary/mythic -> upgrade_level 1..5.
func _create_skill_book_from_id(item_id: String) -> Item:
	var parts := item_id.split("_")
	if parts.size() < 3:
		return null
	var tier_str := parts[parts.size() - 1]
	var skill_id := "_".join(parts.slice(1, parts.size() - 1))

	var tier_map := {
		"common": 1, "rare": 2, "epic": 3, "legendary": 4, "mythic": 5
	}
	var upgrade_level: int = tier_map.get(tier_str, 1)

	var skill: SkillSchema = _skills.get(skill_id)
	var display_name: String = skill.display_name if skill else skill_id

	return SkillBook.create(skill_id, upgrade_level, display_name)
