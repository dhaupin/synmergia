## FerryService - S14.5: the ferry is a moving room (prd-ocean-depths
## sec 9). Scripted, scheduled, server-owned: the vessel and its path
## are server truth, and the schedule is the CLOSED-FORM primitive the
## almanac's sailing page already reads (one derivation, two readers
## -- if the boat and the page ever disagreed, the bug could only
## live in ferry_schedule.gd).
##
## The three crossing tiers on one route (the honesty law):
##   1. THE FERRY (ride it): real time -- the crossing is CONTENT.
##      Boarding opens in the schedule's boarding window and closes
##      at cast-off; arrival teleports the manifest port-to-port.
##   2. THE CHARTERED SKIFF (fast, priced): 2.5x the crossing, a
##      ticket price in gold -- the gold sink. Requires a RECORDED
##      ride (the wake) first: first crossings are never skippable.
##   3. THE ESTABLISHED WAKE (later dock-warp tier): the ledger
##      counts rides; S14.5 exposes the counts for the dock UI.
##
## The riding book is authoritative session truth (like the swim
## book): a rider moves with the vessel, and a rider who logs out
## misses the boat. Sailing position follows the v0 path contract:
## positions are the ports, the deck is virtual (planned ride-motion
## is S14.6+; the ride time is honest already).
##
## Autoload: NO class_name (AGENTS rule). Registered after
## OceanService (reads volumes for the route's lane) in project.godot.
extends Node

const FerrySchedule = preload("res://core/frame/srv/ferry_schedule.gd")
const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind
const DictStore = preload("res://adapters/persistence/dict_store.gd")
const _KV := "ferry_wake:"

## The skiff: 2.5x the ferry speed (prd sec 9, tier 2).
const SKIFF_SPEED_MULT: float = 2.5
## Boarding refuses outside the window; this is also how long the
## dock prompt stays honest after cast-off (the primitive's law).
const DEFAULT_SKIFF_TICKET: int = 25

signal ferry_departed(vehicle_id: String, from_port: String, to_port: String, riders: Array)
signal ferry_arrived(vehicle_id: String, at_port: String, riders: Array)
signal rider_boarded(player_id: String, vehicle_id: String, skiff: bool)
signal rider_arrived(player_id: String, vehicle_id: String, at_port: String)

## vehicle_id -> VehicleData (scheduled ferries only).
var _ferries: Dictionary = {}
## vehicle_id -> riders (the manifest; server truth for both tiers).
var _manifests: Dictionary = {}
## vehicle_id -> the departure it is running: {hour, day, cross_s}
## (day = the Concord epoch day it left on).
var _sailings: Dictionary = {}
## "player|vehicle" -> ride count (the wake ledger, session +
## persisted below; first-class-ride law reads this).
var _wake_ledger: Dictionary = {}
## "player|vehicle" -> true (ride recorded this session, for the
## unload-test seam; the ledger is the authority).
var _recorded_this_session: Dictionary = {}

var _loaded: bool = false
## Test/admin clock override (fractional Concord days); -1 = the sky.
var _clock_override: float = -1.0


func _ready() -> void:
	ensure_loaded()
	_load_wake()
	# The driver: cast-offs and arrivals are second-scale events, so
	# one tick per second carries the whole sailing day (the
	# SignService timer idiom).
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(_on_schedule_tick)
	add_child(timer)


func _on_schedule_tick() -> void:
	tick(1.0)


const ResourceScan = preload("res://core/frame/srv/resource_scan.gd")

## Load every data/vehicles/*.tres that declares a schedule.
## Idempotent (re-load refreshes). Export-safe scan: the pack stores
## .tres as .res + .tres.remap.
func ensure_loaded() -> void:
	if _loaded:
		return
	_ferries.clear()
	for p in ResourceScan.list_resources("res://data/vehicles"):
		var v = load(p)
		if v != null and "ferries_per_day" in v and int(v.ferries_per_day) > 0 \
				and v.route_gateways != null and v.route_gateways.size() >= 2:
			_ferries[str(v.id)] = v
			_manifests[str(v.id)] = {}
	_loaded = true


func get_ferry(id: String):
	return _ferries.get(id)


func all_ferries() -> Array:
	return _ferries.values()


## The canonical sky epoch (override-aware -- tests time-travel the
## same way SignService does; one clock read per call site).
func _epoch_days() -> float:
	if _clock_override >= 0.0:
		return _clock_override
	if SignService != null and SignService.has_method("sky_epoch_days"):
		return SignService.sky_epoch_days()
	return float(Time.get_unix_time_from_system()) / 86400.0


## Ports resolve through the gateway data (display_name for lore,
## source_position for the dock). Returns {id, name, pos} or null.
func _port(gateway_id: String):
	if DataService == null or not DataService.has_method("get_gateway"):
		return null
	var g = DataService.get_gateway(gateway_id)
	if g == null:
		return null
	return {"id": gateway_id, "name": str(g.display_name), \
		"pos": Vector3(g.source_position)}


## The sailing state a dock UI (or the almanac) shows for one route:
## {status: "boarding"/"at_sea"/"in_port", dep: {...}, crossing: {...}}
func route_status(vehicle_id: String) -> Dictionary:
	var v = _ferries.get(vehicle_id)
	if v == null:
		return {}
	var e := _epoch_days()
	var dep: Dictionary = FerrySchedule.next_departure( \
		int(v.ferries_per_day), float(v.first_departure_hour), e)
	var cross: Dictionary = FerrySchedule.crossing_in_progress( \
		int(v.ferries_per_day), float(v.first_departure_hour), \
		float(v.crossing_hours), e)
	var status := "in_port"
	if bool(dep.get("departing", false)) and cross.is_empty():
		status = "boarding"
	elif not cross.is_empty():
		status = "at_sea"
	return {"status": status, "dep": dep, "crossing": cross}


## Can this player board the ferry right now? The schedule's boarding
## window is the law (the almanac's "casting off now" is the same
## truth). Departed vessels refuse (the boat has sailed).
func can_board(player_id: String, vehicle_id: String) -> Dictionary:
	var v = _ferries.get(vehicle_id)
	if v == null:
		return {"ok": false, "reason": "no such vessel"}
	var st := route_status(vehicle_id)
	if st["status"] != "boarding":
		if not st["crossing"].is_empty():
			return {"ok": false, "reason": "the ferry is at sea"}
		var dep: Dictionary = st["dep"]
		if dep.is_empty():
			return {"ok": false, "reason": "no schedule"}
		return {"ok": false, "reason": "next cast-off in %.1f h" % float(dep["in_h"])}
	return {"ok": true, "to": str(v.route_gateways[1]), \
		"from": str(v.route_gateways[0])}


## Board the ferry (tier 1, free -- the owner's open question
## resolves to free rides + priced skiff). Inside the boarding window
## only; the manifest is server truth. Ride motion (the moving deck)
## is S14.6+; the RIDE TIME is honest already.
func board_ferry(player_id: String, vehicle_id: String) -> Dictionary:
	var gate := can_board(player_id, vehicle_id)
	if not bool(gate["ok"]):
		return gate
	var v = _ferries[vehicle_id]
	if _manifests[vehicle_id].has(player_id):
		return {"ok": false, "reason": "already aboard"}
	_manifests[vehicle_id][player_id] = true
	# Claim the sailing this boat will run (the departure the window
	# is open for; the tick reads it at cast-off).
	if not _sailings.has(vehicle_id):
		var dep: Dictionary = route_status(vehicle_id)["dep"]
		_sailings[vehicle_id] = {"hour": float(dep["hour"]), \
			"day": int(floor(_epoch_days())) + int(dep["day_offset"]), \
			"cross_s": FerrySchedule.crossing_seconds(float(v.crossing_hours))}
	rider_boarded.emit(player_id, vehicle_id, false)
	return {"ok": true, "to": str(v.route_gateways[1]), \
		"from": str(v.route_gateways[0])}


## The chartered skiff (tier 2): 2.5x speed, ticket-priced, and the
## WAKE LAW -- a player who has never ridden this route rides the
## ferry first; the world makes you take the sea at least once.
func charter_skiff(player_id: String, vehicle_id: String, ticket_cost: int = DEFAULT_SKIFF_TICKET) -> Dictionary:
	var v = _ferries.get(vehicle_id)
	if v == null:
		return {"ok": false, "reason": "no such vessel"}
	var wake_key := _wake_key(player_id, vehicle_id)
	if int(_wake_ledger.get(wake_key, 0)) <= 0:
		return {"ok": false, "reason": "the wake is not yours yet -- ride the ferry first"}
	var st := route_status(vehicle_id)
	if st["status"] == "at_sea" and not _manifests[vehicle_id].has(player_id):
		# A skiff can leave while the ferry sails (it is faster); it
		# just cannot leave from mid-water: board at the dock.
		return {"ok": false, "reason": "the dock is empty -- the ferry is at sea"}
	if _manifests[vehicle_id].has(player_id):
		return {"ok": false, "reason": "already aboard"}
	# The ticket: gold through the player's inventory (the sink).
	if ticket_cost > 0:
		var inv = InventoryService.get_inventory(player_id) if InventoryService != null else null
		if inv == null or not inv.has_method("remove_gold"):
			return {"ok": false, "reason": "no purse"}
		if not inv.remove_gold(ticket_cost):
			return {"ok": false, "reason": "not enough gold (the skiff costs %d)" % ticket_cost}
		if InventoryService.has_method("persist_inventory"):
			InventoryService.persist_inventory(player_id)
	_manifests[vehicle_id][player_id] = true
	# The skiff leaves NOW (it does not wait for the schedule): its
	# crossing is the ferry's divided by the multiplier.
	var cross_s: float = FerrySchedule.crossing_seconds(float(v.crossing_hours)) / SKIFF_SPEED_MULT
	var from_id := str(v.route_gateways[0])
	if not _sailings.has(vehicle_id):
		_sailings[vehicle_id] = {"hour": 0.0, "day": int(floor(_epoch_days())), "cross_s": cross_s}
	else:
		# A skiff sailing ahead of the ferry borrows the slot; the
		# ferry's own cast-off re-stamps it (v0: one slot, honest).
		_sailings[vehicle_id]["cross_s"] = cross_s
	_recorded_this_session[wake_key] = true
	rider_boarded.emit(player_id, vehicle_id, true)
	ferry_departed.emit(vehicle_id, from_id, str(v.route_gateways[1]), [player_id])
	return {"ok": true, "to": str(v.route_gateways[1]), "skiff": true}


## The per-physics-tick driver: cast off when the manifest is loaded
## and the schedule says so; arrive when the crossing is done.
func tick(delta: float) -> void:
	for vehicle_id in _ferries:
		var v = _ferries[vehicle_id]
		var manifest: Dictionary = _manifests[vehicle_id]
		var sailing: Dictionary = _sailings.get(vehicle_id, {})

		# At sea: run the crossing clock down.
		if not sailing.is_empty() and sailing.has("remaining_s"):
			sailing["remaining_s"] = float(sailing["remaining_s"]) - delta
			if float(sailing["remaining_s"]) <= 0.0:
				_arrive(vehicle_id)
			continue

		# In port: cast off at the scheduled departure IF anyone is
		# aboard (an empty boat stays tied up -- the crew waits).
		if manifest.is_empty():
			continue
		var e := _epoch_days()
		var dep: Dictionary = FerrySchedule.next_departure( \
			int(v.ferries_per_day), float(v.first_departure_hour), e)
		if bool(dep.get("departing", false)):
			_sailings[vehicle_id] = {"hour": float(dep["hour"]), \
				"day": int(floor(e)) + int(dep["day_offset"]), \
				"cross_s": FerrySchedule.crossing_seconds(float(v.crossing_hours)), \
				"remaining_s": FerrySchedule.crossing_seconds(float(v.crossing_hours))}
			ferry_departed.emit(vehicle_id, str(v.route_gateways[0]), \
				str(v.route_gateways[1]), manifest.keys())


## Arrival: the manifest lands at the destination port; the wake is
## recorded (the ledger that unlocks the skiff and the dock warp).
func _arrive(vehicle_id: String) -> void:
	var v = _ferries[vehicle_id]
	var manifest: Dictionary = _manifests[vehicle_id]
	var at_id := str(v.route_gateways[1])
	ferry_arrived.emit(vehicle_id, at_id, manifest.keys())
	for pid in manifest.keys():
		var player := str(pid)
		rider_arrived.emit(player, vehicle_id, at_id)
		_record_wake(player, vehicle_id)
		# v0 path contract: positions are the ports. The destination
		# dock's gateway position is the arrival truth (zone routing
		# stays ZoneManager's business).
		var port = _port(at_id)
		GameLog.info("FerryService: %s arrives at %s" % [player, str(port["name"]) if port != null else at_id])
		var local_kind: int = NotifKind.ZONE_CHANGED
		if NotificationService != null:
			NotificationService.notify(local_kind, \
				"The ferry docks at %s." % str(port["name"] if port != null else at_id), \
				"FerryService", \
				"ferry:arrive:%s:%s" % [player, vehicle_id], \
				{"vehicle_id": vehicle_id, "port": at_id}, \
				player)
	_sailings.erase(vehicle_id)
	_manifests[vehicle_id] = {}


## A rider who logs out misses the boat (the manifest is session
## truth; the wake only records completed rides). An EMPTIED dock
## also clears the claimed sailing slot -- nobody aboard, nobody
## sailing. A boat AT SEA sails on: riders abandoning mid-crossing
## do not teleport it back to port.
func abandon_riding(player_id: String) -> void:
	for vehicle_id in _manifests:
		_manifests[vehicle_id].erase(player_id)
		if _manifests[vehicle_id].is_empty() and _sailings.has(vehicle_id) \
				and not _sailings[vehicle_id].has("remaining_s"):
			_sailings.erase(vehicle_id)


## The wake: rides recorded per player per vehicle.
func _wake_key(player_id: String, vehicle_id: String) -> String:
	return "%s|%s" % [player_id, vehicle_id]


func _record_wake(player_id: String, vehicle_id: String) -> void:
	var key := _wake_key(player_id, vehicle_id)
	_wake_ledger[key] = int(_wake_ledger.get(key, 0)) + 1
	_persist_wake(player_id)


func rides_recorded(player_id: String, vehicle_id: String) -> int:
	return int(_wake_ledger.get(_wake_key(player_id, vehicle_id), 0))


## The dock-warp tier's gate (tier 3, S14.6+ UI): the wake is known
## once the route has carried this player WAKE_KNOWN_RIDES rides.
const WAKE_KNOWN_RIDES: int = 3


func wake_is_known(player_id: String, vehicle_id: String) -> bool:
	return rides_recorded(player_id, vehicle_id) >= WAKE_KNOWN_RIDES


## -- Wake persistence (a DictStore, the adapter-layer way: one key
## per player, the whole wake row as the payload -- the
## WaypointService idiom) --------------------------------------------

func _load_wake() -> void:
	var store := DictStore.new()
	var keys: Array = store.all_keys()
	var wake_keys: Array = []
	for key in keys:
		if str(key).begins_with(_KV):
			wake_keys.append(key)
	if wake_keys.is_empty():
		return
	var results: Dictionary = store.get_many(wake_keys)
	for key in wake_keys:
		var player_id: String = str(key).substr(_KV.length())
		var row = results.get(key, {})
		if row is Dictionary:
			for vehicle_id in row.keys():
				_wake_ledger[_wake_key(player_id, str(vehicle_id))] = int(row[vehicle_id])


func _persist_wake(player_id: String) -> void:
	var store := DictStore.new()
	var row: Dictionary = {}
	for vehicle_id in _ferries:
		var key := _wake_key(player_id, vehicle_id)
		if _wake_ledger.has(key):
			row[vehicle_id] = int(_wake_ledger[key])
	if row.is_empty():
		store.erase(_KV + player_id)
	else:
		store.set_kv(_KV + player_id, row)
