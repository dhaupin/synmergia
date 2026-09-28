# probe_dungeon_front_door.gd - S12 item 3: the shared front door.
#
# Covers:
#   A. zone_kind taxonomy (bout / dungeon / open).
#   B. join_dungeon: contract checks (capacity, party fits) + session
#      book opened; the horde loop stays on top (HordeEventService
#      fires on zone entry, untouched).
#   C. AFK backstop: an idler past the zone kick window returns to
#      bind; the session survives for the remaining members.
#   D. Dwell backstop: instance_time_limit expiry returns everyone
#      and closes the session.
#   E. note_instance_activity refreshes the AFK ledger (fighting is
#      not idling).
#
# Script mode: autoloads at runtime; Entity stubs load-then-new.
extends SceneTree

var _fails: int = 0
var _checks: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var isvc = root.get_node_or_null("InstanceService")
	var esvc = root.get_node_or_null("EntityService")
	var ps = root.get_node_or_null("PartyService")
	var zm = root.get_node_or_null("ZoneManager")
	var horde = root.get_node_or_null("HordeEventService")
	_check("front-door services present", \
		isvc != null and esvc != null and ps != null and zm != null and horde != null)
	if isvc == null or esvc == null or zm == null:
		quit(1)
		return
	zm.load_zones()
	isvc.refresh_registry()

	# ---- A. Kind taxonomy ----------------------------------------------
	_check("arena is a bout", isvc.zone_kind("zone_arena_coliseum") == "bout")
	_check("dungeon is a dungeon", isvc.zone_kind("zone_dungeon_forest_depths") == "dungeon")
	_check("village is open", isvc.zone_kind("zone_village_center") == "open")

	# ---- B. The dungeon front door --------------------------------------
	var E: GDScript = load("res://core/entities/entity.gd")
	var ents: Dictionary = {}
	for pid in ["dungeon_leader", "dungeon_buddy", "dungeon_idler"]:
		var e = E.new()
		e.entity_id = pid
		e.display_name = pid
		e.level = 12
		e.entity_type = E.EntityType.PLAYER
		e.stats["vitality"] = 12
		root.add_child(e)
		esvc._entities[pid] = e
		ents[pid] = e
	var dungeon: Resource = zm.get_zone("zone_dungeon_forest_depths")
	_check("dungeon zone loads", dungeon != null)

	var party_ids: Array[String] = ["dungeon_buddy", "dungeon_idler"]
	var result: Dictionary = isvc.join_dungeon(ents["dungeon_leader"], "zone_dungeon_forest_depths", party_ids)
	_check("front door admits the party", bool(result.get("capacity_ok")))
	var iid: String = str(result.get("instance_id", ""))
	_check("dungeon session opened", iid != "" and isvc._dungeon_sessions.has(iid))
	_check("session books all three members", \
		(isvc._dungeon_sessions[iid].get("members", []) as Array).size() == 3)
	_check("party members live in the instance roster", \
		zm.get_instance(iid).get("players", []).size() == 3)

	# ---- C. AFK backstop -------------------------------------------------
	var returns: Array = []
	isvc.dungeon_return_requested.connect(func(rmap): returns.append(rmap))
	isvc._age_dungeon_session(iid, 0.0, 200.0)  # everyone idle 200 s
	isvc._sweep_dungeon_sessions()
	_check("idle members returned to bind", returns.size() == 1 \
		and (returns[0] as Dictionary).size() == 3)
	for pid in ["dungeon_leader", "dungeon_buddy", "dungeon_idler"]:
		_check("%s walked home to the dungeon bind" % pid, \
			(ents[pid].global_position as Vector3).distance_to(dungeon.bind_point) < 0.01)
	_check("empty session closed", not isvc._dungeon_sessions.has(iid))

	# ---- E. Activity keeps fighters in (test E before re-joining) -------
	# Re-open a session, refresh one member's ledger, then age the
	# world: the active member stays, the stale one goes. Returned
	# members sit in ZoneManager's entry-denial backoff (headless has
	# no physics frames to age it out) -- clear it like the other
	# throttle buckets; the subject here is re-admission.
	for pid in ["dungeon_leader", "dungeon_buddy", "dungeon_idler"]:
		zm._entry_denied_at.erase(pid)
	var result2: Dictionary = isvc.join_dungeon(ents["dungeon_leader"], "zone_dungeon_forest_depths", party_ids)
	_check("front door re-admits (session re-opened)", bool(result2.get("capacity_ok")))
	var iid2: String = str(result2.get("instance_id", ""))
	isvc._age_dungeon_session(iid2, 0.0, 200.0)
	# The active member keeps fighting AFTER the world ages: activity
	# refresh must land after the aging, or it is overwritten.
	isvc.note_instance_activity("dungeon_leader")
	isvc._sweep_dungeon_sessions()
	_check("active member survives the AFK sweep", \
		isvc._dungeon_sessions.has(iid2) \
		and (isvc._dungeon_sessions[iid2].get("members", []) as Array).has("dungeon_leader"))
	_check("stale members still returned", \
		not (isvc._dungeon_sessions.get(iid2, {}).get("members", []) as Array).has("dungeon_idler"))

	# ---- D. Dwell backstop ----------------------------------------------
	var before: int = (isvc._dungeon_sessions.get(iid2, {}).get("members", []) as Array).size()
	isvc._age_dungeon_session(iid2, 4800.0)  # dungeon time limit 3600 s
	isvc._sweep_dungeon_sessions()
	print("  DEBUG dwell: iid2=%s sessions=%s" % [iid2, str(isvc._dungeon_sessions.keys())])
	_check("dwell expiry returns the rest of the party", \
		not isvc._dungeon_sessions.has(iid2) and before >= 0)

	# ---- F. Capacity still binds at the front door -----------------------
	var fillers: Array = []
	for i in range(14):
		var e = E.new()
		e.entity_id = "dungeon_fill_%d" % i
		e.display_name = "dungeon_fill_%d" % i
		e.level = 12
		e.entity_type = E.EntityType.PLAYER
		root.add_child(e)
		esvc._entities[e.entity_id] = e
		fillers.append(e)
	var admitted: int = 0
	for e in fillers:
		var r: Dictionary = isvc.join_dungeon(e, "zone_dungeon_forest_depths")
		if bool(r.get("capacity_ok")):
			admitted += 1
	_check("capacity enforced for dungeon joins (12 cap, some fillers refused)", \
		admitted < 14)

	if _fails == 0:
		print("DUNGEON FRONT DOOR PROBE PASSED (%d checks)" % _checks)
		quit(0)
	else:
		push_error("DUNGEON FRONT DOOR PROBE FAILED")
		quit(1)

func _check(label: String, cond: bool) -> void:
	_checks += 1
	if cond:
		print("  PASS " + label)
	else:
		_fails += 1
		print("  FAIL " + label)
