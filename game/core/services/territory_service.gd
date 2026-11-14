## TerritoryService - owns the territory registry and its live contest state.
##
## TerritoryData groups zones; this service answers the questions every
## other system asks:
##   - which territory is this zone in? (map, hordes, bosses, events)
##   - who controls it and is it contested? (map, combat rules, UI)
##   - claim / contest / resolve it (guilds, faction wars)
##
## No class_name: the autoload name is the global identifier (AGENTS.md).
extends Node

const TerritoryData = preload("res://core/schemas/territory_data.gd")
const DictStore = preload("res://adapters/persistence/dict_store.gd")

## Runtime state survives a reboot: the authored controller is the base
## state, and a saved overlay re-applies claims/wars on top of it.
const _kv_prefix := "territory:state:"

var _territories: Dictionary = {}   # territory_id -> TerritoryData
var _zone_index: Dictionary = {}    # zone_id -> territory_id

signal territory_changed(territory_id: String, context: Dictionary)


func _ready() -> void:
	reload()
	GameLog.info("TerritoryService: Ready (%d territories)" % _territories.size())


## Rebuild the registry from DataService. Safe to call after data reloads.
func reload() -> void:
	_territories.clear()
	_zone_index.clear()
	var data_service = _data_service()
	if data_service == null:
		return
	if data_service.has_method("load_territories"):
		data_service.load_territories()
	for territory in data_service.get_all_territories():
		register_territory(territory)
	_load_runtime_state()


## Register one territory. A zone may not belong to two territories; the
## second registration is refused loudly instead of silently shadowing.
func register_territory(territory) -> bool:
	if territory == null or str(territory.id) == "":
		return false
	var tid: String = str(territory.id)
	if _territories.has(tid):
		GameLog.warn("TerritoryService: duplicate territory id %s" % tid)
		return false
	for zone_id in territory.zone_ids:
		var zid: String = str(zone_id)
		if _zone_index.has(zid):
			GameLog.warn("TerritoryService: zone %s already belongs to %s" % [zid, _zone_index[zid]])
			return false
	for zone_id in territory.zone_ids:
		_zone_index[str(zone_id)] = tid
	# DataService caches resources. Keep the authored catalog immutable and
	# mutate a deep copy; otherwise a reload reads back the already-claimed
	# object and the "authored controller" is gone for the process lifetime.
	_territories[tid] = territory.duplicate(true)
	return true


func get_territory(territory_id: String):
	return _territories.get(territory_id)


func get_all_territories() -> Array:
	return _territories.values()


## The territory containing a zone, or null.
func for_zone(zone_id: String):
	var tid: String = str(_zone_index.get(zone_id, ""))
	return _territories.get(tid)


func territories_for_faction(faction_id: String) -> Array:
	return _territories_for(TerritoryData.Controller.FACTION, faction_id)


func territories_for_guild(guild_id: String) -> Array:
	return _territories_for(TerritoryData.Controller.GUILD, guild_id)


func _territories_for(kind: int, owner_id: String) -> Array:
	var out: Array = []
	for territory in _territories.values():
		if int(territory.controller) == kind and str(territory.controller_id) == owner_id:
			out.append(territory)
	return out


## Short label for a zone, for map tooltips. Falls back to `fallback` when
## the zone has no territory, so callers never lose the zone name.
func zone_label(zone_id: String, fallback: String) -> String:
	var territory = for_zone(zone_id)
	if territory == null:
		return fallback
	var owner: String = _controller_name(territory)
	if territory.is_contested():
		return "%s - %s (contested)" % [territory.display_name, owner]
	if owner == "":
		return "%s - unclaimed" % territory.display_name
	return "%s - %s" % [territory.display_name, owner]


## Claim a territory for a faction or guild. The caller owns the permission
## check; this is the state transition only. A stronger claim takes control.
func claim(territory_id: String, kind: int, owner_id: String, influence: int = 50) -> bool:
	var territory = _territories.get(territory_id)
	if territory == null or owner_id == "":
		return false
	if kind != TerritoryData.Controller.FACTION and kind != TerritoryData.Controller.GUILD:
		return false
	_upsert_claimant(territory, kind, owner_id, influence)
	var current: int = int(territory.controller)
	if current == TerritoryData.Controller.NONE or influence >= _influence_of(territory, current, str(territory.controller_id)):
		territory.controller = kind
		territory.controller_id = owner_id
	_emit(territory)
	return true


## Mark a territory as the stake of a live faction war and seat both
## claimants. The war itself lives in FactionManager.
func contest(territory_id: String, war_id: String, faction_a: String, faction_b: String) -> bool:
	var territory = _territories.get(territory_id)
	if territory == null or war_id == "":
		return false
	territory.active_war_id = war_id
	_upsert_claimant(territory, TerritoryData.Controller.FACTION, faction_a, 0)
	_upsert_claimant(territory, TerritoryData.Controller.FACTION, faction_b, 0)
	_emit(territory)
	return true


## Resolve one territory's war. The winner gets the controller seat; with no
## winner the strongest claimant keeps it.
func resolve_war(territory_id: String, winner_kind: int = -1, winner_id: String = "") -> bool:
	var territory = _territories.get(territory_id)
	if territory == null:
		return false
	territory.active_war_id = ""
	if winner_kind != -1 and winner_id != "":
		_upsert_claimant(territory, winner_kind, winner_id, 100)
		territory.controller = winner_kind
		territory.controller_id = winner_id
	else:
		_resolve_by_influence(territory)
	_keep_only_controller_claim(territory)
	_emit(territory)
	return true


## End every war between two factions and resolve each affected territory.
func resolve_war_between(faction_a: String, faction_b: String) -> int:
	var resolved: int = 0
	for territory in _territories.values():
		if str(territory.active_war_id) == "":
			continue
		var claimant_ids: Array = []
		for claim in territory.claimants:
			claimant_ids.append(str(claim.get("id", "")))
		if claimant_ids.has(faction_a) and claimant_ids.has(faction_b):
			territory.active_war_id = ""
			_resolve_by_influence(territory)
			_keep_only_controller_claim(territory)
			_emit(territory)
			resolved += 1
	return resolved


## Drop every claim and the controller (unclaim).
func release(territory_id: String) -> bool:
	var territory = _territories.get(territory_id)
	if territory == null:
		return false
	territory.claimants.clear()
	territory.controller = TerritoryData.Controller.NONE
	territory.controller_id = ""
	territory.active_war_id = ""
	_emit(territory)
	return true


func _upsert_claimant(territory, kind: int, owner_id: String, influence: int) -> void:
	for claim in territory.claimants:
		if int(claim.get("kind", -1)) == kind and str(claim.get("id", "")) == owner_id:
			claim["influence"] = max(int(claim.get("influence", 0)), influence)
			return
	territory.claimants.append({
		"kind": kind,
		"id": owner_id,
		"influence": influence,
		"since": Time.get_unix_time_from_system()
	})


func _influence_of(territory, kind: int, owner_id: String) -> int:
	for claim in territory.claimants:
		if int(claim.get("kind", -1)) == kind and str(claim.get("id", "")) == owner_id:
			return int(claim.get("influence", 0))
	return -1


## After a war, only the winner's claim survives. A peace is not a frozen
## two-claim cold war; it is a resolved contest with one holder.
func _keep_only_controller_claim(territory) -> void:
	var kept: Array[Dictionary] = []
	for claim in territory.claimants:
		if int(claim.get("kind", -1)) == int(territory.controller) \
				and str(claim.get("id", "")) == str(territory.controller_id):
			kept.append(claim)
	territory.claimants = kept


func _resolve_by_influence(territory) -> void:
	var best_kind: int = TerritoryData.Controller.NONE
	var best_id: String = ""
	var best: int = -1
	for claim in territory.claimants:
		var influence: int = int(claim.get("influence", 0))
		if influence > best:
			best = influence
			best_kind = int(claim.get("kind", TerritoryData.Controller.NONE))
			best_id = str(claim.get("id", ""))
	territory.controller = best_kind
	territory.controller_id = best_id


func _controller_name(territory) -> String:
	if territory.controller == TerritoryData.Controller.FACTION:
		var data_service = _data_service()
		if data_service and data_service.has_method("get_faction"):
			var faction = data_service.get_faction(str(territory.controller_id))
			if faction:
				return str(faction.display_name)
		return str(territory.controller_id)
	if territory.controller == TerritoryData.Controller.GUILD:
		return str(territory.controller_id)
	return ""


func _emit(territory) -> void:
	_persist(territory)
	territory_changed.emit(str(territory.id), territory.to_context())


## Drop the persisted overlay (all territories, or one id). Tests use this
## to leave no runtime state behind; operators can use it to reset a shard.
func clear_persisted(territory_id: String = "") -> void:
	var store := DictStore.new()
	if territory_id != "":
		store.erase(_kv_prefix + territory_id)
		return
	for key in store.all_keys():
		if str(key).begins_with(_kv_prefix):
			store.erase(str(key))


func _persist(territory) -> void:
	var store := DictStore.new()
	store.set_kv(_kv_prefix + str(territory.id), {
		"controller": int(territory.controller),
		"controller_id": str(territory.controller_id),
		"claimants": territory.claimants.duplicate(true),
		"active_war_id": str(territory.active_war_id)
	})


## Apply the saved overlay after the authored data has loaded. Unknown ids
## are ignored (a deleted territory leaves no phantom), and the stored claim
## array is rebuilt as Array[Dictionary] before assignment.
func _load_runtime_state() -> void:
	var store := DictStore.new()
	for key in store.all_keys():
		var ks: String = str(key)
		if not ks.begins_with(_kv_prefix):
			continue
		var territory = _territories.get(ks.substr(_kv_prefix.length()))
		if territory == null:
			continue
		var data = store.get_kv(ks, {})
		if not data is Dictionary:
			continue
		var kind: int = int(data.get("controller", TerritoryData.Controller.NONE))
		if kind >= TerritoryData.Controller.NONE and kind <= TerritoryData.Controller.GUILD:
			territory.controller = kind
		territory.controller_id = str(data.get("controller_id", ""))
		territory.active_war_id = str(data.get("active_war_id", ""))
		var claims: Array[Dictionary] = []
		for claim in data.get("claimants", []):
			if claim is Dictionary:
				claims.append(claim)
		territory.claimants = claims


func _data_service():
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(NodePath("DataService"))

