# probe_arena_trigger.gd - S10 probe: the world-side gateway trigger.
# Script-mode SceneTree test: gateway fires the S9 join once per
# entry, dedupes while standing inside, re-arms after exit, and the
# FULL case returns capacity_ok=false without a phantom instance.
# Instance room itself is probed by probe_arena_instance.gd.
extends SceneTree

var _fails: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var zm = root.get_node_or_null("ZoneManager")
	var isvc = root.get_node_or_null("InstanceService")
	_check("autoloads present", zm != null and isvc != null)
	if zm == null or isvc == null:
		quit(1)
		return
	zm.load_zones()
	isvc.refresh_registry()

	var Gateway = load("res://scenes/worlds/arena_gateway.gd")
	var gw = Gateway.new()
	gw.zone_id = "zone_arena_coliseum"
	root.add_child(gw)

	# ---- A. Solo join fires on entry --------------------------------
	var E: GDScript = load("res://core/entities/entity.gd")
	var p1 = E.new()
	p1.entity_id = "trigger_walker"
	p1.display_name = "trigger_walker"
	p1.level = 1
	p1.entity_type = E.EntityType.PLAYER

	var requested: Array = []
	var results: Array = []
	gw.join_requested.connect(func(e, z): requested.append([e, z]))
	gw.join_result.connect(func(e, r): results.append(r))

	# Fire the body_entered path directly (physics frames are not
	# needed; the Area3D handler is the unit under test).
	gw._on_body_entered(p1)
	_check("join_requested emitted", requested.size() == 1)
	_check("join_result emitted", results.size() == 1)
	var r1: Dictionary = results[0] if results.size() > 0 else {}
	_check("solo trigger join accepted", bool(r1.get("capacity_ok")))
	var iid: String = str(r1.get("instance_id", ""))
	_check("join landed in a live instance", iid != "")
	_check("lobby state surfaced in result", \
		r1.has("lobby_state") and int(r1.get("lobby_state")) == 0)  # OPEN

	# ---- B. Dedupe: standing inside does not re-fire ----------------
	gw._on_body_entered(p1)
	_check("no double-fire inside the volume", \
		requested.size() == 1 and results.size() == 1)

	# ---- C. Re-arm after exit ----------------------------------------
	gw._on_body_exited(p1)
	gw._on_body_entered(p1)
	_check("re-entry fires again after exit", requested.size() == 2)
	_check("second join routes to THE live instance", \
		results.size() == 2 and str(results[1].get("instance_id", "")) == iid)

	# ---- D. FULL case: 12 seats, the 13th gets a refusal toast ------
	for i in range(10):
		var pj = E.new()
		pj.entity_id = "trigger_filler_%d" % i
		pj.level = 1
		pj.entity_type = E.EntityType.PLAYER
		gw._on_body_entered(pj)
	# Walker + 11 more = 12 total seated (p1 + 10 fillers + 1 below).
	var p13 = E.new()
	p13.entity_id = "trigger_thirteenth"
	p13.level = 1
	p13.entity_type = E.EntityType.PLAYER
	gw._on_body_entered(p13)
	_check("gateway fired for all entrants", requested.size() == 13)
	var last: Dictionary = results[results.size() - 1] if results.size() > 0 else {}
	_check("capacity enforced (12 seated of 13 requests)", \
		results.size() == 13 and \
		_results_with_seat(results) == 12)
	_check("last entrant refused when full", \
		not bool(last.get("capacity_ok")) and str(last.get("instance_id", "")) == iid)
	_check("no phantom instance created", \
		isvc.live_instance_id("zone_arena_coliseum") == iid)

	# Cleanup: leave the KV store clean for later boots.
	var lm = root.get_node_or_null("LoginManager")
	if isvc.get("players") != null:
		pass
	zm.destroy_instance(iid)

	if _fails == 0:
		print("ARENA TRIGGER PROBE PASSED")
		quit(0)
	else:
		push_error("ARENA TRIGGER PROBE FAILED")
		quit(1)

func _results_with_seat(results: Array) -> int:
	var n := 0
	for r in results:
		if bool(r.get("capacity_ok")):
			n += 1
	return n

func _check(label: String, cond: bool) -> void:
	if cond:
		print("  PASS " + label)
	else:
		_fails += 1
		print("  FAIL " + label)
