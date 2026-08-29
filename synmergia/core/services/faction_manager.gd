## FactionManager - Faction relationships and war management
## Handles faction reputation, war declarations, and guild alliances
extends Node

# All factions (faction_id -> Faction)
var _factions: Dictionary = {}

# Player reputation per faction (player_id -> {faction_id: reputation})
var _player_reputations: Dictionary = {}

# Active wars (faction1_id -> faction2_id -> war_data)
var _active_wars: Dictionary = {}

# Guild alliances (guild_id -> [faction_ids])
var _guild_alliances: Dictionary = {}

# War declaration cooldowns (faction_id -> timestamp)
var _war_cooldowns: Dictionary = {}

const WAR_COOLDOWN_HOURS: int = 24
const WAR_DECLARATION_COST: int = 10000  # Gold cost to declare war

signal faction_loaded(faction: Faction)
signal war_declared(faction1: Faction, faction2: Faction)
signal war_ended(faction1: Faction, faction2: Faction)
signal reputation_changed(player_id: String, faction_id: String, old_rep: int, new_rep: int)
signal alliance_formed(guild_id: String, faction: Faction)
signal alliance_broken(guild_id: String, faction: Faction)

func _ready() -> void:
	Logger.info("FactionManager: Ready")

## Load all factions from data
func load_factions() -> void:
	var data_service = DataService
	if not data_service:
		Logger.warn("FactionManager: DataService not available")
		return
	
	var faction_data_dict = data_service.get_all_factions()
	for faction_id in faction_data_dict:
		register_faction(faction_data_dict[faction_id])
	
	Logger.info("FactionManager: Loaded %d factions" % _factions.size())

## Register a faction
func register_faction(faction: Faction) -> void:
	if faction == null:
		return
	
	_factions[faction.id] = faction
	faction_loaded.emit(faction)
	Logger.debug("FactionManager: Registered faction %s" % faction.id)

## Get faction by ID
func get_faction(faction_id: String) -> Faction:
	return _factions.get(faction_id)

## Get all factions
func get_all_factions() -> Array[Faction]:
	return _factions.values()

## Get faction relation between two factions
func get_relation(faction1_id: String, faction2_id: String) -> Faction.Relation:
	var faction1 = _factions.get(faction1_id)
	var faction2 = _factions.get(faction2_id)
	
	if faction1 == null or faction2 == null:
		return Faction.Relation.NEUTRAL
	
	# Check if at war
	if is_at_war(faction1_id, faction2_id):
		return Faction.Relation.HOSTILE
	
	# Check explicit relations
	if faction1.relations.has(faction2_id):
		return faction1.relations[faction2_id]
	
	# Check species-based auto-alliance
	return faction1.get_relation(faction2_id)

## Check if two factions are at war
func is_at_war(faction1_id: String, faction2_id: String) -> bool:
	if not _active_wars.has(faction1_id):
		return false
	return _active_wars[faction1_id].has(faction2_id)

## Declare war between factions
func declare_war(faction1_id: String, faction2_id: String, attacker_id: String = "") -> bool:
	var faction1 = _factions.get(faction1_id)
	var faction2 = _factions.get(faction2_id)
	
	if faction1 == null or faction2 == null:
		Logger.warn("FactionManager: Cannot declare war, faction not found")
		return false
	
	# Check cooldowns
	if is_on_cooldown(faction1_id) or is_on_cooldown(faction2_id):
		Logger.info("FactionManager: War declaration on cooldown for %s or %s" % [faction1_id, faction2_id])
		return false
	
	# Already at war
	if is_at_war(faction1_id, faction2_id):
		Logger.info("FactionManager: %s and %s are already at war" % [faction1_id, faction2_id])
		return false
	
	# Set war data
	if not _active_wars.has(faction1_id):
		_active_wars[faction1_id] = {}
	
	_active_wars[faction1_id][faction2_id] = {
		"started_at": Time.get_ticks_msec(),
		"started_by": attacker_id,
		"declarations": 1
	}
	
	# Bidirectional (for easier lookup)
	if not _active_wars.has(faction2_id):
		_active_wars[faction2_id] = {}
	_active_wars[faction2_id][faction1_id] = {
		"started_at": Time.get_ticks_msec(),
		"started_by": attacker_id,
		"declarations": 1
	}
	
	# Set cooldown
	_war_cooldowns[faction1_id] = Time.get_ticks_msec() + (WAR_COOLDOWN_HOURS * 60 * 60 * 1000)
	
	# Update faction relations
	faction1.set_relation(faction2_id, Faction.Relation.HOSTILE)
	faction2.set_relation(faction1_id, Faction.Relation.HOSTILE)
	
	war_declared.emit(faction1, faction2)
	Logger.info("FactionManager: WAR declared between %s and %s" % [faction1_id, faction2_id])
	
	# Notify players
	var notification_service = NotificationService
	if notification_service:
		var message = "FACTION WAR: %s has declared war on %s!" % [faction1.display_name, faction2.display_name]
		notification_service.broadcast_all(
			message,
			NotificationService.NotificationType.FACTION,
			NotificationService.Priority.HIGH,
			NotificationService.DisplayLocation.CENTER_SCREEN,
			NotificationService.SoundType.WARNING,
			{"faction1": faction1_id, "faction2": faction2_id}
		)
	
	return true

## End war between factions
func end_war(faction1_id: String, faction2_id: String) -> bool:
	if not is_at_war(faction1_id, faction2_id):
		return false
	
	var faction1 = _factions.get(faction1_id)
	var faction2 = _factions.get(faction2_id)
	
	if _active_wars.has(faction1_id):
		_active_wars[faction1_id].erase(faction2_id)
	if _active_wars.has(faction2_id):
		_active_wars[faction2_id].erase(faction1_id)
	
	# Reset to neutral
	if faction1:
		faction1.set_relation(faction2_id, Faction.Relation.NEUTRAL)
	if faction2:
		faction2.set_relation(faction1_id, Faction.Relation.NEUTRAL)
	
	war_ended.emit(faction1, faction2)
	Logger.info("FactionManager: War ended between %s and %s" % [faction1_id, faction2_id])
	
	# Notify players
	var notification_service = NotificationService
	if notification_service and faction1 and faction2:
		var message = "FACTION PEACE: The war between %s and %s has ended." % [faction1.display_name, faction2.display_name]
		notification_service.broadcast_all(
			message,
			NotificationService.NotificationType.FACTION,
			NotificationService.Priority.NORMAL,
			NotificationService.DisplayLocation.CENTER_SCREEN,
			NotificationService.SoundType.NOTIFICATION,
			{"faction1": faction1_id, "faction2": faction2_id}
		)
	
	return true

## Check if faction is on war declaration cooldown
func is_on_cooldown(faction_id: String) -> bool:
	if not _war_cooldowns.has(faction_id):
		return false
	return Time.get_ticks_msec() < _war_cooldowns[faction_id]

## Get remaining cooldown for war declaration
func get_cooldown_remaining(faction_id: String) -> int:
	if not _war_cooldowns.has(faction_id):
		return 0
	var remaining = _war_cooldowns[faction_id] - Time.get_ticks_msec()
	return max(0, remaining)

## Get war data
func get_war_data(faction1_id: String, faction2_id: String) -> Dictionary:
	if not _active_wars.has(faction1_id):
		return {}
	return _active_wars[faction1_id].get(faction2_id, {})

## Get active wars for a faction
func get_faction_wars(faction_id: String) -> Array[Faction]:
	var wars: Array[Faction] = []
	if not _active_wars.has(faction_id):
		return wars
	
	for enemy_id in _active_wars[faction_id]:
		var enemy = _factions.get(enemy_id)
		if enemy:
			wars.append(enemy)
	return wars

## Player reputation management

## Get player reputation with a faction
func get_reputation(player_id: String, faction_id: String) -> int:
	if not _player_reputations.has(player_id):
		return 0
	return _player_reputations[player_id].get(faction_id, 0)

## Modify player reputation with a faction
func modify_reputation(player_id: String, faction_id: String, delta: int) -> void:
	if not _player_reputations.has(player_id):
		_player_reputations[player_id] = {}
	
	var old_rep = _player_reputations[player_id].get(faction_id, 0)
	var new_rep = clampi(old_rep + delta, -10000, 10000)
	_player_reputations[player_id][faction_id] = new_rep
	
	reputation_changed.emit(player_id, faction_id, old_rep, new_rep)
	Logger.debug("FactionManager: %s reputation with %s: %d -> %d" % [player_id, faction_id, old_rep, new_rep])

## Set player reputation with a faction
func set_reputation(player_id: String, faction_id: String, value: int) -> void:
	if not _player_reputations.has(player_id):
		_player_reputations[player_id] = {}
	
	var old_rep = _player_reputations[player_id].get(faction_id, 0)
	_player_reputations[player_id][faction_id] = clampi(value, -10000, 10000)
	
	reputation_changed.emit(player_id, faction_id, old_rep, value)

## Get reputation rank name
func get_reputation_rank(reputation: int) -> String:
	match reputation:
		var r if r >= 9000:
			return "Exalted"
		var r if r >= 6000:
			return "Revered"
		var r if r >= 3000:
			return "Honored"
		var r if r >= 1000:
			return "Friendly"
		var r if r >= 0:
			return "Neutral"
		var r if r >= -999:
			return "Unfriendly"
		var r if r >= -3000:
			return "Hostile"
		_:
			return "Hated"

## Guild alliances

## Form alliance between guild and faction
func form_alliance(guild_id: String, faction_id: String) -> bool:
	var faction = _factions.get(faction_id)
	if faction == null:
		return false
	
	if not _guild_alliances.has(guild_id):
		_guild_alliances[guild_id] = []
	
	if _guild_alliances[guild_id].has(faction_id):
		return false  # Already allied
	
	_guild_alliances[guild_id].append(faction_id)
	alliance_formed.emit(guild_id, faction)
	Logger.info("FactionManager: Guild %s allied with faction %s" % [guild_id, faction_id])
	return true

## Break alliance between guild and faction
func break_alliance(guild_id: String, faction_id: String) -> bool:
	if not _guild_alliances.has(guild_id):
		return false
	
	var faction = _factions.get(faction_id)
	if faction == null:
		return false
	
	_guild_alliances[guild_id].erase(faction_id)
	alliance_broken.emit(guild_id, faction)
	Logger.info("FactionManager: Guild %s broke alliance with faction %s" % [guild_id, faction_id])
	return true

## Get guild alliances
func get_guild_alliances(guild_id: String) -> Array[Faction]:
	var results: Array[Faction] = []
	if not _guild_alliances.has(guild_id):
		return results
	
	for faction_id in _guild_alliances[guild_id]:
		var faction = _factions.get(faction_id)
		if faction:
			results.append(faction)
	return results

## Check if guild is allied with faction
func is_guild_allied(guild_id: String, faction_id: String) -> bool:
	if not _guild_alliances.has(guild_id):
		return false
	return _guild_alliances[guild_id].has(faction_id)

## Can entity attack target based on faction/pvp rules
func can_attack(attacker: Entity, target: Entity) -> bool:
	# Same entity
	if attacker == target:
		return false
	
	# Same faction
	if attacker.faction_id != "" and attacker.faction_id == target.faction_id:
		return false
	
	# Check if at war
	if attacker.faction_id != "" and target.faction_id != "":
		if is_at_war(attacker.faction_id, target.faction_id):
			return true
	
	# Check zone-based PvP
	var zone_manager = ZoneManager
	if zone_manager:
		return zone_manager.can_pvp(attacker, target)
	
	return false
