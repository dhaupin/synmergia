## BoutTeleportService - the scene-flow seam for the lobby loop.
##
## The mechanical completion of owner decision 2 (stones round-trip):
##   - bout_assembled  -> player entities are scattered into the bout's
##     team staging (the same contract primitive the room uses for its
##     fighters, so avatars and bodies never disagree about where the
##     fight starts).
##   - bout_return_requested -> every fighter is moved back to the
##     stone they queued at (win, loss, AFK kick -- the room declares,
##     this service moves).
##
## Position is authoritative; the GameManager scene swap (globe <->
## instance) remains its own flow item. When an entity node cannot be
## resolved (headless probes, cross-scene timing), the move is skipped
## and logged -- never half-applied.
##
## Autoload AFTER LobbyService + ArenaRoomService (listens to both).
## No class_name (AGENTS rule).
extends Node

const Contract = preload("res://core/schemas/instance_contract.gd")
const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind


func _ready() -> void:
	if LobbyService != null and LobbyService.has_signal("bout_assembled"):
		LobbyService.bout_assembled.connect(_on_bout_assembled)
	if ArenaRoomService != null and ArenaRoomService.has_signal("room_opened"):
		ArenaRoomService.room_opened.connect(_on_room_opened)
	GameLog.info("BoutTeleportService: listening (assembly in, returns home)")


func _on_room_opened(instance_id: String, room) -> void:
	if room.has_signal("bout_return_requested") and not room.bout_return_requested.is_connected(_on_return_map):
		room.bout_return_requested.connect(_on_return_map)


## Assembly: teleport each player entity to their team's staged ring.
func _on_bout_assembled(zone_id: String, instance_id: String, team_a: Array, team_b: Array) -> void:
	var zone = _zone(zone_id)
	var spawns: Array = []
	if zone != null and "spawn_points" in zone:
		spawns = zone.spawn_points
	_teleport_team(team_a, 0, spawns, instance_id)
	_teleport_team(team_b, 1, spawns, instance_id)


func _teleport_team(team_ids: Array, team_index: int, spawns: Array, instance_id: String) -> void:
	var center: Vector3 = Vector3.ZERO
	if team_index < spawns.size():
		center = spawns[team_index]
	for i in range(team_ids.size()):
		var pid: String = str(team_ids[i])
		var entity = _entity(pid)
		if entity == null or not (entity is Node3D):
			GameLog.warn("BoutTeleportService: no live node for %s (assembly %s); scene flow owns the swap" % [pid, instance_id])
			continue
		(entity as Node3D).global_position = Contract.scatter_spawn(center, i)
		_toast(pid, "The stone carries you. Fight well.", "bout_in:%s:%s" % [pid, instance_id])


## The room has closed: everyone goes home to their stone.
func _on_return_map(return_map: Dictionary) -> void:
	for fid in return_map:
		var pid: String = str(fid)
		var pos = return_map[fid]
		if not (pos is Vector3):
			continue
		var entity = _entity(pid)
		if entity == null or not (entity is Node3D):
			GameLog.warn("BoutTeleportService: no live node for %s (return); scene flow owns the swap" % pid)
			continue
		(entity as Node3D).global_position = pos
		_toast(pid, "The bout is over. The stone takes you back.", "bout_home:%s" % pid)


## Direct seam for tests/tools: apply a return map on demand.
func apply_return_map(return_map: Dictionary) -> void:
	_on_return_map(return_map)


# ---- Resolvers ------------------------------------------------------------

func _zone(zone_id: String):
	if ZoneManager == null:
		return null
	return ZoneManager.get_zone(zone_id)


func _entity(pid: String):
	if EntityService == null:
		return null
	return EntityService.get_entity(pid)


func _toast(player_id: String, message: String, dedupe_key: String) -> void:
	if NotificationService == null:
		return
	NotificationService.notify(
		NotifKind.ZONE_CHANGED,
		message,
		"BoutTeleportService",
		dedupe_key,
		{},
		player_id)
