## ArenaRoomService - the node-side registry of live bout rooms.
##
## InstanceService owns the DATA front door (capacity, contracts);
## this service owns the NODE map: which ArenaInstance is live for
## which instance id, and which fighter stands in which room. The
## ArenaCombatBridge resolves through here so CombatSystem never
## learns about arenas, and UI can find the room a fighter is in.
##
## Rooms self-register on tree entry (only when they carry a real
## instance id -- probe scratch rooms stay off the books) and leave
## it on tree exit. Autoload: NO class_name (AGENTS rule).
extends Node

signal room_opened(instance_id: String, room)
signal room_closed(instance_id: String, room)

var _rooms: Dictionary = {}        # instance_id -> ArenaInstance
var _fighter_rooms: Dictionary = {}  # fighter_id -> instance_id


func register_room(room) -> void:
	# NOTE: Object.get(key, default) lost its default arg in 4.7.2 --
	# a two-arg get() is an invalid call. Use the `in` operator.
	var iid: String = str(room.instance_id) if "instance_id" in room else ""
	if iid == "":
		return
	_rooms[iid] = room
	# Snapshot the roster now; fighters joining later re-index.
	for fid in room._fighters.keys():
		_fighter_rooms[str(fid)] = iid
	room.fighter_spawned.connect(_on_fighter_spawned.bind(iid))
	room_opened.emit(iid, room)
	GameLog.info("ArenaRoomService: room %s registered" % iid)


func unregister_room(room) -> void:
	var iid: String = str(room.instance_id) if "instance_id" in room else ""
	_rooms.erase(iid)
	for fid in _fighter_rooms.keys():
		if str(_fighter_rooms[fid]) == iid:
			_fighter_rooms.erase(fid)
	room_closed.emit(iid, room)


func _on_fighter_spawned(fighter_id: String, _team: int, iid: String) -> void:
	_fighter_rooms[str(fighter_id)] = iid


func room_by_id(instance_id: String):
	return _rooms.get(instance_id)


## Which room holds this fighter (null when none)?
func room_for_fighter(fighter_id: String):
	var iid: String = str(_fighter_rooms.get(fighter_id, ""))
	if iid == "":
		return null
	var room = _rooms.get(iid)
	if room == null or not is_instance_valid(room):
		_fighter_rooms.erase(fighter_id)
		return null
	return room
