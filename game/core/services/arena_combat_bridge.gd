## ArenaCombatBridge - the S11 combat seam between the open world's
## CombatSystem and the instanced bout rooms (arena_instance.gd).
##
## Three duties, all from locked owner decisions:
##   1. DEATHS route into the right room: CombatSystem.entity_died is
##      forwarded to report_death(victim, killer) for the bout that
##      holds both fighters.
##   2. SELF-INITIATED actions break the spawn shield (fire-and-you-
##      lose-it) and refresh AFK activity: skill casts and damage both
##      count as life; RECEIVED damage never breaks the shield and
##      never registers activity (being hit is not playing).
##   3. POWER NORMALIZATION enforcement: when a room reports its level
##      book, the bridge snapshots each fighter's six base stats,
##      scales them toward the capped normalized level (contract
##      power_scale_target), and RESTORES the snapshot at bout end --
##      bout-local only, real stats never change.
##
## Bridge-only autoload: no class_name (AGENTS rule). Resolves rooms
## through ArenaRoomService's instance_id -> room map so CombatSystem
## never learns about arenas.
extends Node

const Contract = preload("res://core/schemas/instance_contract.gd")

## fighter_id -> {stats: Dictionary snapshot, room_id: String}
var _power_sessions: Dictionary = {}


func _ready() -> void:
	if CombatSystem != null:
		CombatSystem.damage_dealt.connect(_on_damage_dealt)
		CombatSystem.entity_died.connect(_on_entity_died)
		GameLog.info("ArenaCombatBridge: wired to CombatSystem")
	if ArenaRoomService != null and ArenaRoomService.has_signal("room_opened"):
		ArenaRoomService.room_opened.connect(_on_room_opened)
		ArenaRoomService.room_closed.connect(_on_room_closed)
		GameLog.info("ArenaCombatBridge: wired to ArenaRoomService")


# ---- Room registry -------------------------------------------------------

func _on_room_opened(instance_id: String, room) -> void:
	# The room tells the bridge its roster's real levels; the bridge
	# answers with the power book on bout start.
	if room.has_signal("power_reference_ready"):
		room.power_reference_ready.connect(_apply_power.bind(instance_id))
	if room.has_signal("bout_ended"):
		room.bout_ended.connect(_restore_powers.bind(instance_id))


func _on_room_closed(instance_id: String, _room) -> void:
	_restore_powers(0, {}, instance_id)


## Bridge-facing lookup: which room holds this fighter?
func room_for_fighter(fighter_id: String):
	if ArenaRoomService == null:
		return null
	return ArenaRoomService.room_for_fighter(fighter_id)


# ---- 1. Deaths -----------------------------------------------------------

func _on_entity_died(victim, killer) -> void:
	var vid: String = _id_of(victim)
	var kid: String = _id_of(killer)
	var room = _room_holding(vid)
	if room == null:
		return
	room.report_death(vid, kid)


# ---- 2. Actions: shield break + activity ---------------------------------

func _on_damage_dealt(damager, _target, _amount, _skill) -> void:
	var did: String = _id_of(damager)
	var room = _room_holding(did)
	if room == null:
		return
	# The attacker LIVED this moment: AFK ledger + fire-and-you-lose-it.
	room.notify_action(did)


# ---- 3. Power normalization ----------------------------------------------

func _apply_power(levels: Dictionary, instance_id: String) -> void:
	if levels.is_empty():
		return
	var room = _room_by_id(instance_id)
	if room == null:
		return
	# Reference: the bout's max level.
	var reference: int = 1
	for fid in levels:
		reference = maxi(reference, int(levels[fid]))
	for fid in levels:
		var entity = _entity_for(fid)
		if entity == null or not ("stats" in entity):
			continue
		var level: int = int(levels[fid])
		var snapshot: Dictionary = _snapshot_stats(entity)
		if _power_sessions.has(fid):
			continue  # already scaled this bout; never double-apply
		var targets: Dictionary = Contract.power_scale_target( \
			entity.stats, level, reference, 2.0)
		for key in targets:
			entity.stats[key] = targets[key]
		if entity.has_method("_calculate_max_resources"):
			entity._calculate_max_resources()
		_power_sessions[fid] = {"stats": snapshot, "room_id": instance_id}
	GameLog.info("ArenaCombatBridge: power book applied in %s (reference lvl %d)" % [instance_id, reference])


func _restore_powers(_winner_team: int, _stats: Dictionary, instance_id: String) -> void:
	var room = _room_by_id(instance_id)
	for fid in _power_sessions.keys():
		var session: Dictionary = _power_sessions[fid]
		if str(session.get("room_id", "")) != instance_id:
			continue
		var entity = _entity_for(fid)
		if entity != null and "stats" in entity:
			var snapshot: Dictionary = session.get("stats", {})
			for key in snapshot:
				entity.stats[key] = snapshot[key]
			if entity.has_method("_calculate_max_resources"):
				entity._calculate_max_resources()
		_power_sessions.erase(fid)


# ---- Resolvers ------------------------------------------------------------

## The fighter book key for a combat participant. CombatSystem events
## carry live entities (entity_id); bout fighter bodies (ArenaFighter)
## carry fighter_id -- same string in the real flow, and the fallback
## keeps the bridge honest if events ever arrive fighter-side.
func _id_of(entity) -> String:
	if entity == null:
		return ""
	if "entity_id" in entity:
		return str(entity.entity_id)
	if "fighter_id" in entity:
		return str(entity.fighter_id)
	return ""


func _room_holding(fighter_id: String):
	var svc = _room_service()
	if svc == null:
		return null
	return svc.room_for_fighter(fighter_id)


func _room_by_id(instance_id: String):
	var svc = _room_service()
	if svc == null:
		return null
	return svc.room_by_id(instance_id)


func _room_service():
	var ml := Engine.get_main_loop()
	if ml == null or not (ml is SceneTree):
		return null
	return (ml as SceneTree).root.get_node_or_null("ArenaRoomService")


func _entity_for(fighter_id: String):
	if EntityService == null:
		return null
	return EntityService.get_entity(fighter_id)


func _snapshot_stats(entity) -> Dictionary:
	var snap: Dictionary = {}
	for key in Contract.POWER_SCALED_STATS:
		snap[key] = int(entity.stats.get(key, 10))
	return snap
