## IDRegistry - Centralized ID generation and validation
## Defines ID prefixes for all entity types to prevent collisions
class_name IDRegistry
extends RefCounted

## ID Prefixes (reserved ranges)
enum Prefix {
	PLAYER = "plr_",      # Player characters
	ENTITY = "ent_",       # Generic entities
	ENEMY  = "eny_",       # Enemies
	NPC    = "npc_",       # Non-player characters
	ITEM   = "itm_",       # Items, equipment
	SKILL  = "skl_",       # Skills, spells, abilities
	ZONE   = "zn_",        # Zones
	QUEST  = "qst_",       # Quests
	FACTION= "fct_",       # Factions
	OBJECT = "obj_",       # World objects, furniture
	LOOT   = "lto_",       # Loot drops
	EVENT  = "evt_",       # World events
	GUILD  = "gld_",       # Guilds
	PARTY  = "prt_",       # Parties
	CHAT   = "cht_",       # Chat channels
	SCENE  = "scn_",       # Scene spawns
}

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
	# Check custom prefixes
	for prefix in Prefix.values():
		if id.begins_with(prefix):
			return true
	# Check reserved ranges
	for prefix in RESERVED_RANGES:
		if id.begins_with(prefix):
			return true
	return false

## Get the type category from an ID
func get_type(id: String) -> String:
	for prefix in Prefix.values():
		if id.begins_with(prefix):
			var name := prefix.trim_suffix("_")
			return name.to_upper()
	for prefix in RESERVED_RANGES:
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
	return generate("plr_")

## Generate enemy ID
func generate_enemy(template_id: String = "") -> String:
	return generate("eny_", template_id)

## Generate NPC ID
func generate_npc(template_id: String = "") -> String:
	return generate("npc_", template_id)

## Generate item ID
func generate_item(template_id: String = "") -> String:
	return generate("itm_", template_id)

## Generate zone ID
func generate_zone(template_id: String = "") -> String:
	return generate("zn_", template_id)

## Generate loot ID
func generate_loot(spawner_id: String = "") -> String:
	return generate("lto_", spawner_id)

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
	
	# Find the underscore position
	var underscore_pos := id.find("_")
	if underscore_pos >= 0:
		result.prefix = id.substr(0, underscore_pos + 1)
		result.suffix = id.substr(underscore_pos + 1)
	
	return result

## Validate ID is of expected type
func validate_type(id: String, expected_type: String) -> bool:
	var actual_type := get_type(id)
	return actual_type.to_lower() == expected_type.to_lower()

## Get all registered prefixes
func get_all_prefixes() -> Array[String]:
	var prefixes: Array[String] = []
	for prefix in Prefix.values():
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
		"zn":  "Zone",
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
	
	var parsed := parse_id(id)
	return type_map.get(parsed.prefix.trim_suffix("_"), "Unknown")
}

## Internal: Generate timestamp-based unique ID
func _generate_timestamp_id() -> String:
	var ts := Time.get_datetime_string_from_system()
	ts = ts.replace("-", "").replace(":", "").replace("T", "_")
	ts += "_%d" % randi_range(1000, 9999)
	return ts
