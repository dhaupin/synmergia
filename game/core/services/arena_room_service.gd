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
	# S13 ROYALE: relay the fog wall to the HUD StormBar. The room
	# announces on bout_started (so the chip shows the calm before the
	# wall), phase advances, bites, and the close.
	if room.has_signal("bout_started") and not room.bout_started.is_connected(_on_room_bout_started):
		room.bout_started.connect(_on_room_bout_started.bind(iid, room))
	if room.has_signal("storm_phase_advanced") and not room.storm_phase_advanced.is_connected(_on_storm_phase):
		room.storm_phase_advanced.connect(_on_storm_phase.bind(iid))
	if room.has_signal("storm_damage_applied") and not room.storm_damage_applied.is_connected(_on_storm_bite):
		room.storm_damage_applied.connect(_on_storm_bite)
	if room.has_signal("bout_ended") and not room.bout_ended.is_connected(_on_room_bout_ended):
		room.bout_ended.connect(_on_room_bout_ended.bind(iid))
	room_opened.emit(iid, room)
	GameLog.info("ArenaRoomService: room %s registered" % iid)


## ---- S13 storm -> HUD relay (StormBar under HudLayer) ---------------------

func _storm_bar():
	var ml := Engine.get_main_loop()
	if ml == null or not (ml is SceneTree):
		return null
	var hud = (ml as SceneTree).root.get_node_or_null("HudLayer")
	if hud == null:
		return null
	return hud.get_node_or_null("StormBar")


func _on_room_bout_started(rules: Dictionary, iid: String, room) -> void:
	var bar = _storm_bar()
	if bar == null or room == null:
		return
	if int(rules.get("mode", -1)) != 2:  # Contract.InstanceMode.ROYALE
		return
	var half: float = 200.0
	if room.zone_data != null and "zone_radius" in room.zone_data:
		half = float(room.zone_data.zone_radius) * 0.5
	var phases: Array = rules.get("storm_phases", [])
	bar.show_storm(iid, phases.size(), half)


func _on_storm_phase(radius: float, phase_index: int, _iid: String) -> void:
	var bar = _storm_bar()
	if bar != null:
		bar.show_phase_advanced(radius, phase_index)


func _on_storm_bite(_fighter_id: String, _dps: float) -> void:
	var bar = _storm_bar()
	if bar != null:
		bar.show_fog_bite()


func unregister_room(room) -> void:
	var iid: String = str(room.instance_id) if "instance_id" in room else ""
	_rooms.erase(iid)
	for fid in _fighter_rooms.keys():
		if str(_fighter_rooms[fid]) == iid:
			_fighter_rooms.erase(fid)
	var bar = _storm_bar()
	if bar != null and bar.active_instance_id() == iid:
		bar.hide_storm()
	room_closed.emit(iid, room)


func _on_fighter_spawned(fighter_id: String, _team: int, iid: String) -> void:
	_fighter_rooms[str(fighter_id)] = iid



## The bout closed: lift the fog chip.
func _on_room_bout_ended(_winner_team: int, _stats: Dictionary, _iid: String) -> void:
	var bar = _storm_bar()
	if bar != null:
		bar.hide_storm()


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
