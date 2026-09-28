## BoutHostService - the S12 keystone: the RUNTIME that hosts a bout.
##
## Everything before this service is verified parts (lobby, rooms,
## bridge, teleports) with no production assembly. This service IS the
## assembly: on LobbyService.bout_assembled it spawns the arena room,
## seats every participant as a LINKED fighter (owner clarifier:
## players use their own class/gear/build -- no duel-set loaner forms;
## the seat binds the live entity by entity_id), arms the start timer
## against the zone's entry deadline, and on bout_ended pays out and
## tears the room down.
##
## The loop after tonight: stone -> queue -> assemble -> HOSTED ROOM
## -> fight -> payout -> home.
##
## Payout (first pass, honest bookkeeping): winners take XP + gold,
## losers take consolation XP, via PlayerManager's duck-typed
## progression surface. Depth (per-kill credit, titles, wagers) is
## parked in labs/prd-bout-host.md.
##
## Host book shape: instance_id -> {zone_id, room, participants,
## started}. The bout_ended connection binds the instance_id (signal
## arity stays 2; the book key rides the bind).
extends Node

const ArenaScene = preload("res://scenes/instances/arena_instance.gd")
const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind

## Payout: base XP for the winning team (per member), consolation for
## losers, plus gold to winners. Zone-scaled base lands later.
const WIN_XP: int = 120
const WIN_GOLD: int = 25
const CONSOLATION_XP: int = 40

# instance_id -> {zone_id, room, participants: Array, started: bool}
var _hosted: Dictionary = {}


func _ready() -> void:
	if LobbyService != null and LobbyService.has_signal("bout_assembled"):
		LobbyService.bout_assembled.connect(_on_bout_assembled)
		GameLog.info("BoutHostService: armed on bout_assembled")


## Host a bout: room + linked seats + start timer.
func _on_bout_assembled(zone_id: String, instance_id: String, team_a: Array, team_b: Array, stones: Dictionary = {}) -> void:
	if _hosted.has(instance_id):
		return
	var zone = _zone(zone_id)
	if zone == null:
		GameLog.warn("BoutHostService: unknown zone %s; assembly dropped" % zone_id)
		return
	var room = ArenaScene.new()
	room.zone_data = zone
	room.instance_id = instance_id
	# Room registers itself with ArenaRoomService on tree entry.
	get_tree().root.add_child(room)
	# Origin stones ride the assembly signal (the round-trip
	# addresses); the seat path below only fills absences, so players
	# who queued through LobbyUI (no stone) fall back to bind point.
	for fid in stones:
		room.origin_stones[str(fid)] = stones[fid]

	var participants: Array = []
	for i in range(team_a.size()):
		_seat(room, str(team_a[i]), 0, zone, participants)
	for i in range(team_b.size()):
		_seat(room, str(team_b[i]), 1, zone, participants)

	_hosted[instance_id] = {
		"zone_id": zone_id,
		"room": room,
		"participants": participants,
		"started": false,
	}
	if room.has_signal("bout_ended"):
		room.bout_ended.connect(_on_bout_ended.bind(instance_id))

	# Start after the zone's entry deadline (contract default 20 s).
	# Probe/tool seam: the room may cap the deadline (script-mode
	# tests cannot wait the real 60-90 s).
	var deadline: float = 2.0
	if zone != null and "instance_entry_deadline" in zone:
		deadline = maxf(float(zone.instance_entry_deadline), 2.0)
	if "start_deadline_override" in room and float(room.start_deadline_override) >= 0.0:
		deadline = minf(deadline, float(room.start_deadline_override))
	var timer := get_tree().create_timer(deadline)
	timer.timeout.connect(func(): _start_if_live(instance_id))


## Seat one linked fighter. Owner clarifier: the seat IS the player --
## no loaner loadout. Missing nodes still get seats (headless flow:
## the book exists; the scene swap owns bodies later).
func _seat(room, pid: String, team: int, zone, participants: Array) -> void:
	if room.has_fighter(pid):
		return
	room.spawn_fighter(pid, team)
	var level: int = 1
	var entity = _entity(pid)
	if entity != null and "level" in entity:
		level = int(entity.level)
	room.set_fighter_level(pid, level)
	var stone: Vector3 = room.origin_stones.get(pid, Vector3.ZERO)
	if stone == Vector3.ZERO:
		stone = _stone_for(pid, zone)
		room.origin_stones[pid] = stone
	participants.append(pid)


## Origin stone fallback: the zone's bind point (players who arrived
## through the LobbyUI queue rather than a stone still go home).
func _stone_for(pid: String, zone) -> Vector3:
	if zone != null and "bind_point" in zone:
		return zone.bind_point
	return Vector3.ZERO


func _start_if_live(instance_id: String) -> void:
	var book: Dictionary = _hosted.get(instance_id, {})
	if book.is_empty():
		return
	var room = book.get("room")
	if room == null or room.is_over() or room.is_started():
		return
	room.start_bout()
	book["started"] = true
	_announce_start(book, instance_id)


func _announce_start(book: Dictionary, instance_id: String) -> void:
	for pid in book.get("participants", []):
		_toast(str(pid), "The bout begins. Last team standing.", "bout_start:%s:%s" % [str(pid), instance_id])


## Bout closed: payout, release, teardown. instance_id arrives via
## the connect-time bind (signal args first, bound args after).
func _on_bout_ended(winner_team: int, _stats: Dictionary, instance_id: String) -> void:
	var book: Dictionary = _hosted.get(instance_id, {})
	if book.is_empty():
		return
	_hosted.erase(instance_id)
	_pay_out(winner_team, book)
	var room = book.get("room")
	if room != null:
		room.queue_free()
	GameLog.info("BoutHostService: bout %s closed (winner team %d)" % [instance_id, winner_team])


## Payout via the duck-typed progression surface. Never throws on
## missing ledgers (headless/probe flow has no PlayerManager book).
func _pay_out(winner_team: int, book: Dictionary) -> void:
	var room = book.get("room")
	if room == null:
		return
	for pid in book.get("participants", []):
		var sid: String = str(pid)
		var f = room._fighters.get(sid)
		if f == null:
			continue
		if int(f.team) == winner_team:
			_grant(sid, WIN_XP, WIN_GOLD)
			_toast(sid, "Victory. The marshal's purse opens. (+%d XP, +%d gold)" % [WIN_XP, WIN_GOLD], "bout_win:%s" % sid)
		else:
			_grant(sid, CONSOLATION_XP, 0)
			_toast(sid, "The bout is lost. The lesson is paid. (+%d XP)" % CONSOLATION_XP, "bout_lose:%s" % sid)


func _grant(pid: String, xp: int, gold: int) -> void:
	var pm = _player_manager()
	if pm == null:
		return
	if pm.has_method("add_experience"):
		pm.add_experience(xp)
	if gold > 0 and pm.has_method("add_gold"):
		pm.add_gold(gold)


# ---- Inspection surface (probe) ------------------------------------------

func hosted_bout_ids() -> Array:
	return _hosted.keys()


func is_hosting(instance_id: String) -> bool:
	return _hosted.has(instance_id)


# ---- Resolvers ------------------------------------------------------------

func _zone(zone_id: String):
	if ZoneManager == null:
		return null
	return ZoneManager.get_zone(zone_id)


func _entity(pid: String):
	if EntityService == null:
		return null
	return EntityService.get_entity(pid)


func _player_manager():
	var ml := Engine.get_main_loop()
	if ml == null or not (ml is SceneTree):
		return null
	return (ml as SceneTree).root.get_node_or_null("PlayerManager")


func _toast(player_id: String, message: String, dedupe_key: String) -> void:
	var notif = _notification_service()
	if notif == null:
		return
	notif.notify(
		NotifKind.ZONE_CHANGED,
		message,
		"BoutHostService",
		dedupe_key,
		{},
		player_id)


func _notification_service():
	var ml := Engine.get_main_loop()
	if ml == null or not (ml is SceneTree):
		return null
	return (ml as SceneTree).root.get_node_or_null("NotificationService")
