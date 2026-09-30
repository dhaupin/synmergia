# ArenaGateway - the S10 world-side trigger, now the S11 queue stone.
#
# An Area3D the player walks into on the globe; entering fires the S9
# front door (InstanceService.join_instance / join_party_instance) and
# surfaces the lobby moment (OPEN/FULL + deadline) through the typed
# notification pipeline. Mode-agnostic: the gateway never reads the
# bout mode; the instance room and lobby UI do.
#
# S11 owner decision: stones in towns are the lobby's doors -- queue
# here (LobbyService.join_queue with this stone as origin), the bout
# teleports you in at assembly, and every ending (win, loss, AFK kick)
# returns you to this stone. Round trip, no stranding.
#
# Data-driven: the zone id comes from `zone_id` (set in code by
# globe_world when it builds the gateway; later a .tres if gateway
# content grows). Party play is all-or-nothing via party_fits inside
# the service; solo players just join.
#
# Conventions: code-built children (globe_world pattern), no
# class_name, tabs, ASCII only.
extends Area3D

const Contract = preload("res://core/schemas/instance_contract.gd")
const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind

## ZoneData id this gateway leads to (e.g. zone_arena_coliseum).
@export var zone_id: String = "zone_arena_coliseum"
## S11: when true, entering queues via LobbyService (assembly joins
## everyone at once) instead of the direct S10 join path.
@export var queue_mode: bool = false

## Set true when the join path accepted the entity (dedupe: do not
## re-fire while the entity stands in the volume).
var _entered: Dictionary = {}  # entity_id -> true

signal join_requested(entity, zone_id: String)
signal join_result(entity, result: Dictionary)

## The stone is a round trip: results and bout returns land back here.
## Read by the scene flow after a bout (bout_return_requested) to know
## where a returning fighter belongs.
func stone_position_for(entity) -> Vector3:
	return global_position + Vector3(0, 1.5, 2.5)

func _init() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 1
	# Bigger than a doorway; a fighter cannot miss the sand line.
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10, 6, 4)
	shape.shape = box
	shape.position = Vector3(0, 3, 0)
	add_child(shape)

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

## The join path fires once per entity per entry (re-entering after a
## full exit re-arms the trigger; standing inside does not spam).
func _on_body_entered(body: Node3D) -> void:
	if body == null or not ("entity_id" in body):
		return
	var eid: String = str(body.entity_id)
	if eid.is_empty() or _entered.has(eid):
		return
	_entered[eid] = true
	join_requested.emit(body, zone_id)

	# S11 stone path: entering a queue stone enqueues you for the
	# zone's bout; assembly (LobbyService.try_assemble) does the join.
	if queue_mode:
		_enqueue_at_stone(body)
		return

	var isvc = _instance_service()
	if isvc == null:
		return
	# Party-aware: members of a party join through the party path so
	# the whole party counts against capacity and stays together.
	var party_ids := _party_ids_for(body)
	var result: Dictionary
	if party_ids.is_empty():
		result = isvc.join_instance(body, zone_id)
	else:
		result = isvc.join_party_instance(body, zone_id, party_ids)
	# The stone remembers who it sent: origin_stones in the result is
	# the round-trip address (bout end + AFK kicks land back here).
	if bool(result.get("capacity_ok")):
		result["origin_stone"] = stone_position_for(body)
		_stamp_origin_stones(isvc, result["instance_id"], body.entity_id, result["origin_stone"])
	_join_toasted(body, result)
	join_result.emit(body, result)

## Leaving the volume re-arms the trigger for a future entry.
func _on_body_exited(body: Node3D) -> void:
	if body == null or not ("entity_id" in body):
		return
	_entered.erase(str(body.entity_id))

## Lobby moment: OPEN/FULL + entry deadline surfaced as a typed toast.
func _join_toasted(entity, result: Dictionary) -> void:
	var notif = _notification_service()
	if notif == null:
		return
	var eid: String = str(entity.entity_id)
	var iid: String = str(result.get("instance_id", ""))
	if not bool(result.get("capacity_ok")):
		# FULL or blocked: the lobby door is closed for now.
		notif.notify(
			NotifKind.ZONE_CHANGED,
			"The arena is full -- the bout has begun. Wait for the next.",
			"ArenaGateway",
			"arena_full:%s:%s" % [eid, iid],
			{},
			eid)
		return
	var state: int = int(result.get("lobby_state", 0))
	var zone: ZoneData = null
	if ZoneManager != null:
		zone = ZoneManager.get_zone(zone_id)
	var deadline: float = Contract.entry_deadline(zone)
	var state_name: String = Contract.LobbyState.keys()[state]
	notif.notify(
		NotifKind.ZONE_CHANGED,
		"Arena lobby %s -- bout starts within %d s." % [state_name, int(deadline)],
		"ArenaGateway",
		"arena_join:%s:%s" % [eid, iid],
		{"instance_id": iid, "lobby_state": state},
		eid)

# ---- Service resolvers (script-mode safe; AGENTS defensive pattern) -

## Stamp the origin stone into the live instance's session record so
## the room (origin_stones) can send everyone home later. Duck-typed
## against ZoneManager's instance dict shape.
func _stamp_origin_stones(_isvc, instance_id: String, entity_id: String, stone: Vector3) -> void:
	var zm = _zone_manager()
	if zm == null:
		return
	var data: Dictionary = zm.get_instance(instance_id)
	if data.is_empty():
		return
	var stones: Dictionary = data.get("origin_stones", {})
	stones[str(entity_id)] = stone
	data["origin_stones"] = stones

func _instance_service():
	var ml := Engine.get_main_loop()
	if ml == null or not (ml is SceneTree):
		return null
	return (ml as SceneTree).root.get_node_or_null("InstanceService")

func _zone_manager():
	var ml := Engine.get_main_loop()
	if ml == null or not (ml is SceneTree):
		return null
	return (ml as SceneTree).root.get_node_or_null("ZoneManager")

func _lobby_service():
	var ml := Engine.get_main_loop()
	if ml == null or not (ml is SceneTree):
		return null
	return (ml as SceneTree).root.get_node_or_null("LobbyService")

## The stone's queue: level read duck-typed off the body (player
## entities carry it; probes may not).
func _enqueue_at_stone(body: Node3D) -> void:
	var svc = _lobby_service()
	if svc == null:
		return
	var level: int = int(body.get("level")) if "level" in body else 1
	var ok: bool = svc.join_queue(str(body.entity_id), level, zone_id, true, stone_position_for(body))
	var notif = _notification_service()
	if notif == null:
		return
	if ok:
		notif.notify(
			NotifKind.ZONE_CHANGED,
			"Queued for the bout. The stone will carry you when both sides stand ready.",
			"ArenaGateway",
			"stone_queue:%s:%s" % [str(body.entity_id), zone_id],
			{},
			str(body.entity_id))
	else:
		notif.notify(
			NotifKind.ZONE_CHANGED,
			"Already queued -- open the Lobby (L) to check or leave.",
			"ArenaGateway",
			"stone_queue_dup:%s" % str(body.entity_id),
			{},
			str(body.entity_id))

func _notification_service():
	var ml := Engine.get_main_loop()
	if ml == null or not (ml is SceneTree):
		return null
	return (ml as SceneTree).root.get_node_or_null("NotificationService")

## Party members of this entity (empty = solo). PartyService owns the
## roster; read-only here. Any failure degrades to a solo join.
func _party_ids_for(entity) -> Array[String]:
	var out: Array[String] = []
	var ps = _party_service()
	if ps == null or not entity or not ("entity_id" in entity):
		return out
	var eid: String = str(entity.entity_id)
	# Real API: get_player_party returns the party dict (id inside);
	# get_party_members returns the roster.
	if ps.has_method("get_player_party"):
		var party = ps.call("get_player_party", eid)
		if party is Dictionary and not (party as Dictionary).is_empty():
			var pid: String = str((party as Dictionary).get("id", ""))
			if not pid.is_empty() and ps.has_method("get_party_members"):
				var members = ps.call("get_party_members", pid)
				if members is Array:
					for m in members:
						var mid := str(m)
						if mid != eid and not mid.is_empty():
							out.append(mid)
	return out

func _party_service():
	var ml := Engine.get_main_loop()
	if ml == null or not (ml is SceneTree):
		return null
	return (ml as SceneTree).root.get_node_or_null("PartyService")
