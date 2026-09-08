## ZoneData - Zone/area definition
## Defines zone boundaries, entry requirements, and PvP rules
extends Resource
class_name ZoneData

enum PvPZoneMode {
	SAFE,         # No PvP at all - all species coexist
	SPECIES_PVP,  # Different species can fight (like RYL2 arena)
	FACTION_PVP,  # Different factions can fight
	FREE_PVP,    # Everyone can fight everyone
	WARZONE      # Guild wars active, full loot
}

@export var id: String = ""
@export var display_name: String = "Unknown Zone"
@export var description: String = ""

# Zone PvP mode
@export var pvp_mode: PvPZoneMode = PvPZoneMode.SAFE

# Level requirements
@export var level_requirement: int = 1
@export var max_level: int = 999

# Entry restrictions (empty = all allowed)
@export var allowed_factions: Array[String] = []  # Empty = all allowed
@export var blocked_sactions: Array[String] = []   # Explicitly blocked factions
@export var blocked_species: Array[String] = []   # Species that cannot enter

# Respawn settings
@export var respawn_at_bind: bool = true  # Respawn at bind point vs zone spawn
@export var respawn_timer: float = 10.0   # Seconds before respawn

# Zone bounds (for auto-detection when entity enters/exits)
@export var bounds: AABB = AABB(Vector3(-500, 0, -500), Vector3(1000, 100, 1000))
@export var zone_center: Vector3 = Vector3.ZERO
@export var zone_radius: float = 500.0  # For circular zones

# Environment
@export var ambient_light_color: Color = Color(0.5, 0.5, 0.5)
@export var ambient_light_energy: float = 1.0
@export var environment_path: String = ""  # Environment resource path

# Weather effects (future)
@export var has_weather: bool = false
@export var weather_type: String = "clear"  # clear, rain, snow, fog, etc.

# Spawn points
@export var spawn_points: Array[Vector3] = []
@export var bind_point: Vector3 = Vector3.ZERO  # Where player binds/respawns

# NPCs in this zone
@export var npcs: Array[String] = []  # NPC IDs to spawn

# Loot multiplier for this zone
@export var loot_multiplier: float = 1.0
@export var xp_multiplier: float = 1.0

# Zone is instanced (dungeons)
@export var is_instanced: bool = false
@export var instance_capacity: int = 0  # 0 = unlimited

func _init() -> void:
	if id == "":
		id = display_name.to_lower().replace(" ", "_")

## Check if a player can enter this zone
func can_enter(entity) -> bool:
	# Level check
	if entity.level < level_requirement:
		return false
	if entity.level > max_level and max_level > 0:
		return false

	# Faction check
	if not allowed_factions.is_empty():
		if "faction_id" in entity:
			if not allowed_factions.has(entity.faction_id):
				return false

	if blocked_sactions.has(entity.faction_id):
		return false

	# Species check
	if "species_id" in entity:
		if blocked_species.has(entity.species_id):
			return false

	return true

## Can entity1 attack entity2 in this zone?
func can_pvp(entity1, entity2) -> bool:
	match pvp_mode:
		PvPZoneMode.SAFE:
			return false

		PvPZoneMode.SPECIES_PVP:
			# Different species can fight
			if "species_id" in entity1 and "species_id" in entity2:
				return entity1.species_id != entity2.species_id
			return entity1.faction != entity2.faction

		PvPZoneMode.FACTION_PVP:
			# Different factions can fight
			return entity1.faction != entity2.faction

		PvPZoneMode.FREE_PVP:
			# Everyone can fight
			return true

		PvPZoneMode.WARZONE:
			# Everyone can fight, full loot
			return true

	return false

## Is this a full-loot zone?
func is_full_loot() -> bool:
	return pvp_mode == PvPZoneMode.WARZONE

## Get respawn position for this zone
func get_respawn_position() -> Vector3:
	if respawn_at_bind and bind_point != Vector3.ZERO:
		return bind_point
	if not spawn_points.is_empty():
		return spawn_points[randi() % spawn_points.size()]
	return zone_center

## Check if a position is within this zone's bounds
func contains_position(position: Vector3) -> bool:
	if zone_radius > 0:
		return position.distance_to(zone_center) <= zone_radius
	return bounds.has_point(position)

## Get zone difficulty for scaling
func get_difficulty() -> int:
	# Higher = more difficult
	var base_difficulty := (level_requirement / 10) as int
	match pvp_mode:
		PvPZoneMode.WARZONE:
			base_difficulty += 5
		PvPZoneMode.FREE_PVP:
			base_difficulty += 3
		PvPZoneMode.SPECIES_PVP:
			base_difficulty += 2
	return base_difficulty

## Get display info for UI
func get_info() -> Dictionary:
	return {
		"id": id,
		"name": display_name,
		"description": description,
		"pvp_mode": PvPZoneMode.keys()[pvp_mode],
		"level_range": "%d-%d" % [level_requirement, max_level],
		"loot_multiplier": loot_multiplier,
		"xp_multiplier": xp_multiplier
	}
