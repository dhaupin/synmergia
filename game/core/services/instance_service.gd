## InstanceService - the S9 instances/lobby contract served per zone
## (prd-spherical-mvp.md S9). A thin CONTRACT layer over ZoneManager's
## instance machinery: ZoneManager owns the lifecycle underneath
## (create_instance / destroy_instance / capacity via can_enter_instance),
## this service owns the front door (which instance do I join, can my
## party fit, what do the physics promise inside).
##
## Contract (locked decision 3, instance_contract.gd): every instance
## is a PLANAR AABB world with vanilla -Y gravity, whatever the world
## shape knob says. Radial gravity is quarantined to the spherical
## ground path and NEVER reaches instanced zones.
##
## Autoload: name is the global identifier, so NO class_name here
## (AGENTS.md rule: autoload name and class_name must not collide).
extends Node

const InstanceContract = preload("res://core/schemas/instance_contract.gd")

signal lobby_state_changed(zone_id: String, instance_id: String, state: int)
signal instance_contract_changed(zone_id: String)
## S12 item 3: dungeon session lifecycle (the shared front door).
signal dungeon_session_opened(zone_id: String, instance_id: String, members: Array)
signal dungeon_return_requested(return_map: Dictionary)

## zone_id -> true for zones with a live instance pair
## (base + live instance). Rebuilt in _ready from ZoneManager.
var _arena_zones := {}

## Optional direct seam for tests/tools: force the "live instance"
## that join_instance returns, keyed by base zone id. Real routing
## stays ZoneManager's (party instance reuse -> fresh create).
var _forced_instance := {}  # zone_id -> instance_id

## S12 item 3: dungeon session books. instance_id -> {zone_id,
## members: Array, opened_at: float, activity: Dictionary}. The
## dwell sweep uses them for the AFK + time-limit backstops.
var _dungeon_sessions: Dictionary = {}
const DUNGEON_SWEEP_SECONDS: float = 5.0


func _ready() -> void:
	_rebuild_arena_registry()
	var sweep := Timer.new()
	sweep.wait_time = DUNGEON_SWEEP_SECONDS
	sweep.autostart = true
	sweep.timeout.connect(_sweep_dungeon_sessions)
	add_child(sweep)
	GameLog.info("InstanceService: Ready (%d instanced zone defs)" % _arena_zones.size())


## Zones that DECLARE themselves instanced (from ZoneData), plus any
## live instances registered in ZoneManager. Both keyed by base zone
## id for the contract API.
func _rebuild_arena_registry() -> void:
	_arena_zones.clear()
	if ZoneManager == null:
		return
	# Registered live instances (loaded from persistence or created
	# this boot) count as arena zones too.
	for instance_id in ZoneManager._instances:
		var data: Dictionary = ZoneManager._instances[instance_id]
		var base: String = str(data.get("base_zone_id", ""))
		if base != "":
			_arena_zones[base] = true
	# Zone definitions that declare is_instanced. Duck-typed: the
	# ZoneManager registry holds both .tres ZoneData and KV-restored
	# ones; a missing flag just means the zone does not self-declare.
	for zone_id in ZoneManager._zones:
		var zone = ZoneManager._zones[zone_id]
		if zone != null and "is_instanced" in zone and zone.is_instanced:
			_arena_zones[zone.id] = true


## The contract for one instanced zone (planar gravity + lobby rules).
## Capacity/deadline read from the ZoneData when the zone is
## registered; unknown zones still get the shared constants.
func get_contract(zone_id: String) -> Dictionary:
	var capacity := 0
	var deadline: float = InstanceContract.DEFAULT_ENTRY_DEADLINE
	if ZoneManager != null:
		var zone: ZoneData = ZoneManager.get_zone(zone_id)
		if zone != null:
			capacity = zone.instance_capacity
			deadline = InstanceContract.entry_deadline(zone)
	var contract: Dictionary = InstanceContract.gravity_contract()
	contract["capacity"] = capacity
	contract["entry_deadline"] = deadline
	contract["zone_id"] = zone_id
	return contract


## Join one instanced zone: reuses the party's live instance when one
## exists (ZoneManager's routing), otherwise creates a fresh one.
## capacity_ok=false means FULL -- the caller shows a queue/lobby UI;
## the join is NOT performed.
func join_instance(entity, zone_id: String, party_ids: Array[String] = []) -> Dictionary:
	if ZoneManager == null:
		return {"capacity_ok": false, "instance_id": ""}
	if not is_instanced_zone(zone_id):
		return {"capacity_ok": false, "instance_id": ""}
	var zone: ZoneData = ZoneManager.get_zone(zone_id)
	if zone == null or not zone.can_enter(entity):
		return {"capacity_ok": false, "instance_id": ""}

	var instance_id: String = _route_instance(zone_id, entity, party_ids)
	if instance_id == "":
		return {"capacity_ok": false, "instance_id": ""}

	var data: Dictionary = ZoneManager.get_instance(instance_id)
	var started: bool = _instance_started(data)
	if not InstanceContract.party_fits(data, 1 + party_ids.size(), started):
		return {"capacity_ok": false, "instance_id": instance_id}

	if not ZoneManager.add_to_instance(entity, instance_id):
		return {"capacity_ok": false, "instance_id": instance_id}

	var state: int = InstanceContract.lobby_state_for(data, started)
	lobby_state_changed.emit(zone_id, instance_id, state)
	GameLog.info("InstanceService: %s joined %s (instance %s, lobby %s)" % \
		[entity.entity_id, zone_id, instance_id, InstanceContract.LobbyState.keys()[state]])
	return {
		"capacity_ok": true,
		"instance_id": instance_id,
		"contract": get_contract(zone_id),
		"lobby_state": state,
	}


## Party join: same routing, but the whole party's size counts
## against capacity (the party stays together or nobody enters).
func join_party_instance(entity, zone_id: String, party_ids: Array[String]) -> Dictionary:
	if ZoneManager == null:
		return {"capacity_ok": false, "instance_id": ""}
	if not is_instanced_zone(zone_id):
		return {"capacity_ok": false, "instance_id": ""}
	var zone: ZoneData = ZoneManager.get_zone(zone_id)
	if zone == null or not zone.can_enter(entity):
		return {"capacity_ok": false, "instance_id": ""}

	var instance_id: String = _route_instance(zone_id, entity, party_ids)
	if instance_id == "":
		return {"capacity_ok": false, "instance_id": ""}

	var data: Dictionary = ZoneManager.get_instance(instance_id)
	var started: bool = _instance_started(data)
	if not InstanceContract.party_fits(data, 1 + party_ids.size(), started):
		return {"capacity_ok": false, "instance_id": instance_id}

	var joined_all := true
	if not ZoneManager.add_to_instance(entity, instance_id):
		joined_all = false
	for pid in party_ids:
		var member = _entity_by_id(pid)
		if member != null and not ZoneManager.add_to_instance(member, instance_id):
			joined_all = false
	if not joined_all:
		return {"capacity_ok": false, "instance_id": instance_id}

	var state: int = InstanceContract.lobby_state_for(data, started)
	lobby_state_changed.emit(zone_id, instance_id, state)
	return {
		"capacity_ok": true,
		"instance_id": instance_id,
		"contract": get_contract(zone_id),
		"lobby_state": state,
	}


## Current lobby state for a zone's live instance (or CLOSED).
func get_lobby_state(zone_id: String) -> int:
	var instance_id: String = live_instance_id(zone_id)
	if instance_id == "":
		return InstanceContract.LobbyState.CLOSED
	return InstanceContract.lobby_state_for( \
		ZoneManager.get_instance(instance_id), _instance_started( \
		ZoneManager.get_instance(instance_id)))


## The live instance id routed for a base zone ("" when none).
## Test seam: _forced_instance wins; otherwise first instance whose
## base_zone_id matches.
func live_instance_id(zone_id: String) -> String:
	if _forced_instance.has(zone_id):
		return str(_forced_instance[zone_id])
	if ZoneManager == null:
		return ""
	for instance_id in ZoneManager._instances:
		var data: Dictionary = ZoneManager._instances[instance_id]
		if str(data.get("base_zone_id", "")) == zone_id:
			return instance_id
	return ""


## True when the zone declares itself instanced (ZoneData flag) or
## has a live instance.
func is_instanced_zone(zone_id: String) -> bool:
	return _arena_zones.has(zone_id)


## ---- S12 item 3: the shared front door ---------------------------------

## Zone kind: "bout" (an arena; hosted by BoutHostService),
## "dungeon" (instanced horde scope; the horde loop sits on top),
## "open" (everything else). The discriminator is horde_config_id:
## dungeons declare one, arenas never do (ELIMINATION's mode value
## is 0, the schema default, so instance_mode cannot separate them).
func zone_kind(zone_id: String) -> String:
	if ZoneManager == null:
		return "open"
	var zone: ZoneData = ZoneManager.get_zone(zone_id)
	if zone == null or not is_instanced_zone(zone_id):
		return "open"
	if "horde_config_id" in zone and str(zone.horde_config_id) != "":
		return "dungeon"
	return "bout"


## The dungeon front door: contract checks (capacity, party fits,
## QoS attribution) + a SESSION BOOK with AFK/dwell backstops, then
## the same ZoneManager routing arenas use. HordeEventService keeps
## firing on zone entry -- the horde loop sits ON TOP of this door,
## not beside it. Returns the same shape as join_instance.
func join_dungeon(entity, zone_id: String, party_ids: Array[String] = []) -> Dictionary:
	if zone_kind(zone_id) != "dungeon":
		return {"capacity_ok": false, "instance_id": ""}
	var result: Dictionary = join_party_instance(entity, zone_id, party_ids) \
		if not party_ids.is_empty() else join_instance(entity, zone_id)
	if not bool(result.get("capacity_ok")):
		return result
	_open_dungeon_session(zone_id, str(result.get("instance_id", "")), entity, party_ids)
	return result


## The backstops (owner point: dungeon boss rooms must not become
## hotels). AFK: an idler past the zone's kick window goes home.
## Dwell: a party past the zone's time limit (instance_time_limit,
## 0 = uncapped) ALL go home to the bind point and the session closes.
func _sweep_dungeon_sessions() -> void:
	var now: float = Time.get_unix_time_from_system()
	for instance_id in _dungeon_sessions.keys():
		var session: Dictionary = _dungeon_sessions[instance_id]
		var zone: ZoneData = ZoneManager.get_zone(str(session.get("zone_id", ""))) if ZoneManager != null else null
		var members: Array = session.get("members", [])
		var kicked: Array = []
		# AFK backstop (contract default 90 s; instance_afk_kick override).
		var window: float = InstanceContract.afk_kick_seconds(zone)
		if window > 0.0:
			for m in members.duplicate():
				var mid: String = str(m)
				var idle: float = now - float(session.get("activity", {}).get(mid, now))
				if idle > window:
					kicked.append(mid)
		# Dwell backstop (zone instance_time_limit > 0 only).
		if zone != null and "instance_time_limit" in zone and float(zone.instance_time_limit) > 0.0:
			if now - float(session.get("opened_at", now)) >= float(zone.instance_time_limit):
				for m in members:
					var mid: String = str(m)
					if not kicked.has(mid):
						kicked.append(mid)
		if kicked.is_empty():
			continue
		_return_members(kicked, zone, instance_id)


## Return members to the zone bind point and book the departure.
## Also frees their seats in the ZoneManager instance roster -- the
## session book and the instance roster must agree, or a returned
## member's seat stays burned against capacity.
func _return_members(member_ids: Array, zone: ZoneData, instance_id: String) -> void:
	var session: Dictionary = _dungeon_sessions.get(instance_id, {})
	var members: Array = session.get("members", [])
	var bind: Vector3 = zone.bind_point if zone != null and "bind_point" in zone else Vector3.ZERO
	var return_map: Dictionary = {}
	for mid in member_ids:
		var sid: String = str(mid)
		return_map[sid] = bind
		members.erase(sid)
		var activity: Dictionary = session.get("activity", {})
		activity.erase(sid)
		var entity = _entity_by_id(sid)
		if entity != null and (entity is Node3D):
			(entity as Node3D).global_position = bind
		_remove_instance_seat(entity, instance_id)
	if members.is_empty():
		_dungeon_sessions.erase(instance_id)
	else:
		session["members"] = members
		_dungeon_sessions[instance_id] = session
	if not return_map.is_empty():
		dungeon_return_requested.emit(return_map)
		GameLog.info("InstanceService: dungeon %s returned %d member(s) to bind" % [instance_id, return_map.size()])


## Free the seat in the ZoneManager instance roster (ZoneManager has
## no removal API; the roster holds live entity refs).
func _remove_instance_seat(entity, instance_id: String) -> void:
	if ZoneManager == null or entity == null or instance_id == "":
		return
	var data: Dictionary = ZoneManager.get_instance(instance_id)
	if data.is_empty():
		return
	var players: Array = data.get("players", [])
	players.erase(entity)
	data["players"] = players


## Fight/room code pokes this for dungeon members (the AFK ledger).
func note_instance_activity(entity_id: String) -> void:
	for instance_id in _dungeon_sessions:
		var session: Dictionary = _dungeon_sessions[instance_id]
		var members: Array = session.get("members", [])
		if members.has(entity_id):
			session["activity"][entity_id] = Time.get_unix_time_from_system()


func _open_dungeon_session(zone_id: String, instance_id: String, entity, party_ids: Array[String]) -> void:
	if instance_id == "":
		return
	var session: Dictionary = _dungeon_sessions.get(instance_id, {})
	if session.is_empty():
		session = {
			"zone_id": zone_id,
			"members": [],
			"opened_at": Time.get_unix_time_from_system(),
			"activity": {},
		}
		_dungeon_sessions[instance_id] = session
	var now: float = Time.get_unix_time_from_system()
	var all: Array = [entity.entity_id] if entity != null and "entity_id" in entity else []
	for pid in party_ids:
		all.append(str(pid))
	for sid in all:
		if not session["members"].has(sid):
			session["members"].append(sid)
		session["activity"][sid] = now
	dungeon_session_opened.emit(zone_id, instance_id, session["members"])
	GameLog.info("InstanceService: dungeon session open in %s (%d member(s))" % [instance_id, session["members"].size()])


## Probe/tool seam: age a session so the sweep can act headlessly.
func _age_dungeon_session(instance_id: String, seconds: float, idle_seconds: float = -1.0) -> void:
	var session: Dictionary = _dungeon_sessions.get(instance_id, {})
	if session.is_empty():
		return
	session["opened_at"] = float(session.get("opened_at", 0.0)) - seconds
	if idle_seconds >= 0.0:
		var now: float = Time.get_unix_time_from_system()
		var activity: Dictionary = session.get("activity", {})
		for key in activity.keys():
			activity[key] = now - idle_seconds
		session["activity"] = activity
	_dungeon_sessions[instance_id] = session


## One-shot re-read of the registry (after external instance churn).
func refresh_registry() -> void:
	_rebuild_arena_registry()


## Force the routing target for a base zone (probe/tool seam).
func _force_instance(zone_id: String, instance_id: String) -> void:
	_forced_instance[zone_id] = instance_id
	_arena_zones[zone_id] = true


func _route_instance(zone_id: String, entity, party_ids: Array[String]) -> String:
	if _forced_instance.has(zone_id):
		return str(_forced_instance[zone_id])
	if ZoneManager == null:
		return ""
	if not party_ids.is_empty():
		var routed: String = ZoneManager.get_or_create_party_instance(zone_id, party_ids[0], party_ids)
		if routed != "":
			return routed
	# Solo path (S9 contract): open joins land in THE live instance
	# for the base zone; when it is full the join is refused (the
		# caller queues) -- never silently open a second instance.
	var live: String = live_instance_id(zone_id)
	if live != "":
		return live
	# QoS: instance creation is a rate-limited action (0.05/s per
	# owner in GameConfig). The requester is the owner of record so
	# a spamming player cannot churn instances; the limit was dead
	# code before this attribution (create_instance took no owner).
	var owner_id: String = str(entity.entity_id) if entity != null and "entity_id" in entity else ""
	if owner_id != "" and QoSService != null and not QoSService.rate_limit(owner_id, "instance"):
		GameLog.warn("InstanceService: instance creation rate-limited for %s" % owner_id)
		return ""
	return ZoneManager.create_instance(zone_id)


func _instance_started(data: Dictionary) -> bool:
	return bool(data.get("started", false))


func _entity_by_id(pid: String):
	if EntityService == null:
		return null
	return EntityService.get_entity(pid)
