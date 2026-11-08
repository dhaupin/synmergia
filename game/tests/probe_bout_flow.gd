# probe_bout_flow.gd - S11 probe: the last hook + the ROYALE drop.
#
# Covers:
#   A. BoutTeleportService: bout_assembled scatters player entities
#      into team staging; bout_return_requested sends them home to
#      their stones (via the room signal AND the direct seam).
#   B. ROYALE drop scatter: start_bout throws every fighter into the
#      sky over a wide golden-angle ring, zeroed velocity, no stacks.
#   C. Glider groundwork: movement_glider profile (AERIAL, tamed
#      gravity, no jump), anticheat glide limits swap while gliding,
#      glider .tres ids resolve with glider_ prefix.
#
# Script mode: autoloads resolved at runtime; Entity stubs via
# load-then-new (never parse-time class_name refs).
extends SceneTree

var _fails: int = 0
var _checks: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var Contract = load("res://core/schemas/instance_contract.gd")
	var zm = root.get_node_or_null("ZoneManager")
	var esvc = root.get_node_or_null("EntityService")
	var ac = root.get_node_or_null("AntiCheatService")
	var tele = root.get_node_or_null("BoutTeleportService")
	var room_svc = root.get_node_or_null("ArenaRoomService")
	_check("teleport listener present", tele != null)
	_check("room service present", room_svc != null)
	if tele == null or esvc == null or zm == null:
		quit(1)
		return
	zm.load_zones()
	var royale: Resource = zm.get_zone("zone_royale_valley")
	_check("royale zone loaded (mode ROYALE)", \
		royale != null and int(royale.instance_mode) == 2)

	# ---- A. Teleport listener: assembly in ----------------------------
	var E: GDScript = load("res://core/entities/entity.gd")
	var p1 = E.new()
	p1.entity_id = "flow_p1"
	p1.display_name = "flow_p1"
	p1.level = 8
	p1.entity_type = E.EntityType.PLAYER
	var p2 = E.new()
	p2.entity_id = "flow_p2"
	p2.display_name = "flow_p2"
	p2.level = 9
	p2.entity_type = E.EntityType.PLAYER
	# Live nodes in the tree: Entity extends Node3D, positions stick.
	root.add_child(p1)
	root.add_child(p2)
	esvc._entities["flow_p1"] = p1
	esvc._entities["flow_p2"] = p2

	var royale_spawns: Array = royale.spawn_points
	tele._on_bout_assembled("zone_royale_valley", "flow_instance", ["flow_p1"], ["flow_p2"])
	_check("assembly teleports team A to staging ring", \
		(p1.global_position as Vector3).distance_to(Contract.scatter_spawn(royale_spawns[0], 0)) < 0.01)
	_check("assembly teleports team B to their staging ring", \
		(p2.global_position as Vector3).distance_to(Contract.scatter_spawn(royale_spawns[1], 0)) < 0.01)
	_check("staged fighters do not stack across teams", \
		(p1.global_position as Vector3).distance_to(p2.global_position) > 1.0)

	# ---- A2. The return home ------------------------------------------
	tele.apply_return_map({
		"flow_p1": Vector3(14, 2.5, 0),
		"flow_p2": Vector3(14, 2.5, 3),
	})
	_check("return map sends p1 home to the stone", \
		(p1.global_position as Vector3).distance_to(Vector3(14, 2.5, 0)) < 0.01)
	_check("return map sends p2 home to the stone", \
		(p2.global_position as Vector3).distance_to(Vector3(14, 2.5, 3)) < 0.01)

	# Room-signal path: a live room's bout_return_requested reaches the
	# listener (wired on room_opened via ArenaRoomService).
	var ArenaScene = load("res://scenes/instances/arena_instance.gd")
	var room = ArenaScene.new()
	room.zone_data = zm.get_zone("zone_arena_coliseum")
	room.instance_id = "flow_probe_room"
	root.add_child(room)
	_check("room registered (listener hook bound)", \
		room_svc.room_by_id("flow_probe_room") == room)
	var p3 = E.new()
	p3.entity_id = "flow_p3"
	p3.display_name = "flow_p3"
	p3.level = 7
	p3.entity_type = E.EntityType.PLAYER
	root.add_child(p3)
	esvc._entities["flow_p3"] = p3
	room.bout_return_requested.emit({"flow_p3": Vector3(14, 2.5, 9)})
	_check("room return signal teleports the fighter home", \
		(p3.global_position as Vector3).distance_to(Vector3(14, 2.5, 9)) < 0.01)
	room.queue_free()
	await process_frame

	# ---- B. ROYALE drop scatter ----------------------------------------
	var rroom = ArenaScene.new()
	rroom.zone_data = royale
	rroom.instance_id = "flow_probe_royale"
	root.add_child(rroom)
	rroom.spawn_fighter("drop_1", 0)
	rroom.spawn_fighter("drop_2", 1)
	rroom.spawn_fighter("drop_3", 2)
	rroom.spawn_fighter("drop_4", 3)
	rroom.start_bout()
	await process_frame
	await process_frame
	var half: float = float(royale.zone_radius) * 0.5
	var expected_height: float = half * 0.8
	var bodies: Array = []
	var min_gap: float = 999.0
	for fid in ["drop_1", "drop_2", "drop_3", "drop_4"]:
		var f = rroom._fighters.get(fid)
		bodies.append(f.global_position)
		_check("drop %s is in the sky over the valley" % fid, \
			f.global_position.y > expected_height * 0.9)
	_check("royale drop scatters (min gap > 1.5 m)", \
		(bodies[0] as Vector3).distance_to(bodies[1]) > 1.5 \
		and (bodies[1] as Vector3).distance_to(bodies[2]) > 1.5 \
		and (bodies[2] as Vector3).distance_to(bodies[3]) > 1.5)
	rroom.queue_free()
	await process_frame

	# ---- C. Glider groundwork ------------------------------------------
	var profile: Resource = load("res://data/movement_profiles/movement_glider.tres")
	_check("glider profile is AERIAL class", int(profile.locomotion_class) == 2)
	_check("glider gravity is tamed (4.5)", abs(profile.gravity_force - 4.5) < 0.001)
	_check("glider cannot jump (jump_force 0, allow_jump false)", \
		profile.jump_force == 0.0 and not profile.allow_jump)
	_check("glider sink is gentle (terminal fall 8)", abs(profile.terminal_fall_speed - 8.0) < 0.001)
	var glide_speed: float = profile.sprint_speed * 1.9
	# Real convention: WORLD limits come from the player's ground
	# profile (standard fall 55 x 2.0 = 110); GLIDE maxima come from
	# the wing profile (fall 8 x 2.0 = 16). Multipliers apply at the
	# call site (the player body's spawn-stamp pattern).
	var world_profile: Resource = load("res://data/movement_profiles/movement_standard.tres")
	ac.set_movement_limits("flow_p1", 25.0, 25.0, \
		world_profile.terminal_fall_speed * ac.FALL_LIMIT_MULTIPLIER, \
		glide_speed * ac.SPEED_LIMIT_MULTIPLIER, \
		profile.terminal_fall_speed * ac.FALL_LIMIT_MULTIPLIER)
	ac.set_glide_active("flow_p1", true)
	var gl: Dictionary = ac.get_movement_limits("flow_p1")
	_check("glide limits swap in while gliding", \
		abs(gl["max_fall"] - 16.0) < 0.001)
	ac.set_glide_active("flow_p1", false)
	var wl: Dictionary = ac.get_movement_limits("flow_p1")
	_check("world limits restore when the wing stows", \
		abs(wl["max_fall"] - 110.0) < 0.001)
	for gid in ["glider_drift_kite", "glider_sewn_swallow", "glider_gullwing_shade", "glider_reclaimer_ribs", "glider_storm_spine"]:
		var dev: Resource = load("res://data/gliders/%s.tres" % gid)
		_check("glider %s loads with glider_ prefix id" % gid, \
			dev != null and str(dev.id) == gid and str(dev.id).begins_with("glider_"))

	if _fails == 0:
		print("BOUT FLOW PROBE PASSED (%d checks)" % _checks)
		quit(0)
	else:
		push_error("BOUT FLOW PROBE FAILED")
		quit(1)

func _check(label: String, cond: bool) -> void:
	_checks += 1
	if cond:
		print("  PASS " + label)
	else:
		_fails += 1
		print("  FAIL " + label)
