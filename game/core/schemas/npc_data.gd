## NPCData - NPC template definition
extends Resource
class_name NPCData

## Location Type (affects pricing)
enum LocationType {
	TOWN,      # Standard pricing
	OUTPOST,   # Slightly more expensive
	VILLAGE,   # Cheaper (rural)
	DUNGEON,   # Emergency repairs (expensive)
	CAPITAL    # Premium pricing
}

@export var id: String = ""
@export var display_name: String = "NPC"
@export var description: String = ""

# NPC Classification
@export var level: int = 1
@export var faction: String = "friendly"

# Visual
@export var scene_path: String = ""  # Path to NPC .tscn scene
@export var model_path: String = ""   # Legacy alias
@export var icon_path: String = ""

# Dialog
@export var greeting: String = "Hello there."
@export var farewell: String = "Take care."

# Location-based behavior
@export var location_type: LocationType = LocationType.TOWN

# Vendor settings (per-NPC price overrides)
@export var buy_multiplier: float = 0.5
@export var sell_multiplier: float = 1.0
@export var buy_categories: Array[String] = []
@export var sell_categories: Array[String] = []

# Blacksmith settings
@export var base_repair_cost_multiplier: float = 1.0
@export var offers_bulk_discount: bool = true
@export var bulk_discount_percent: float = 10.0
@export var bulk_discount_threshold: int = 5

# Stats (for combat-capable NPCs like guards)
@export var health: int = 100
@export var strength: int = 10
@export var agility: int = 10
@export var intelligence: int = 10
@export var vitality: int = 10

# Combat settings
@export var attack_power: int = 10
@export var armor: int = 5
@export var is_aggressive: bool = false

# Position in world (relative to zone bind point)
@export var spawn_offset: Vector3 = Vector3.ZERO
@export var spawn_rotation: float = 0.0

## Includes -- what this NPC provides when the player interacts.
## Two supported shapes (see normalize_includes()):
##   ref-based:  {type: "offering", ref_id: "vendor_general"}
##               -> data/npc_offerings/<ref_id>.tres
##   inline:     {type: "dialogue", dialogue_id: "village_elder_greeting"}
##               {type: "vendor", ref_id: "vendor_general"}
##               {type: "quest", quest_ids: [...]}, {type: "bank"}
@export var includes: Array[Dictionary] = []

## True when this NPC provides at least one live offering
## (ref-based or inline). Used by world boot to skip non-offering NPC
## placeholder nodes.
func has_live_offering() -> bool:
	for inc in includes:
		var t := str(inc.get("type", ""))
		if t == "":
			continue
		if t == "offering":
			if not str(inc.get("ref_id", "")).is_empty():
				return true
		elif t == "dialogue":
			return not str(inc.get("dialogue_id", "")).is_empty()
		elif t == "vendor":
			return not str(inc.get("ref_id", "")).is_empty()
		elif t == "quest" or t == "bank" or t == "service":
			return true
	return false

## First dialogue id across inline and ref-based entries ("" if none).
func get_dialogue_id() -> String:
	for inc in includes:
		var t := str(inc.get("type", ""))
		if t == "dialogue" and not str(inc.get("dialogue_id", "")).is_empty():
			return str(inc.get("dialogue_id", ""))
		if t == "offering":
			var res := load("res://data/npc_offerings/%s.tres" % str(inc.get("ref_id", "")))
			if res != null and str(res.get("type")) == "dialogue":
				var dlg: Variant = res.get("dialogue_id")
				if dlg != null and str(dlg) != "":
					return str(dlg)
	return ""

## First vendor offering resource across inline and ref-based entries
## (null if none).
func get_vendor_offering() -> Resource:
	for inc in includes:
		var t := str(inc.get("type", ""))
		var ref_id := str(inc.get("ref_id", ""))
		if (t == "vendor" or t == "offering") and not ref_id.is_empty():
			var res := load("res://data/npc_offerings/%s.tres" % ref_id)
			if res != null and str(res.get("type")) == "vendor":
				return res
	return null

## True when the NPC provides an offering of the given type
## ("dialogue", "vendor", "quest", "bank", "service", ...).
func has_offering(offering_type: String) -> bool:
	for inc in includes:
		var t := str(inc.get("type", ""))
		if t == "":
			continue
		if t == "offering":
			var res := load("res://data/npc_offerings/%s.tres" % str(inc.get("ref_id", "")))
			if res != null and str(res.get("type")) == offering_type:
				return true
		elif t == offering_type:
			return true
	return false


## Normalize the two include shapes the codebase ships:
##   ref-based:  {type: "offering", ref_id: "vendor_general"}
##               -> data/npc_offerings/<ref_id>.tres (NPCOffering)
##   inline:     {type: "dialogue", dialogue_id: ...},
##               {type: "vendor", ref_id: ...},
##               {type: "quest", quest_ids: [...]}, {type: "bank"}
##
## Consumers (ActionMenu filter, PlayerController context actions,
## NPCEntity.on_interact) resolve through the helpers below so both
## shapes work everywhere. Called by NPCEntity._ready after load.
func normalize_includes() -> void:
	for inc in includes:
		var t := str(inc.get("type", ""))
		if t == "offering" and str(inc.get("ref_id", "")) == "":
			# Legacy alias: treat a bare "offering" entry with a
			# dialogue_id as an inline dialogue.
			if not str(inc.get("dialogue_id", "")).is_empty():
				inc["type"] = "dialogue"


func _init() -> void:
	if id == "":
		id = display_name.to_lower().replace(" ", "_")

## Get location cost modifier
func get_location_cost_modifier() -> float:
	match location_type:
		LocationType.TOWN:
			return 1.0
		LocationType.OUTPOST:
			return 1.25
		LocationType.VILLAGE:
			return 0.9
		LocationType.DUNGEON:
			return 2.0
		LocationType.CAPITAL:
			return 1.5
	return 1.0

## Get total cost modifier for pricing
func get_total_cost_modifier() -> float:
	return base_repair_cost_multiplier * get_location_cost_modifier()
