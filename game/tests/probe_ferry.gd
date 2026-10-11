# probe_ferry.gd - S14.5: the ferry is a moving room
# (labs/prd-ocean-depths.md sec 9). The schedule primitive is the ONE
# law the page and the dock read; the service rides it. Covers:
#   A. The ferry is DATA (declared schedule, real route, live chart).
#   B. Chart-and-dock agreement: route_status and the primitive give
#      the same numbers off the same epoch (one-clock law).
#   C. The ride: board in the window, cast off with a manifest,
#      arrive, record the wake.
#   D. The skiff: priced, 2.5x, and the first crossing is never
#      skippable (the wake law).
#   E. Logout misses the boat (the manifest is session truth).
#   F. The wake survives a reboot (DictStore round-trip).
#
# Script mode: autoloads at runtime. The clock is time-traveled via
# FerryService._clock_override (the SignService override pattern);
# every clock-sensitive phase pins ONE override epoch.
extends SceneTree

var _fails: int = 0
var _checks: int = 0
var _departures: Array = []
var _arrivals: Array = []
var _rider_arrivals: Array = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var fs = root.get_node_or_null("FerryService")
	_check("FerryService present (the dock is staffed)", fs != null)
	if fs == null:
		quit(1)
		return
	fs.ensure_loaded()
	var FS = load("res://core/frame/srv/ferry_schedule.gd")
	var id := "veh_haven_ferry"

	# ---- A. The ferry is data ------------------------------------------------
	var v = fs.get_ferry(id)
	_check("the Haven Ferry is scheduled data (8 a day, 30 min)", \
		v != null and int(v.ferries_per_day) == 8 \
		and absf(float(v.crossing_hours) - 0.5) < 1e-9)
	_check("the route has two ports (village docks -> Nexus harbor)", \
		v != null and str(v.route_gateways[0]) == "waypoint_village_center" \
		and str(v.route_gateways[1]) == "waypoint_nexus_central")
	var st_live: Dictionary = fs.route_status(id)
	_check("the dock chart is never blank (realtime status works)", \
		not st_live.is_empty() and st_live.has("status") \
		and (not st_live["dep"].is_empty() or not st_live["crossing"].is_empty()))

	# ---- B. Chart-and-dock agreement (the one-law probe) ----------------------
	# 09:00 exactly on day 100: a departure hour, boarding window open.
	var epoch: float = 100.0 + 9.0 / 24.0
	fs._clock_override = epoch
	var st: Dictionary = fs.route_status(id)
	var prim: Dictionary = FS.next_departure(8, 6.0, epoch)
	_check("the dock and the primitive read the same cast-off", \
		not st["dep"].is_empty() and absf(float(st["dep"]["hour"]) - float(prim["hour"])) < 1e-9 \
		and absf(float(st["dep"]["in_h"]) - float(prim["in_h"])) < 1e-9 \
		and bool(st["dep"]["departing"]) == bool(prim["departing"]))
	_check("09:00 is BOARDING (the window the page calls casting off)", \
		str(st["status"]) == "boarding")
	fs._clock_override = 100.0 + 9.2 / 24.0
	var st_sea: Dictionary = fs.route_status(id)
	_check("09:12 is AT SEA with the crossing clock the primitive gives", \
		str(st_sea["status"]) == "at_sea" \
		and absf(float(st_sea["crossing"]["remaining_h"]) - 0.3) < 1e-9)

	# ---- C. The ride ------------------------------------------------------------
	fs._clock_override = epoch  # back to the boarding window
	# A purse for the skiff later; the ferry itself is free.
	var inv = load("res://core/components/inventory_component.gd").new()
	root.add_child(inv)
	var invs = root.get_node_or_null("InventoryService")
	_check("InventoryService present (the purse keeper)", invs != null)
	invs.register_inventory("deckhand", inv)
	inv.add_gold(100)

	var gate: Dictionary = fs.can_board("deckhand", id)
	_check("in the window the dock says come aboard", \
		bool(gate["ok"]) and str(gate["to"]) == "waypoint_nexus_central")
	var board: Dictionary = fs.board_ferry("deckhand", id)
	_check("deckhand boards the ferry (free, as the law settled)", \
		bool(board["ok"]) and not board.has("skiff"))
	var again: Dictionary = fs.board_ferry("deckhand", id)
	_check("no double-boarding (one manifest, one body)", \
		not bool(again["ok"]) and str(again["reason"]).contains("already"))

	# Cast-off: the tick departs a loaded boat in the window.
	fs.ferry_departed.connect(func(vid, from_p, to_p, riders): _departures.append(riders))
	for i in 5:
		fs.tick(1.0 / 60.0)
	_check("the loaded boat casts off on schedule", _departures.size() == 1)
	var sailing: Dictionary = fs._sailings.get(id, {})
	_check("the crossing clock is honest (30 min of sea)", \
		sailing.has("remaining_s") and absf(float(sailing["remaining_s"]) - 1800.0) < 1.0)

	# Arrival: the manifest lands and the wake is recorded.
	fs.ferry_arrived.connect(func(vid, at_p, riders): _arrivals.append(str(at_p)))
	fs.rider_arrived.connect(func(pid, vid, at_p): _rider_arrivals.append(str(pid)))
	fs._sailings[id]["remaining_s"] = 0.01
	fs.tick(0.02)
	_check("the ferry arrives at the Nexus harbor", _arrivals == ["waypoint_nexus_central"])
	_check("the rider's arrival is named", _rider_arrivals == ["deckhand"])
	_check("the manifest disembarks cleanly", fs._manifests[id].is_empty())
	_check("the wake is recorded (one crossing, one entry)", \
		fs.rides_recorded("deckhand", id) == 1)

	# ---- D. The skiff and the wake law -----------------------------------------
	var lubber = load("res://core/components/inventory_component.gd").new()
	root.add_child(lubber)
	invs.register_inventory("landlubber", lubber)
	lubber.add_gold(500)
	var no_wake: Dictionary = fs.charter_skiff("landlubber", id)
	_check("the first crossing is never skippable (no wake, no skiff)", \
		not bool(no_wake["ok"]) and str(no_wake["reason"]).contains("wake"))
	_check("the refusal never touched the purse", lubber.get_gold() == 500)
	var skiff: Dictionary = fs.charter_skiff("deckhand", id)
	_check("a ridden route charters the skiff (2.5x, priced)", \
		bool(skiff["ok"]) and bool(skiff["skiff"]))
	_check("the ticket is the gold sink (100 - 25 = 75)", inv.get_gold() == 75)
	fs.abandon_riding("deckhand")
	fs._sailings.erase(id)
	fs._manifests[id] = {}
	var broke = load("res://core/components/inventory_component.gd").new()
	root.add_child(broke)
	invs.register_inventory("sailor", broke)
	broke.add_gold(10)
	fs._record_wake("sailor", id)  # rode once, now broke
	var poor: Dictionary = fs.charter_skiff("sailor", id)
	_check("the skiff is priced for real (a broke wake walks)", \
		not bool(poor["ok"]) and str(poor["reason"]).contains("gold") \
		and broke.get_gold() == 10)
	var free: Dictionary = fs.charter_skiff("sailor", id, 0)
	_check("a comped ticket still sails (the tier is the speed)", bool(free["ok"]))
	fs.abandon_riding("sailor")
	fs._sailings.erase(id)
	fs._manifests[id] = {}

	# ---- E. Logout misses the boat ------------------------------------------------
	fs._clock_override = epoch
	var deserter = load("res://core/components/inventory_component.gd").new()
	root.add_child(deserter)
	invs.register_inventory("deserter", deserter)
	fs.board_ferry("deserter", id)
	fs.abandon_riding("deserter")
	fs.tick(1.0 / 60.0)
	_check("a rider who leaves the manifest misses the boat (it stays tied)", \
		fs._manifests[id].is_empty() and not fs._sailings.has(id) \
		and fs.rides_recorded("deserter", id) == 0)

	# ---- F2. THE SUNDERED BARQUE (the authored-site route) --------------------------
	# The strait ferry is real DATA through the real DataService scan:
	# two ports (moor pin -> seaward pin), both on the strait zone,
	# the vehicle declared with its own schedule. AND the crossing is
	# honest about the TERRAIN: the moor-side port rides a direction
	# whose ground law (through the authored backend seam) is below
	# the sea line (a ferry dock sits in water); the shoal crest
	# direction stands its WET pin (probe_sundered_sea's crest).
	var b_id := "veh_sundered_barque"
	var barque = fs.get_ferry(b_id)
	_check("the Sundered barque is scheduled data (6 a day, moor -> seaward)", \
		barque != null and int(barque.ferries_per_day) == 6 \
		and str(barque.route_gateways[0]) == "waypoint_strait_moor" \
		and str(barque.route_gateways[1]) == "waypoint_strait_seaward")
	var ds2 = root.get_node_or_null("DataService")
	var moor = ds2.get_gateway("waypoint_strait_moor") if ds2 else null
	var seaward = ds2.get_gateway("waypoint_strait_seaward") if ds2 else null
	_check("both barque pins resolve through the DataService scan", \
		moor != null and seaward != null \
		and str(moor.source_zone_id) == "zone_sundered_sea" \
		and str(seaward.source_zone_id) == "zone_sundered_sea")
	# The strait ferry's route_status reads the SAME primitive law on
	# its OWN schedule (5:30 start, 6 ferries, 4 h step => cast-offs
	# at 5.5, 9.5, 13.5...). The boarding window is 0.25 h before the
	# cast-off, so 05:30 - 11 min (5.52 -> in_h 0.08) is boarding.
	fs._clock_override = 100.0 + 5.48 / 24.0
	var st_barque: Dictionary = fs.route_status(b_id)
	_check("the barque's dock chart is live (boarding on its own clock)", \
		str(st_barque.get("status", "")) == "boarding")
	fs._clock_override = -1.0

	# ---- F. The wake survives a reboot --------------------------------------------
	fs._record_wake("deckhand", id)  # second crossing
	var fs2 = load("res://core/services/ferry_service.gd").new()
	fs2._load_wake()
	_check("the wake ledger round-trips the store (a reboot remembers)", \
		fs2.rides_recorded("deckhand", id) == 2)
	fs2.free()

	# ---- G. Cleanup: the clock and the wake store ---------------------------------
	fs._clock_override = -1.0
	var store = load("res://adapters/persistence/dict_store.gd").new()
	for pid in ["deckhand", "landlubber", "sailor", "deserter"]:
		store.erase("ferry_wake:" + pid)
		invs.unregister_inventory(pid)

	if _fails == 0:
		print("FERRY PROBE PASSED (%d checks)" % _checks)
		quit(0)
	else:
		push_error("FERRY PROBE FAILED")
		quit(1)

func _check(label: String, cond: bool) -> void:
	_checks += 1
	if cond:
		print("  PASS " + label)
	else:
		_fails += 1
		print("  FAIL " + label)
