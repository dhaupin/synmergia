## IDRegistry - Centralized ID generation and validation
## Defines ID prefixes for all entity types to prevent collisions
extends Node

## ID Prefixes (reserved ranges)
const PREFIX_PLAYER := "plr_"
const PREFIX_ENTITY := "ent_"
const PREFIX_ENEMY := "eny_"
const PREFIX_NPC := "npc_"
const PREFIX_ITEM := "itm_"
const PREFIX_SKILL := "skl_"
const PREFIX_ZONE := "zn_"
const PREFIX_QUEST := "qst_"
const PREFIX_FACTION := "fct_"
const PREFIX_OBJECT := "obj_"
const PREFIX_LOOT := "lto_"
const PREFIX_EVENT := "evt_"
const PREFIX_GUILD := "gld_"
const PREFIX_PARTY := "prt_"
const PREFIX_CHAT := "cht_"
const PREFIX_SCENE := "scn_"

const ALL_PREFIXES := [
	PREFIX_PLAYER, PREFIX_ENTITY, PREFIX_ENEMY, PREFIX_NPC,
	PREFIX_ITEM, PREFIX_SKILL, PREFIX_ZONE, PREFIX_QUEST,
	PREFIX_FACTION, PREFIX_OBJECT, PREFIX_LOOT, PREFIX_EVENT,
	PREFIX_GUILD, PREFIX_PARTY, PREFIX_CHAT, PREFIX_SCENE,
]

## Reserved ID ranges (for special purposes)
const RESERVED_RANGES := {
	"sys_": "System IDs (internal use)",
	"tmp_": "Temporary IDs (runtime only)",
	"dbg_": "Debug IDs (development only)",
}

## Validate an ID format
func is_valid_id(id: String) -> bool:
	if id.is_empty():
		return false
	for prefix in ALL_PREFIXES:
		if id.begins_with(prefix):
			return true
	for prefix in RESERVED_RANGES:
		if id.begins_with(prefix):
			return true
	return false

## Get the type category from an ID
func get_type(id: String) -> String:
	for prefix: String in ALL_PREFIXES:
		if id.begins_with(prefix):
			var name: String = prefix.trim_suffix("_")
			return name.to_upper()
	for prefix: String in RESERVED_RANGES:
		if id.begins_with(prefix):
			return prefix.trim_suffix("_").to_upper()
	return "UNKNOWN"

## Generate a new ID with a given prefix
func generate(prefix: String, unique_id: String = "") -> String:
	var base_id := prefix
	if unique_id != "":
		base_id += unique_id
	else:
		base_id += _generate_timestamp_id()
	return base_id

## Generate player ID
func generate_player(steam_id: String = "") -> String:
	if steam_id != "":
		return "plr_%s" % steam_id
	return generate(PREFIX_PLAYER)

## Generate enemy ID
func generate_enemy(template_id: String = "") -> String:
	return generate(PREFIX_ENEMY, template_id)

## Generate NPC ID
func generate_npc(template_id: String = "") -> String:
	return generate(PREFIX_NPC, template_id)

## Generate item ID
func generate_item(template_id: String = "") -> String:
	return generate(PREFIX_ITEM, template_id)

## Generate zone ID
func generate_zone(template_id: String = "") -> String:
	return generate(PREFIX_ZONE, template_id)

## Generate loot ID
func generate_loot(spawner_id: String = "") -> String:
	return generate(PREFIX_LOOT, spawner_id)

## Parse ID to extract components
func parse_id(id: String) -> Dictionary:
	var result := {
		"prefix": "",
		"suffix": "",
		"type": "UNKNOWN",
		"is_valid": false
	}

	if not is_valid_id(id):
		return result

	result.is_valid = true
	result.type = get_type(id)

	var underscore_pos: int = id.find("_")
	if underscore_pos >= 0:
		result.prefix = id.substr(0, underscore_pos + 1)
		result.suffix = id.substr(underscore_pos + 1)

	return result

## Validate ID is of expected type
func validate_type(id: String, expected_type: String) -> bool:
	var actual_type: String = get_type(id)
	return actual_type.to_lower() == expected_type.to_lower()

## Get all registered prefixes
func get_all_prefixes() -> Array[String]:
	var prefixes: Array[String] = []
	for prefix in ALL_PREFIXES:
		prefixes.append(prefix)
	for prefix in RESERVED_RANGES:
		prefixes.append(prefix)
	return prefixes

## Human-readable type name
func get_type_display_name(id: String) -> String:
	var type_map := {
		"plr": "Player",
		"ent": "Entity",
		"eny": "Enemy",
		"npc": "NPC",
		"itm": "Item",
		"skl": "Skill",
		"zn": "Zone",
		"qst": "Quest",
		"fct": "Faction",
		"obj": "Object",
		"lto": "Loot",
		"evt": "Event",
		"gld": "Guild",
		"prt": "Party",
		"cht": "Chat",
		"scn": "Scene",
	}

	var parsed: Dictionary = parse_id(id)
	return type_map.get(parsed.prefix.trim_suffix("_"), "Unknown")

## Internal: Generate timestamp-based unique ID
func _generate_timestamp_id() -> String:
	var ts: String = Time.get_datetime_string_from_system()
	ts = ts.replace("-", "").replace(":", "").replace("T", "_")
	ts += "_%d" % randi_range(1000, 9999)
	return ts
