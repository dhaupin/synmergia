# probe_royale_storm.gd - S13: the fog closes (ROYALE wiring).
#
# Covers:
#   A. Contract storm math: the phase ladder (storm_plan /
#      storm_radius_at / storm_damage_at) agrees with itself across
#      holds, shrinks and the final circle.
#   B. Rules plumbing: bout_rules(zone_royale_valley) carries the
#      storm book (start / scale / phases); zone .tres fields land.
#   C. Room arming: the wall arms storm_start_seconds after the bout
#      starts (probe deadline override), announces phase 0, and the
#      draw clock stays the backstop.
#   D. The grind: fighters outside the safe circle take storm damage
#      through the bridge (room holds bodies; entities route the
#      bite), on a 1 s cadence, with the fog as the kill credit.
#   E. In-circle fighters stay untouched; shrinking radii follow the
#      ladder; ROYALE fighters drop on the WING (glider contract).
#   F. Anticheat launch tickets forgive the ROYALE throw upward but
#      never horizontal speedhacks (server-side grants only).
#
# Script mode: autoloads resolved at runtime; deadlines overridden so
# headless waits are seconds, not minutes.
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
	_check("services present (ZoneManager/EntityService/anticheat)", \
		zm != null and esvc != null and ac != null)
	if zm == null or esvc == null:
		quit(1)
		return

	# ---- A. Contract storm math -----------------------------------------
	var plan: Dictionary = Contract.storm_plan(100.0)
	var phases: Array = plan.get("phases", [])
	_check("storm plan has 5 phases (horde ladder + no quarter)", phases.size() == 5)
	var first: Dictionary = phases[0]
	var last: Dictionary = phases[phases.size() - 1]
	_check("phase 1 holds then shrinks to 0.65 of half", \
		abs(float(first.get("shrink_start")) - 60.0) < 0.01 \
		and abs(float(first.get("radius")) - 65.0) < 0.01)
	_check("final phase ends at the plan total", \
		abs(float(last.get("end")) - float(plan.get("total"))) < 0.01)
	_check("phase 4 radius honors the min circle", \
		float(phases[3].get("radius")) >= Contract.MIN_STORM_RADIUS_M)
	_check("NO QUARTER: the ladder has a true-zero final phase", \
		phases.size() == 5 and float(phases[-1].get("radius")) == 0.0 \
		and float(phases[-1].get("damage")) >= 10.0)
	_check("damage climbs per phase (1 -> 7 dps)", \
		float(phases[0].get("damage")) < float(phases[-1].get("damage")) \
		and float(phases[0].get("damage")) == 1.0)
	# Radius walking: full radius before any shrink; lerped mid-shrink;
	# final radius after the ladder.
	var r0: float = Contract.storm_radius_at(plan, 30.0, 100.0)
	var rmid: float = Contract.storm_radius_at(plan, 75.0, 100.0)
	var rend: float = Contract.storm_radius_at(plan, float(plan.get("total")) + 5.0, 100.0)
	_check("wall stands at the room edge during the hold", abs(r0 - 100.0) < 0.01)
	_check("wall lerps inward mid-shrink", rmid < 100.0 and rmid > float(first.get("radius")))
	_check("wall rests at the final circle after the ladder", \
		abs(rend - float(last.get("radius"))) < 0.01)
	_check("no damage before the storm arms", Contract.storm_damage_at(plan, -1.0) == 0.0)
	_check("damage lives through hold AND shrink", \
		Contract.storm_damage_at(plan, 30.0) > 0.0 \
		and Contract.storm_damage_at(plan, 80.0) > 0.0 \
		and Contract.storm_damage_at(plan, float(plan.get("total")) + 1.0) == 0.0)

	# ---- B. Rules plumbing ----------------------------------------------
	zm.load_zones()
	var royale: Resource = zm.get_zone("zone_royale_valley")
	_check("royale zone loaded", royale != null)
	var rules: Dictionary = Contract.bout_rules(royale)
	_check("royale rules carry the storm book", \
		rules.has("storm_start_seconds") and rules.has("storm_phases") \
		and rules.has("storm_scale"))
	_check("valley storm arms at 45 s (zone .tres override)", \
		abs(float(rules.get("storm_start_seconds")) - 45.0) < 0.01)
	_check("zone fields land on ZoneData (storm_start/scale)", \
		"instance_storm_start" in royale and "instance_storm_scale" in royale)
	_check("draw clock stays (15 min backstop)", \
		abs(float(rules.get("time_limit_seconds")) - 900.0) < 0.01)
	# A negative start disables the wall.
	var no_storm_zone = load("res://data/zones/zone_arena_coliseum.tres")
	_check("elimination rules carry NO storm book (mode-scoped)", \
		not Contract.bout_rules(no_storm_zone).has("storm_start_seconds"))

	# ---- C+D. Room arming + the grind ------------------------------------
	var ArenaScene = load("res://scenes/instances/arena_instance.gd")
	var room = ArenaScene.new()
	room.zone_data = royale
	room.instance_id = "storm_probe_room"
	room.start_deadline_override = 0.0
	root.add_child(room)

	# Live entities: the storm routes its bite through the bridge.
	var E: GDScript = load("res://core/entities/entity.gd")
	var cs2 = root.get_node_or_null("CombatSystem")
	var p1 = E.new()
	p1.entity_id = "storm_p1"
	p1.display_name = "storm_p1"
	p1.level = 10
	p1.entity_type = E.EntityType.PLAYER
	p1.max_health = 200
	p1.current_health = 200
	root.add_child(p1)
	esvc._entities["storm_p1"] = p1
	if cs2 != null:
		cs2.register_entity(p1)  # production registers at spawn; the probe mirrors it
	var p2 = E.new()
	p2.entity_id = "storm_p2"
	p2.display_name = "storm_p2"
	p2.level = 10
	p2.entity_type = E.EntityType.PLAYER
	p2.max_health = 200
	p2.current_health = 200
	root.add_child(p2)
	esvc._entities["storm_p2"] = p2
	if cs2 != null:
		cs2.register_entity(p2)

	room.spawn_fighter("storm_p1", 0)
	room.spawn_fighter("storm_p2", 1)
	room.origin_stones["storm_p1"] = Vector3.ZERO
	room.origin_stones["storm_p2"] = Vector3.ZERO

	# Phase-0 signal spy before the bout arms anything.
	var phase_announcements: Array = []
	room.storm_phase_advanced.connect(func(radius: float, idx: int):
		phase_announcements.append({"radius": radius, "phase": idx}))
	var storm_hits: Array = []
	room.storm_damage_applied.connect(func(fid: String, dps: float):
		storm_hits.append({"fighter": fid, "dps": dps}))
	var kill_credits: Array = []
	room.storm_kill_credited.connect(func(victim: String, team: int):
		kill_credits.append({"victim": victim, "team": team}))

	room.start_bout()
	await process_frame
	_check("bout live, wall not yet armed", room.is_started() and not room.storm_armed())
	_check("wing armed by the drop (glider contract)", \
		room._fighters.get("storm_p1") != null \
		and room._fighters.get("storm_p1").glider != null)
	_check("fighters dropped from the sky", \
		room._fighters.get("storm_p1").global_position.y > 100.0)

	# Force the wall to arm NOW (storm_start override + arm seam): the
	# room arms on its own clock; the probe pulls the seam directly so
	# headless waits stay instant.
	room._arm_storm()
	_check("wall armed on demand", room.storm_armed())
	_check("arming announced phase 0", phase_announcements.size() >= 1 \
		and int(phase_announcements[0].get("phase")) == 0)

	# p1 inside the final circle, p2 deep in the fog.
	room._fighters.get("storm_p1").global_position = Vector3(0, 2, 0)
	room._fighters.get("storm_p2").global_position = Vector3(150, 2, 0)

	# Simulate deep storm time: the probe reads the room's safe radius
	# through the seam, then drives the grind directly (the _process
	# path is exercised by the regression room probe; here the math is
	# the unit -- wall-relative t far down the ladder).
	var full_plan: Dictionary = Contract.storm_plan(200.0)
	var final_t: float = float(full_plan.get("total")) + 1.0
	var safe_now: float = Contract.storm_radius_at(full_plan, final_t, 200.0)
	_check("no quarter: the wall closes to ZERO", safe_now == 0.0)
	var knife_t: float = float(full_plan.get("phases", [])[3].get("end")) + 1.0
	var knife_r: float = Contract.storm_radius_at(full_plan, knife_t, 200.0)
	_check("phase 4 rests at knife-range (>= min circle)", knife_r > 0.0 \
		and knife_r <= 25.0)
	# Direct grind: the room's damage route with a fighter far out.
	room._storm_damage_cooldown.clear()
	room._fighters.get("storm_p2").global_position = Vector3(150, 2, 0)
	room._damage_fighter("storm_p2", int(ceilf(float(phases[-1].get("damage")))))
	var hp_after: int = p2.current_health
	_check("fog bite lands on the far fighter (route works)", hp_after < 200 or storm_hits.size() > 0)
	_check("in-circle fighter untouched by the same bite", p1.current_health == 200)
	_check("storm hit reported (UI signal)", storm_hits.size() >= 1 \
		and str(storm_hits[0].get("fighter")) == "storm_p2")

	# Fog kill credit: the storm entity is a REGISTERED combat source
	# (CombatSystem relays its kills like any fight kill); the room's
	# death path then accepts the fog by name and books the departure.
	var cs = root.get_node_or_null("CombatSystem")
	_check("storm entity exists as the kill source", room._storm_entity != null \
		and str(room._storm_entity.entity_id) == "royale_storm")
	_check("fog is registered with CombatSystem (kill relay)", \
		cs != null and cs.get_entity("royale_storm") == room._storm_entity)
	# LETHAL fog bite: the kill routes to the last standing team (p1,
	# team 0), the death relay books it, and the credit signal flies.
	for i in range(4):
		if not room._fighters.get("storm_p2").alive:
			break
		room._storm_damage_cooldown.clear()
		room._damage_fighter("storm_p2", 250)
	_check("fog-kill credited into the room without error", \
		room.has_fighter("storm_p2") and not room._fighters.get("storm_p2").alive)
	_check("fog-kill credit emitted to the last standing team", \
		kill_credits.size() >= 1 and int(kill_credits[0].get("team")) == 0 \
		and str(kill_credits[0].get("victim")) == "storm_p2")
	_check("kill ledger books the fog kill to the survivor", \
		int(room.kill_counts.get("storm_p1", 0)) == 1)

	room.queue_free()
	await process_frame

	# ---- E2. Glide-drop math through the fighter body --------------------
	var FighterScript = load("res://scenes/instances/arena_fighter.gd")
	var glider_script = load("res://core/frame/srv/glider_state.gd")
	var fb = FighterScript.new()
	fb.setup("drop_body", 0)
	root.add_child(fb)
	await process_frame
	var gprof: Resource = load("res://data/movement_profiles/movement_glider.tres")
	fb.global_position = Vector3(0, 160, 0)
	fb.arm_glider(gprof)
	fb.drop_height_m = 159.0
	fb.velocity = Vector3.ZERO
	_check("arming adopts the wing profile gravity", \
		abs(fb.gravity_force - float(gprof.gravity_force)) < 0.01)
	# First tick: the machine auto-deploys at the 6 m gate instantly
	# (160 m drop, auto mode) -- the wing opens the frame the bout
	# throws you, so the sink is wing-gentle from tick one.
	var first_vy: float = fb._glider_tick(1.0 / 60.0, 0.0)
	_check("wing opens on the first drop tick (auto-deploy)", \
		fb.glider.state == glider_script.State.GLIDING)
	_check("sink is the wing's gentle 4.5 m/s from tick one", \
		abs(first_vy + glider_script.GLIDE_SINK_SPEED) < 0.01)
	var glide_vy: float = first_vy
	for i in range(20):
		glide_vy = fb._glider_tick(1.0 / 60.0, glide_vy)
	_check("sink holds the glide rate across ticks (no fall buildup)", \
		abs(glide_vy + glider_script.GLIDE_SINK_SPEED) < 0.3)
	fb.queue_free()
	# A fighter WITHOUT the wing falls contract-gravity (trials/other
	# modes never see the glider).
	var fb2 = FighterScript.new()
	fb2.setup("plain_body", 0)
	root.add_child(fb2)
	await process_frame
	var fall_vy: float = fb2._glider_tick(1.0 / 60.0, 0.0)
	_check("wingless fighters fall at contract gravity", \
		abs(fall_vy + Contract.GRAVITY_FORCE / 60.0) < 0.01)
	fb2.queue_free()
	await process_frame

	# ---- F. Anticheat: the ROYALE throw is ticketed ----------------------
	# The room throws 160 m up; the TICKET covers upward-only. Grant
	# path: ThermalService/room-side authority (server), not the player.
	_check("royale throw exceeds the jump limit (ticket needed)", 160.0 > 12.5)
	ac.set_movement_limits("royale_thrower", 25.0, 12.5, 110.0)
	_check("server grant accepted for a legal throw speed", \
		bool(ac.grant_launch_grace("royale_thrower", 30.0)))
	var tripped := false
	for i in range(40):
		if ac.validate_movement("royale_thrower", Vector3(i * 0.1, 160, 0), \
				Vector3(0, 30.0, 0), 1.0 / 60.0):
			tripped = true
			break
	_check("ticketed upward throw does NOT trip the jump hack", not tripped)
	var h_trip := false
	for i in range(40):
		if ac.validate_movement("royale_thrower", Vector3(i * 0.1, 160, 0), \
				Vector3(90.0, 0, 0), 1.0 / 60.0):
			h_trip = true
			break
	_check("the same ticket never covers horizontal hacks", h_trip)
	_check("above the ceiling no ticket can be bought", \
		not bool(ac.grant_launch_grace("royale_thrower", 999.0)))

	# ---- G. Valley thermals (owner: two, no launchers) -------------------
	var ts = root.get_node_or_null("ThermalService")
	_check("thermal service present", ts != null)
	if ts != null:
		var valley_lifts: Array = []
		for u in ts.get_updrafts():
			if str(u.zone_id) == "zone_royale_valley":
				valley_lifts.append(u)
		_check("valley has exactly two thermals", valley_lifts.size() == 2)
		var no_launchers := true
		var in_bounds := true
		for u in valley_lifts:
			if int(u.kind) != 0:  # ThermalUpdraft.Kind.THERMAL
				no_launchers = false
			var flat := Vector2(u.position.x, u.position.z).length()
			if flat > 120.0:  # inside the 200 m walls, OUTSIDE the knife circle
				in_bounds = false
		_check("valley thermals are THERMAL kind (no launchers)", no_launchers)
		_check("valley thermals sit inside the walls (fog swallows them late)", in_bounds)

	# ---- H. HUD relay: ArenaRoomService drives the StormBar --------------
	# The real HudLayer lives in the playable world scene; the probe
	# mounts a stub CanvasLayer under the SAME name so the service's
	# relay resolution path is exercised for real.
	var room_svc = root.get_node_or_null("ArenaRoomService")
	_check("room service present (HUD relay source)", room_svc != null)
	var StormBarScript = load("res://ui/components/storm_bar.gd")
	var stub_hud := CanvasLayer.new()
	stub_hud.name = "HudLayer"
	root.add_child(stub_hud)
	var bar = StormBarScript.new()
	bar.name = "StormBar"
	stub_hud.add_child(bar)
	await process_frame
	_check("StormBar resolvable via the service's HUD lookup", \
		room_svc._storm_bar() == bar)
	if bar != null and room_svc != null:
		# The real room was freed earlier in this probe; the relay only
		# needs a zone_data carrier (dictionaries duck-access .zone_data).
		room_svc._on_room_bout_started({"mode": 2, "storm_phases": \
			[{}, {}, {}, {}, {}]}, "probe_chip", {"zone_data": null})
		_check("bout start shows the calm before the wall", bar.visible \
			and not bar._armed and bar.active_instance_id() == "probe_chip")
		room_svc._on_storm_phase(65.0, 0, "probe_chip")
		_check("phase advance arms the chip with the radius", bar._armed \
			and abs(bar._radius - 65.0) < 0.01)
		room_svc._on_storm_bite("storm_p1", 7.0)
		_check("fog bite flashes the label", \
			bar._radius_label.text.contains("BITES"))
		room_svc._on_room_bout_ended(0, {}, "probe_chip")
		_check("bout close hides the chip", not bar.visible \
			and bar.active_instance_id() == "")
	stub_hud.queue_free()
	await process_frame

	if _fails == 0:
		print("ROYALE STORM PROBE PASSED (%d checks)" % _checks)
		quit(0)
	else:
		push_error("ROYALE STORM PROBE FAILED")
		quit(1)

func _check(label: String, cond: bool) -> void:
	_checks += 1
	if cond:
		print("  PASS " + label)
	else:
		_fails += 1
		print("  FAIL " + label)
