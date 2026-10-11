## DataService - Resource discovery and loading
## Scans data/ folder for .tres files and provides access by ID
extends Node



const SkillBook = preload("res://core/schemas/skill_book.gd")
const ActProfile = preload("res://core/schemas/act_profile.gd")
const MysteryData = preload("res://core/schemas/mystery_data.gd")
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
var _movement_profiles: Dictionary = {}
var _hitbox_profiles: Dictionary = {}
## id -> LayerProfile (data/physics_layers/, named collision bits).
var _layer_profiles: Dictionary = {}
## id -> CalibrationTier (data/calibration/, the alignment substrate).
var _calibration: Dictionary = {}
var _signs: Dictionary = {}
var _acts: Dictionary = {}
var _mysteries: Dictionary = {}
var _events: Dictionary = {}
var _dwellings: Dictionary = {}
## id -> WardGateData (data/gates/, the hard gate registry).
var _gates: Dictionary = {}
var _npcs: Dictionary = {}
var _status_effects: Dictionary = {}
var _quests: Dictionary = {}
var _achievements: Dictionary = {}
var _gateways: Dictionary = {}
var _recipes: Dictionary = {}
var _titles: Dictionary = {}
var _hordes: Dictionary = {}
var _weather_events: Dictionary = {}


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
	load_weather_events()
	load_currencies()
	load_mounts()
	load_vehicles()
	load_accessories()
	load_movement_profiles()
	load_hitbox_profiles()
	load_layer_profiles()
	load_signs()
	load_acts()
	load_gates()
	load_mysteries()
	load_calibration()

	_loaded = true
	GameLog.info("DataService: Loaded all data")

## Scan directory for data resources. EXPORT-SAFE (S14-web): the
## exported pack converts .tres to .res + .tres.remap sidecars, so a
## by-extension scan finds NOTHING -- the boot showed "Loaded 0
## species" inside the web client. ResourceScan handles all forms
## and dedupes them; only the id extraction stays local.
const ResourceScan = preload("res://core/frame/srv/resource_scan.gd")

func _scan_directory(path: String, resource_type: String) -> Dictionary:
	var results := ResourceScan.load_dir(path, func(res: Resource, p: String):
		return _get_resource_id(res, p.get_file()))
	if results.is_empty() and DirAccess.open(path) == null:
		GameLog.warn("DataService: Cannot open directory: " + path)
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
		return str(resource.get("id"))
	# Explicit if/else, NOT a ternary: GDScript binds
	# `base.length() - 5 if cond else 4` as `(base.length() - 5) if cond
	# else 4`, which silently returns literal 4 on the .res branch.
	var base: String = ResourceScan.resource_base(filename)
	return base.to_lower()

## Load skills + recipes (data/skills/, data/recipes/)
func load_skills() -> void:
	_skills = _scan_directory(_data_path + "skills", "skill")
	_recipes = _scan_directory(_data_path + "recipes", "recipe")
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

## Load dwellings from data/dwellings/. Item-scripted dwellings (the
	# placeable furniture: chairs, fireplaces, craft stations) MERGE into
	# _items like accessories do -- the purse carries them as plain
	# Items, so placeable stations are bought/held/crafted goods. Pure
	# DwellingData entries stay dwelling-only.
func load_dwellings() -> void:
	var dwelling_paths := _scan_directory(_data_path + "dwellings", "dwelling")
	_dwellings = dwelling_paths
	var dwelling_items := 0
	for id in dwelling_paths:
		var dw = dwelling_paths[id]
		if dw != null and dw.get_script() != null and dw is Item:
			_items.merge({str(id): dw})
			dwelling_items += 1
	GameLog.info("DataService: Loaded %d dwellings (%d purse-carried items)" % [_dwellings.size(), dwelling_items])

## Load NPCs from data/npc/
func load_npcs() -> void:
	_npcs = _scan_directory(_data_path + "npc", "npc")
	GameLog.info("DataService: Loaded %d NPCs" % _npcs.size())

## Load currencies from data/currencies/
func load_currencies() -> void:
	_currencies = _scan_directory(_data_path + "currencies", "currency")
	GameLog.info("DataService: Loaded %d currencies" % _currencies.size())

## Load mounts from data/mounts/ + data/gliders/ (S12.4: a sewn
## glider is a mount -- MountKind.FLYING, movement_glider -- and the
## craft/ride/ledger paths resolve it through the same get_mount
## door; no second registry to drift).
func load_mounts() -> void:
	_mounts = _scan_directory(_data_path + "mounts", "mount")
	_mounts.merge(_scan_directory(_data_path + "gliders", "mount"))
	GameLog.info("DataService: Loaded %d mounts (incl. gliders)" % _mounts.size())

## Load ward gates from data/gates/ (the hard gate registry).
func load_gates() -> void:
	_gates = _scan_directory(_data_path + "gates", "gate")
	GameLog.info("DataService: Loaded %d ward gates" % _gates.size())

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

## Load movement profiles from data/movement_profiles/.
func load_movement_profiles() -> void:
	_movement_profiles = _scan_directory(_data_path + "movement_profiles", "movement")
	GameLog.info("DataService: Loaded %d movement profiles" % _movement_profiles.size())

## Load hitbox profiles from data/hitbox_profiles/.
func load_hitbox_profiles() -> void:
	_hitbox_profiles = _scan_directory(_data_path + "hitbox_profiles", "hitbox")
	GameLog.info("DataService: Loaded %d hitbox profiles" % _hitbox_profiles.size())

## Load layer profiles from data/physics_layers/ (named collision bits).
func load_layer_profiles() -> void:
	_layer_profiles = _scan_directory(_data_path + "physics_layers", "physics")
	GameLog.info("DataService: Loaded %d layer profiles" % _layer_profiles.size())

func get_layer_profile(id: String) -> Resource:
	if _layer_profiles.has(id):
		return _layer_profiles.get(id)
	GameLog.warn("DataService: Layer profile not found: " + id)
	return null

func get_layer_profiles() -> Dictionary:
	return _layer_profiles

## Load calibration tiers from data/calibration/ (the alignment
## substrate, prd-industry-labs.md: time/space/state aligned to the
## Linux epoch, declared as data for the OSS frame).
func load_calibration() -> void:
	_calibration = _scan_directory(_data_path + "calibration", "calibration")
	GameLog.info("DataService: Loaded %d calibration tiers" % _calibration.size())

func get_calibration_tier(id: String) -> Resource:
	if _calibration.has(id):
		return _calibration.get(id)
	GameLog.warn("DataService: Calibration tier not found: " + id)
	return null

func get_calibration_tiers() -> Dictionary:
	return _calibration.duplicate()

## Load Sky Signs from data/signs/.
func load_signs() -> void:
	_signs = _scan_directory(_data_path + "signs", "sign")
	GameLog.info("DataService: Loaded %d signs" % _signs.size())

## Load Acts of the Concord Chronicle from data/acts/.
func load_acts() -> void:
	_acts = _scan_directory(_data_path + "acts", "act")
	GameLog.info("DataService: Loaded %d acts" % _acts.size())

## Load Chronicle mysteries from data/mysteries/.
func load_mysteries() -> void:
	_mysteries = _scan_directory(_data_path + "mysteries", "mystery")
	GameLog.info("DataService: Loaded %d mysteries" % _mysteries.size())

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
func load_recipes() -> void:
	_recipes = _scan_directory(_data_path + "recipes", "recipe")
	GameLog.info("DataService: Loaded %d recipes" % _recipes.size())

## One recipe by id (data/recipes/*.tres, the catalog law). Typed
## loosely (the class_name registration is editor-side; script mode
## parses before globals register -- the RecipeData preloads fine).
func get_recipe(id: String):
	if _recipes.has(id):
		return _recipes.get(id)
	GameLog.warn("DataService: Recipe not found: " + id)
	return null

func get_all_recipes() -> Array:
	return _recipes.values()

func load_gateways() -> void:
	_gateways = _scan_directory(_data_path + "gateways", "gateway")
	GameLog.info("DataService: Loaded %d gateways" % _gateways.size())

## Load horde event configs from data/hordes/
func load_hordes() -> void:
	_hordes = _scan_directory(_data_path + "hordes", "horde")
	GameLog.info("DataService: Loaded %d horde configs" % _hordes.size())

## Load weather-triggered event configs from data/weather_events/
## (the WeatherEventData content pipeline — designers author the
## sun->sword law as .tres, not code). Catalog keys on the resource's
## id field, callers may pass the file-stem form (weather_<id>), same
## normalization as get_horde.
func load_weather_events() -> void:
	_weather_events = _scan_directory(_data_path + "weather_events", "weather")
	GameLog.info("DataService: Loaded %d weather event configs" % _weather_events.size())

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

func get_gate(id: String) -> WardGateData:
	if _gates.has(id):
		return _gates.get(id)
	GameLog.warn("DataService: Ward gate not found: " + id)
	return null

func get_all_gates() -> Dictionary:
	return _gates

func get_all_mounts() -> Dictionary:
	return _mounts

func get_vehicle(id: String) -> VehicleData:
	if _vehicles.has(id):
		return _vehicles.get(id)
	GameLog.warn("DataService: Vehicle not found: " + id)
	return null

## All scheduled vehicles (the walk-up dock seam iterates ROUTES, not
## ids: a pin resolves to the boat whose route_gateways names it --
## no pin-to-boat lookup table to drift). S16.10.
func get_all_vehicles() -> Array:
	return _vehicles.values()

func get_movement_profile(id: String) -> MovementProfile:
	if _movement_profiles.has(id):
		return _movement_profiles.get(id)
	GameLog.warn("DataService: Movement profile not found: " + id)
	return null

func get_hitbox_profile(id: String) -> HitboxProfile:
	if _hitbox_profiles.has(id):
		return _hitbox_profiles.get(id)
	GameLog.warn("DataService: Hitbox profile not found: " + id)
	return null

func get_hitbox_profiles() -> Dictionary:
	return _hitbox_profiles

func get_sign(id: String) -> SignProfile:
	if _signs.has(id):
		return _signs.get(id)
	GameLog.warn("DataService: Sign not found: " + id)
	return null

func get_signs() -> Dictionary:
	return _signs

func get_act(id: String) -> ActProfile:
	if _acts.has(id):
		return _acts.get(id)
	GameLog.warn("DataService: Act not found: " + id)
	return null

## All authored acts sorted by id (act_1... -> act_2... -> act_3...):
## stable order for the almanac's Chronicle block.
func get_acts() -> Dictionary:
	return _acts

func get_mystery(id: String) -> MysteryData:
	if _mysteries.has(id):
		return _mysteries.get(id)
	GameLog.warn("DataService: Mystery not found: " + id)
	return null

func get_mysteries() -> Dictionary:
	return _mysteries


## Resolve the hitbox profile id for a playable character species.
## FAIRNESS RULE (species PvP): every playable species resolves to ONE
## shared profile so no species spawns with a bigger hitbox than
## another. Set `fair_ids` (ids already known to be fair, e.g. all
## species agreeing on hitbox_player) to assert consistency; a species
## deviating from the group logs a fairness error and falls back to the
## group's profile.
func resolve_player_hitbox_profile(species_id: String, fair_ids: Dictionary = {}) -> HitboxProfile:
	var profile_id := "hitbox_player"
	if fair_ids.has("__profile_id"):
		profile_id = str(fair_ids["__profile_id"])
	var sp = get_species(species_id)
	if sp != null:
		var requested = sp.get("hitbox_profile_id")
		if requested != null and not str(requested).is_empty():
			if not fair_ids.is_empty() and str(requested) != profile_id:
				GameLog.error("DataService: SPECIES HITBOX FAIRNESS VIOLATION: species '%s' requests '%s' but playable species share '%s' -- forcing shared profile" % [species_id, str(requested), profile_id])
			else:
				profile_id = str(requested)
	return get_hitbox_profile(profile_id)


## Single resolution path for creature hitboxes: an explicit
## hitbox_profile_id on the data wins; otherwise EnemyData.animation_set
## hints the body plan (wolf -> quadruped beasts, slime -> spheres,
## dummies -> their own tiny profile) and humanoids fall back to
## hitbox_humanoid. No per-consumer fallback code anywhere else.
func get_creature_hitbox_profile(data) -> HitboxProfile:
	var explicit = data.get("hitbox_profile_id") if data != null else null
	if explicit != null and not str(explicit).is_empty():
		return get_hitbox_profile(str(explicit))
	var anim_set = data.get("animation_set") if data != null else null
	match str(anim_set):
		"wolf", "beast", "quadruped":
			return get_hitbox_profile("hitbox_beast_medium")
		"slime":
			return get_hitbox_profile("hitbox_blob")
		_:
			return get_hitbox_profile("hitbox_humanoid")

func get_movement_profiles() -> Dictionary:
	return _movement_profiles


## Single resolution path for rideable/driveable movement: an explicit
## movement_profile_id on the MountData/VehicleData wins; otherwise the
## mount's kind derives it (GROUND->quadruped, FLYING->aerial,
## AQUATIC->aquatic) and vehicles fall back to movement_mechanical.
## No per-consumer fallback code anywhere else.
func get_mount_movement_profile(mount) -> MovementProfile:
	var explicit = mount.get("movement_profile_id") if mount != null else null
	if explicit != null and not str(explicit).is_empty():
		return get_movement_profile(str(explicit))
	if mount != null and mount.get("script") != null and str(mount.get("script").resource_path).ends_with("mount_data.gd"):
		var kind = mount.get("kind")
		var derived: String = "movement_quadruped"
		match int(kind):
			1: derived = "movement_aerial"    # MountKind.FLYING
			2: derived = "movement_aquatic"   # MountKind.AQUATIC
			3: derived = "movement_leviathan" # MountKind.SPACE (R44; movement_lunar is S16.4's Lunar Settler)
			_: derived = "movement_quadruped" # MountKind.GROUND
		return get_movement_profile(derived)
	return get_movement_profile("movement_mechanical")

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

func get_dwelling(id: String) -> Resource:
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

func get_weather_event(id: String):
	var cid := id.strip_edges().trim_prefix("weather_")
	if _weather_events.has(cid):
		return _weather_events.get(cid)
	if _weather_events.has("weather_" + cid):
		return _weather_events.get("weather_" + cid)
	GameLog.warn("DataService: Weather event config not found: " + id)
	return null

func get_all_weather_events() -> Array:
	return _weather_events.values()

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
