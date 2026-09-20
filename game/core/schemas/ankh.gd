## Ankh - Respawn point object
## UO-style ankhs scattered through the world as respawn points
extends Node3D
class_name Ankh

enum AnkhType {
	SHARED,      # All players can bind here
	PERSONAL,    # Individual binding (persist across sessions)
	GUILD,       # Guild-only binding
	FACTION,     # Faction-restricted
	NEUTRAL,     # No restrictions, but no bonuses
	BLESSED,     # Faster respawn when bound here
	CURSED,      # Slower respawn, debuffs on respawn
	ARENA        # Arena-specific, team-based
}

enum AnkhSize {
	SMALL,       # Personal use only
	MEDIUM,      # Small group
	LARGE,       # Raid/group
	COLOSSAL     # City-wide
}

signal activated(player, ankh: Ankh)
signal deactivated(player, ankh: Ankh)
signal bound_to(player, ankh: Ankh)

@export var ankh_id: String = ""
@export var display_name: String = "Ankh"
@export var description: String = "A mystical resurrection point."

# Type and size
@export var ankh_type: AnkhType = AnkhType.SHARED
@export var ankh_size: AnkhSize = AnkhSize.MEDIUM

# Zone linking
@export var zone_id: String = ""  # Which zone this ankh is in
@export var gateway_ids: Array[String] = []  # Connected gateway IDs

# Restrictions
@export var min_level: int = 0
@export var max_level: int = 100
@export var required_faction: String = ""
@export var required_guild_rank: int = 0
@export var required_quest_ids: Array[String] = []

# Respawn modifiers when bound to this ankh
@export var respawn_time_modifier: float = 1.0  # Multiplier (0.5 = 50% faster)
@export var respawn_cost_modifier: float = 1.0  # Durability loss, XP penalty
@export var blessed_duration: float = 0.0  # Seconds of invincibility after respawn
@export var debuffs_on_respawn: Array[String] = []  # Debuff IDs to apply

# Combat zone settings
@export var is_in_pvp_zone: bool = false
@export var is_in_arena: bool = false
@export var arena_team_id: int = 0  # For arena ankhs
@export var respawn_count_limit: int = 0  # 0 = unlimited
var _team_respawn_counts: Dictionary = {}  # team_id -> remaining respawns
@export var contested_respawn: bool = false  # Fight for res

# Binding cooldown
@export var bind_cooldown_seconds: float = 60.0  # Cooldown between re-binds
var _player_bind_times: Dictionary = {}  # player_id -> last_bind_timestamp

# Visual
@export var model_path: String = ""
@export var glow_color: Color = Color.WHITE
@export var particle_effect: String = ""

# Coverage (how far this ankh "protects")
@export var coverage_radius: float = 50.0  # Players in range can bind
@export var activation_radius: float = 3.0  # Must be this close to activate

# State
var _bound_players: Array[String] = []  # Player IDs currently bound
var _bound_guilds: Array[String] = []  # Guild IDs (for guild ankhs)

func _ready() -> void:
	add_to_group("ankhs")
	# Persist across scene reloads is NOT wanted for scene-placed ankhs
	# (the scene owns them); group membership is what RespawnService
	# resolves by, and that survives as long as the node does.

## Check if a player can bind to this ankh. Duck-typed on purpose:
## callers pass PlayerController (not an Entity), which carries
## entity_id/display_name/level/health_component but no faction_id or
## guild_rank properties.
func can_bind(player) -> bool:
	if player == null:
		return false

	# Level check (missing on entities without levels -> treat as 1)
	var plevel := 1
	if "level" in player:
		plevel = int(player.level)
	if plevel < min_level or plevel > max_level:
		return false

	# Faction check (only when the ankh restricts AND the entity has one)
	if required_faction != "":
		if not "faction" in player or player.faction != required_faction:
			return false

	# Quest check (has_completed_quest is optional on stubs)
	for quest_id in required_quest_ids:
		if not player.has_method("has_completed_quest") or not player.has_completed_quest(quest_id):
			return false

	# Guild check for guild ankhs (guild_rank may not exist)
	if ankh_type == AnkhType.GUILD:
		if not "guild_rank" in player or int(player.guild_rank) < required_guild_rank:
			return false

	# Cooldown check (anti-exploit)
	if _player_bind_times.has(player.entity_id):
		var last_bind: float = _player_bind_times[player.entity_id]
		var elapsed: float = Time.get_unix_time_from_system() - last_bind
		if elapsed < bind_cooldown_seconds:
			return false

	return true

## Bind player to this ankh
func bind_player(player) -> bool:
	if not can_bind(player):
		return false

	# Prevent binding while dead (exploit prevention); health_component
	# is optional on test stubs.
	if "health_component" in player and player.health_component != null \
			and player.health_component.has_method("is_dead") \
			and player.health_component.is_dead():
		GameLog.warn("Ankh '%s': Player '%s' tried to bind while dead" % [ankh_id, player.display_name])
		return false

	if not _bound_players.has(player.entity_id):
		_bound_players.append(player.entity_id)

	# Record binding time for cooldown
	_player_bind_times[player.entity_id] = Time.get_unix_time_from_system()

	# Set as player's respawn point. RespawnService reads
	# player.respawn_ankh_id when offering the ANKH respawn mode; the
	# health component's bind position is what its own timer respawns to.
	player.respawn_ankh_id = ankh_id
	if "respawn_point" in player:
		player.respawn_point = global_position
	if "health_component" in player and player.health_component != null \
			and player.health_component.has_method("set_bind_position"):
		player.health_component.set_bind_position(global_position)

	bound_to.emit(player, self)
	activated.emit(player, self)

	GameLog.info("Ankh '%s': Player '%s' bound" % [ankh_id, player.display_name])
	return true

## Unbind player from this ankh
func unbind_player(player) -> void:
	_bound_players.erase(player.entity_id)
	deactivated.emit(player, self)

## Get respawn time for a player
func get_respawn_time(base_time: float) -> float:
	return base_time * respawn_time_modifier

## Get respawn info for a player
func get_respawn_info(player) -> Dictionary:
	return {
		"ankh_id": ankh_id,
		"ankh_name": display_name,
		"ankh_type": AnkhType.keys()[ankh_type],
		"zone_id": zone_id,
		"position": {
			"x": global_position.x,
			"y": global_position.y,
			"z": global_position.z
		},
		"respawn_time_modifier": respawn_time_modifier,
		"blessed_duration": blessed_duration,
		"is_in_pvp_zone": is_in_pvp_zone,
		"is_in_arena": is_in_arena,
		"can_bind": can_bind(player)
	}

## Check if position is within coverage
func is_within_coverage(position: Vector3) -> bool:
	return global_position.distance_to(position) <= coverage_radius

## Check if position is within activation range
func is_within_activation_range(position: Vector3) -> bool:
	return global_position.distance_to(position) <= activation_radius

## For arena: get remaining respawns for a team
func get_team_respawns(team_id: int) -> int:
	if respawn_count_limit <= 0:
		return -1  # Unlimited

	# Track respawns per team (simplified)
	# Initialize team respawn count if not set
	if not _team_respawn_counts.has(team_id):
		_team_respawn_counts[team_id] = respawn_count_limit
	return _team_respawn_counts[team_id]

## Decrement team respawn (arena mode)
func use_team_respawn(team_id: int) -> bool:
	if respawn_count_limit <= 0:
		return true  # Unlimited

	# Decrement team-specific counter
	if not _team_respawn_counts.has(team_id):
		_team_respawn_counts[team_id] = respawn_count_limit
	if _team_respawn_counts[team_id] > 0:
		_team_respawn_counts[team_id] -= 1
		return true
	return false
