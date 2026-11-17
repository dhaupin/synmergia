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
##      book, the bridge snapshots each fighter's six base stats and scales
##      them toward the highest fighter (contract power_scale_target). It
##      recomputes from that snapshot on every roster/reference change, so
##      the book can be RETUNED when a player joins or leaves, and RESTORES
##      the snapshot at bout end -- bout-local only, real stats never change.
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

func _on_damage_dealt(damager, target, amount, _skill) -> void:
	var did: String = _id_of(damager)
	var room = _room_holding(did)
	if room == null:
		return
	# The attacker LIVED this moment: AFK ledger + fire-and-you-lose-it.
	room.notify_action(did)
	# Trial-bout dummies: damage from a REAL entity onto an entity-less
	# dummy body resolves the dummy's death via its tuned presence.
	# The attacker's shield rule already ran; the dummy's death is the
	# room's own accounting (trial payout/credit follows bout end).
	var tid: String = _id_of(target)
	if tid == "" or not room.has_fighter(tid):
		return
	var f = room._fighters.get(tid)
	if f == null or not f.alive:
		return
	var hp: int = int(f.get("trial_health")) if "trial_health" in f else 0
	if hp <= 0:
		return  # real fighters die through entity death events, not here
	f.trial_health = hp - int(amount)
	if f.trial_health <= 0:
		room.report_death(tid, did)


# ---- 3. Power normalization ----------------------------------------------

func _apply_power(levels: Dictionary, instance_id: String) -> void:
	var room = _room_by_id(instance_id)
	if room == null:
		return
	if levels.is_empty():
		# The last fighter left: restore every session this room still holds.
		for fid in _power_sessions.keys():
			var orphan: Dictionary = _power_sessions[fid]
			if str(orphan.get("room_id", "")) == instance_id:
				_restore_session(fid, orphan)
		return
	# Reference: the bout's current highest level. A retune recomputes from
	# this book, so a 60 joining lifts the room and a 60 leaving lowers it.
	var reference: int = 1
	for fid in levels:
		reference = maxi(reference, int(levels[fid]))
	for fid in levels:
		var entity = _entity_for(fid)
		if entity == null or not ("stats" in entity):
			continue
		var level: int = int(levels[fid])
		var session: Dictionary = _power_sessions.get(fid, {})
		var baseline: Dictionary
		if not session.is_empty() and str(session.get("room_id", "")) == instance_id:
			# Retune: recompute from the PRE-bout snapshot, never from the
			# already-scaled stat block (which would compound every join).
			baseline = session.get("stats", {})
		else:
			baseline = _snapshot_stats(entity)
			_power_sessions[fid] = {"stats": baseline.duplicate(), "room_id": instance_id}
		var targets: Dictionary = Contract.power_scale_target(
			baseline, level, reference)
		for key in targets:
			entity.stats[key] = targets[key]
		# The battle is now normalized: CombatMath bypasses the open-world
		# level-power law and reads one shared level for hit/armor penalties.
		# Meta is bout-local and cleared with the stat snapshot below.
		entity.set_meta("arena_power_normalized", true)
		if entity.has_method("_calculate_max_resources"):
			entity._calculate_max_resources()
		var stored: Dictionary = _power_sessions.get(fid, {})
		stored["level"] = level
		stored["reference"] = reference
		_power_sessions[fid] = stored
	# A fighter that left the room's level book no longer belongs to this
	# bout's session: restore their real stats now instead of waiting for
	# an end that may never include them.
	for fid in _power_sessions.keys():
		var session: Dictionary = _power_sessions[fid]
		if str(session.get("room_id", "")) != instance_id:
			continue
		if levels.has(fid):
			continue
		_restore_session(fid, session)
	GameLog.info("ArenaCombatBridge: power book applied in %s (reference lvl %d)" % [instance_id, reference])


func _restore_powers(_winner_team: int, _stats: Dictionary, instance_id: String) -> void:
	for fid in _power_sessions.keys():
		var session: Dictionary = _power_sessions[fid]
		if str(session.get("room_id", "")) != instance_id:
			continue
		_restore_session(fid, session)

## Restore one fighter's pre-bout snapshot and clear the normalized mark.
func _restore_session(fid: String, session: Dictionary) -> void:
	var entity = _entity_for(fid)
	if entity != null and "stats" in entity:
		var snapshot: Dictionary = session.get("stats", {})
		for key in snapshot:
			entity.stats[key] = snapshot[key]
		if entity.has_meta("arena_power_normalized"):
			entity.remove_meta("arena_power_normalized")
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
