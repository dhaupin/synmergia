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

# Frame-level notification dispatch (see synmergia/core/notifications/).
# Faction events broadcast server-wide (war/peace) or target a single
# player (rep changes). Dedupe is keyed on (kind, target, identifier)
# so rep ticks during a long quest don't flood the toast panel.
const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind

func _emit_faction(
	kind: int,
	message: String,
	dedupe_key: String,
	data: Dictionary,
	recipient: String = ""
) -> void:
	if not is_instance_valid(NotificationService):
		return
	# notify() handles both broadcast and per-player routing internally.
	# A blank recipient is broadcast; a real recipient is targeted.
	NotificationService.notify(
		kind,
		message,
		"FactionManager",
		dedupe_key,
		data,
		recipient
	)

func _ready() -> void:
	GameLog.info("FactionManager: Ready")

## Load all factions from data
func load_factions() -> void:
	var data_service = DataService
	if not data_service:
		GameLog.warn("FactionManager: DataService not available")
		return
	
	var faction_data_dict = data_service.get_all_factions()
	for faction_id in faction_data_dict:
		register_faction(faction_data_dict[faction_id])
	
	GameLog.info("FactionManager: Loaded %d factions" % _factions.size())

## Register a faction
func register_faction(faction: Faction) -> void:
	if faction == null:
		return
	
	_factions[faction.id] = faction
	faction_loaded.emit(faction)
	GameLog.debug("FactionManager: Registered faction %s" % faction.id)

## Get faction by ID
func get_faction(faction_id: String) -> Faction:
	return _factions.get(faction_id)

## Get all factions
func get_all_factions() -> Array:
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
		GameLog.warn("FactionManager: Cannot declare war, faction not found")
		return false
	
	# Check cooldowns
	if is_on_cooldown(faction1_id) or is_on_cooldown(faction2_id):
		GameLog.info("FactionManager: War declaration on cooldown for %s or %s" % [faction1_id, faction2_id])
		return false
	
	# Already at war
	if is_at_war(faction1_id, faction2_id):
		GameLog.info("FactionManager: %s and %s are already at war" % [faction1_id, faction2_id])
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
	GameLog.info("FactionManager: WAR declared between %s and %s" % [faction1_id, faction2_id])

	# Frame-level toast. Dedupe on the war pair so a re-emit during the same
	# 5s window (e.g. multiple systems reacting to the same event) collapses
	# to one toast.
	_emit_faction(
		NotifKind.FACTION_CHANGED,
		"FACTION WAR: %s has declared war on %s!" % [faction1.display_name, faction2.display_name],
		"war:%s:%s" % [faction1_id, faction2_id],
		{"faction1": faction1_id, "faction2": faction2_id, "attacker_id": attacker_id, "event": "war_declared"}
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
	GameLog.info("FactionManager: War ended between %s and %s" % [faction1_id, faction2_id])

	# Frame-level toast.
	_emit_faction(
		NotifKind.FACTION_CHANGED,
		"FACTION PEACE: The war between %s and %s has ended." % [faction1.display_name, faction2.display_name],
		"peace:%s:%s" % [faction1_id, faction2_id],
		{"faction1": faction1_id, "faction2": faction2_id, "event": "war_ended"}
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
func get_faction_wars(faction_id: String) -> Array:
	var wars: Array = []
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
	GameLog.debug("FactionManager: %s reputation with %s: %d -> %d" % [player_id, faction_id, old_rep, new_rep])

	# Frame-level toast on rank transitions only. A quest chain can tick
	# +5 rep a hundred times; only the moments where the player crosses
	# into a new rank (Neutral → Friendly, Friendly → Honored, etc.) are
	# interesting. Dedupe on the rank so a quick double-cross doesn't
	# double-toast.
	var old_rank: String = get_reputation_rank(old_rep)
	var new_rank: String = get_reputation_rank(new_rep)
	if old_rank != new_rank:
		_emit_faction(
			NotifKind.FACTION_REP_CHANGED,
			"Reputation with %s: %s → %s" % [faction_id, old_rank, new_rank],
			"rep_rank:%s:%s" % [player_id, new_rank],
			{"faction_id": faction_id, "old_rank": old_rank, "new_rank": new_rank, "old_rep": old_rep, "new_rep": new_rep, "delta": delta},
			player_id
		)

## Set player reputation with a faction
func set_reputation(player_id: String, faction_id: String, value: int) -> void:
	if not _player_reputations.has(player_id):
		_player_reputations[player_id] = {}
	
	var old_rep = _player_reputations[player_id].get(faction_id, 0)
	_player_reputations[player_id][faction_id] = clampi(value, -10000, 10000)
	
	reputation_changed.emit(player_id, faction_id, old_rep, value)

## Get reputation rank name
func get_reputation_rank(reputation: int) -> String:
	if reputation >= 9000:
		return "Exalted"
	elif reputation >= 6000:
		return "Revered"
	elif reputation >= 3000:
		return "Honored"
	elif reputation >= 1000:
		return "Friendly"
	elif reputation >= 0:
		return "Neutral"
	elif reputation >= -999:
		return "Unfriendly"
	elif reputation >= -3000:
		return "Hostile"
	else:
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
	# Frame-level broadcast: alliances affect the whole guild, so the
	# toast is server-wide. Dedupe on the alliance pair.
	_emit_faction(
		NotifKind.FACTION_CHANGED,
		"Guild %s formed an alliance with %s" % [guild_id, faction.display_name],
		"alliance_formed:%s:%s" % [guild_id, faction_id],
		{"guild_id": guild_id, "faction_id": faction_id, "event": "alliance_formed"}
	)
	GameLog.info("FactionManager: Guild %s allied with faction %s" % [guild_id, faction_id])
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
	_emit_faction(
		NotifKind.FACTION_CHANGED,
		"Guild %s broke its alliance with %s" % [guild_id, faction.display_name],
		"alliance_broken:%s:%s" % [guild_id, faction_id],
		{"guild_id": guild_id, "faction_id": faction_id, "event": "alliance_broken"}
	)
	GameLog.info("FactionManager: Guild %s broke alliance with faction %s" % [guild_id, faction_id])
	return true

## Get guild alliances
func get_guild_alliances(guild_id: String) -> Array:
	var results: Array = []
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
func can_attack(attacker, target) -> bool:
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
