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

## zone_id -> true for zones with a live instance pair
## (base + live instance). Rebuilt in _ready from ZoneManager.
var _arena_zones := {}

## Optional direct seam for tests/tools: force the "live instance"
## that join_instance returns, keyed by base zone id. Real routing
## stays ZoneManager's (party instance reuse -> fresh create).
var _forced_instance := {}  # zone_id -> instance_id


func _ready() -> void:
	_rebuild_arena_registry()
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
