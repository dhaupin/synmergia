# probe_arena_bridge.gd - S11 probe: the combat bridge end to end.
#
# Covers the locked owner decisions through the REAL seams:
#   A. Contract power helpers (capped scale, never-nerf, stat targets)
#   B. Room self-registration into ArenaRoomService
#   C. Power normalization: bridge scales the lvl-5 fighter's six
#      stats toward the bout reference (cap ratio 2), recomputes max
#      health, stashes the snapshot, and RESTORES at bout end.
#   D. Fire-and-you-lose-it through the live signal path: a
#      CombatSystem.damage_dealt event from the ATTACKER breaks the
#      attacker's shield only; the victim's shield survives. A death
#      event on a shielded victim is refused by the room.
#   E. Death routing: CombatSystem.entity_died reaches the right room
#      and resolves the elimination bout (winner + return map).
#
# Script mode: autoloads resolved at runtime (never bare identifiers).
extends SceneTree

var _fails: int = 0
var _checks: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var Contract = load("res://core/schemas/instance_contract.gd")
	var zm = root.get_node_or_null("ZoneManager")
	if zm == null:
		quit(1)
		return
	zm.load_zones()
	var arena: Resource = zm.get_zone("zone_arena_coliseum")
	var sandpit: Resource = zm.get_zone("zone_arena_sandpit")
	_check("zones loaded", arena != null and sandpit != null)
	var bridge = root.get_node_or_null("ArenaCombatBridge")
	var room_svc = root.get_node_or_null("ArenaRoomService")
	var esvc = root.get_node_or_null("EntityService")
	var cs = root.get_node_or_null("CombatSystem")
	_check("bridge + room service + combat present", \
		bridge != null and room_svc != null and cs != null)

	# ---- A. Contract power helpers ------------------------------------
	_check("power_scale 30 vs 60 = 2.0 (full boost)", \
		abs(Contract.power_scale(30, 60) - 2.0) < 0.0001)
	_check("power_scale 5 vs 60 = 2.0 (cap holds)", \
		abs(Contract.power_scale(5, 60) - 2.0) < 0.0001)
	_check("power_scale never nerfs (70 vs 60 = 1.0)", \
		abs(Contract.power_scale(70, 60) - 1.0) < 0.0001)
	var targets: Dictionary = Contract.power_scale_target( \
		{"strength": 10, "agility": 10, "intelligence": 10, "vitality": 10, \
		"endurance": 10, "wisdom": 10, "damage_multiplier": 1.5}, 30, 60)
	_check("scale target doubles the base six", \
		int(targets.get("strength", 0)) == 20 and int(targets.get("vitality", 0)) == 20)
	_check("scale target leaves non-scaled keys alone", \
		not targets.has("damage_multiplier"))

	# ---- B. Room self-registration -------------------------------------
	var ArenaScene = load("res://scenes/instances/arena_instance.gd")
	var room = ArenaScene.new()
	room.zone_data = arena
	room.instance_id = "bridge_probe_room"
	root.add_child(room)
	_check("room self-registered by instance_id", \
		room_svc.room_by_id("bridge_probe_room") == room)

	# Real Entity stubs (script mode: load-then-new; registered straight
	# into EntityService's book the way the spawn path would).
	var E: GDScript = load("res://core/entities/entity.gd")
	var l5 = E.new()
	l5.entity_id = "bridge_l5"
	l5.display_name = "bridge_l5"
	l5.level = 5
	l5.entity_type = E.EntityType.PLAYER
	l5.stats["strength"] = 10
	l5.stats["vitality"] = 10
	var l60 = E.new()
	l60.entity_id = "bridge_l60"
	l60.display_name = "bridge_l60"
	l60.level = 60
	l60.entity_type = E.EntityType.PLAYER
	l60.stats["strength"] = 60
	l60.stats["vitality"] = 60
	esvc._entities["bridge_l5"] = l5
	esvc._entities["bridge_l60"] = l60

	# ---- C. Power normalization end to end -----------------------------
	room.spawn_fighter("bridge_l5", 0)
	room.spawn_fighter("bridge_l60", 1)
	room.set_fighter_level("bridge_l5", 5)
	room.set_fighter_level("bridge_l60", 60)
	room.origin_stones = {
		"bridge_l5": Vector3(2, 1, 2),
		"bridge_l60": Vector3(-2, 1, -2),
	}
	room.start_bout()
	await process_frame
	await process_frame  # deferred power emission + bridge application
	_check("lvl 5 strength scaled 10 -> 20 (cap ratio 2)", int(l5.stats["strength"]) == 20)
	_check("lvl 5 vitality scaled -> max health 300", l5.max_health == 300)
	_check("lvl 60 stats untouched (at reference)", int(l60.stats["strength"]) == 60)
	_check("snapshot stashed for restore", bridge._power_sessions.has("bridge_l5"))

	# ---- E. Death routing resolves the elimination bout -----------------
	var returns: Array = []
	room.bout_return_requested.connect(func(rmap): returns.append(rmap))
	# CombatSystem reports the kill: the lvl 60 takes out the lvl 5.
	cs.entity_died.emit(l5, l60)
	_check("bridge routed the kill into the room", room.is_over())
	_check("elimination winner is team 1 (the lvl 60)", room.score_for(0) == 0)
	_check("return map carries both stones", \
		returns.size() == 1 \
		and (returns[0].get("bridge_l5", Vector3.ZERO) as Vector3).distance_to(Vector3(2, 1, 2)) < 0.01)
	_check("power restored at bout end", int(l5.stats["strength"]) == 10)
	_check("power sessions cleared", bridge._power_sessions.is_empty())

	room.queue_free()
	await process_frame
	_check("room unregistered on exit", room_svc.room_by_id("bridge_probe_room") == null)

	# ---- D. Fire-and-you-lose-it via the live signal path (TDM) ---------
	# Real event shape: CombatSystem carries live ENTITIES (entity_id),
	# not the room's fighter bodies. Register real Entity stubs.
	var tdm = ArenaScene.new()
	tdm.zone_data = sandpit
	tdm.instance_id = "bridge_probe_tdm"
	root.add_child(tdm)
	var ta = tdm.spawn_fighter("bridge_tdm_a", 0)
	var tb = tdm.spawn_fighter("bridge_tdm_b", 1)
	tdm.start_bout()
	await process_frame
	_check("both TDM fighters shielded", ta.is_shielded() and tb.is_shielded())
	var ea = E.new()
	ea.entity_id = "bridge_tdm_a"
	ea.display_name = "bridge_tdm_a"
	ea.level = 10
	ea.entity_type = E.EntityType.PLAYER
	var eb = E.new()
	eb.entity_id = "bridge_tdm_b"
	eb.display_name = "bridge_tdm_b"
	eb.level = 10
	eb.entity_type = E.EntityType.PLAYER
	esvc._entities["bridge_tdm_a"] = ea
	esvc._entities["bridge_tdm_b"] = eb

	# A shielded victim's death is refused (the shield blocks).
	cs.entity_died.emit(eb, ea)
	_check("shield blocks the bridged kill", tb.alive and tdm.score_for(0) == 0)

	# The ATTACKER's damage event breaks the ATTACKER's shield only.
	cs.damage_dealt.emit(ea, eb, 5, null)
	_check("attacker shield broke (fire-and-you-lose-it)", not ta.is_shielded())
	_check("victim shield survived (received damage never breaks)", tb.is_shielded())

	# The victim fighting back breaks their own shield too.
	cs.damage_dealt.emit(eb, ea, 5, null)
	_check("victim's counterattack breaks their shield", not tb.is_shielded())

	# Unshielded, the next bridged kill lands and scores.
	cs.entity_died.emit(eb, ea)
	_check("bridged kill scores after shield gone", \
		not tb.alive and tdm.score_for(0) == 1)

	tdm.queue_free()
	await process_frame

	if _fails == 0:
		print("ARENA BRIDGE PROBE PASSED (%d checks)" % _checks)
		quit(0)
	else:
		push_error("ARENA BRIDGE PROBE FAILED")
		quit(1)

func _check(label: String, cond: bool) -> void:
	_checks += 1
	if cond:
		print("  PASS " + label)
	else:
		_fails += 1
		print("  FAIL " + label)
