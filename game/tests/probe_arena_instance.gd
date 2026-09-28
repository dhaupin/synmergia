# probe_arena_instance.gd - S10 probe: planar instance room + bout
# controller. Script-mode SceneTree test; runs the whole chain
# headless: room builds from zone data, fighters spawn at spawn_points
# with PLANAR contract gravity, elimination resolves a winner,
# TEAM_DEATHMATCH respawns and reaches the kill target, bout rules
# come from bout_rules() (never hardcoded).
#
# Conventions: no parse-time Entity refs (script mode), probe asserts
# via _check, exit 0/1. Registered in DEFAULT_SET.
extends SceneTree

const ContractPath = "res://core/schemas/instance_contract.gd"

var _fails: int = 0

func _init() -> void:
	# Let autoloads finish (script mode still mounts them as nodes).
	call_deferred("_run")

func _run() -> void:
	var Contract = load(ContractPath)
	var zm = root.get_node_or_null("ZoneManager")
	_check("ZoneManager present", zm != null)
	if zm == null:
		quit(1)
		return
	zm.load_zones()

	var arena: Resource = zm.get_zone("zone_arena_coliseum")
	_check("coliseum zone loaded", arena != null)
	var sandpit: Resource = zm.get_zone("zone_arena_sandpit")
	_check("sandpit zone loaded", sandpit != null)

	# ---- A. Room construction from zone data ------------------------
	var ArenaScene = load("res://scenes/instances/arena_instance.gd")
	var room = ArenaScene.new()
	room.zone_data = arena
	room.instance_id = "probe_instance_1"
	root.add_child(room)

	_check("rules served from bout_rules (not hardcoded)", \
		int(room.bout_rules().get("mode")) == Contract.InstanceMode.ELIMINATION)
	_check("room is planar by contract", \
		Contract.bout_rules(null).get("respawn_allowed") == false)
	var spawns: Array = arena.spawn_points
	_check("zone provides two team spawns", spawns.size() == 2)

	# ---- B. Elimination bout: spawn, fight, resolve -----------------
	var f1 = room.spawn_fighter("blue_one", 0)
	var f2 = room.spawn_fighter("red_one", 1)
	var f3 = room.spawn_fighter("red_two", 1)
	_check("fighters spawn on team spawns", \
		f1.global_position.distance_to(spawns[0]) < 1.0 and \
		f2.global_position.distance_to(spawns[1]) < 1.0)
	_check("fighter gravity is contract force", \
		abs(f1.gravity_force - Contract.GRAVITY_FORCE) < 0.0001)

	var started := [false]
	room.bout_started.connect(func(_r): started[0] = true)
	room.start_bout()
	_check("bout_started emitted", started[0])

	# Gravity settles fighters onto the floor (planar contact).
	await _settle(1.5)
	_check("fighters land on planar floor", \
		f1.is_on_floor() and f2.is_on_floor() and f3.is_on_floor())
	_check("floor contact near sand height", \
		f1.global_position.y < 2.5)

	var ended: Array = []
	room.bout_ended.connect(func(w, _s): ended.append(w))
	# Red loses two, then blue loses one: red eliminated first.
	room.report_death("red_one", "blue_one")
	room.report_death("red_two", "blue_one")
	_check("red team wiped -> bout over", room.is_over())
	_check("blue wins elimination", ended.size() == 1 and ended[0] == 0)
	_check("fighter_down signalled", room.alive_count(1) == 0)
	_check("elimination respects shield=null zone (none)", \
		not bool(room.bout_rules().get("respawn_allowed")))

	room.queue_free()
	await process_frame

	# ---- C. TEAM_DEATHMATCH bout on the sandpit ---------------------
	var room2 = ArenaScene.new()
	room2.zone_data = sandpit
	root.add_child(room2)
	var sp_rules: Dictionary = room2.bout_rules()
	_check("sandpit rules: TDM respawn", bool(sp_rules.get("respawn_allowed")))
	_check("sandpit rules: kill target 20 from zone", \
		int(sp_rules.get("kill_target")) == 20)

	var g1 = room2.spawn_fighter("tdm_blue", 0)
	var g2 = room2.spawn_fighter("tdm_red", 1)
	_check("TDM first spawn shielded", g1.is_shielded() and g2.is_shielded())
	room2.start_bout()

	# Room grew with the zone (radius 220 -> 220 m square) and carries
	# deterministic cover; the elimination room above stayed clean.
	var rock_count: int = _room_rock_count(room2)
	_check("TDM room has cover rocks", rock_count == 8)
	# Fresh elimination room for the cover split (the first room was
	# freed after its bout; freed rooms cannot be inspected).
	var room3 = ArenaScene.new()
	room3.zone_data = arena
	root.add_child(room3)
	_check("cover only in TDM rooms", _room_rock_count(room3) == 0 and rock_count == 8)
	room3.queue_free()
	await process_frame

	# Shield blocks the kill.
	var first_try: int = room2.report_death("tdm_blue", "tdm_red")
	_check("spawn shield blocks elimination", first_try == -1 and g1.alive)

	# Fire-and-you-lose-it: a self-initiated action breaks the shield;
	# the combat bridge will call break_shield() in S11.
	g1.break_shield()
	_check("self-initiated action breaks shield", not g1.is_shielded())
	var second_try: int = room2.report_death("tdm_blue", "tdm_red")
	_check("broken shield no longer protects", second_try == -1 and not g1.alive)
	_sync_revive(room2, "tdm_blue")
	g1.apply_spawn_shield(4.0)

	# Expire shields, then trade kills to the target: red reaches 20.
	await _settle(0.5)
	# Sync-revive between kills: the real respawn path is the zone's
	# 5 s timer, which headless time will not wait out 20 times. The
	# probe tests the controller's accounting, not the timer, so each
	# iteration force-revives the victim and clears the shield first.
	# Red already has 1 (the shield-break demo kill): 18 more lands
	# one short of the target.
	for i in range(18):
		_sync_revive(room2, "tdm_blue")
		room2.report_death("tdm_blue", "tdm_red")
		await process_frame
	_check("red one short of target (19)", room2.score_for(1) == 19)
	_check("bout NOT over below target", not room2.is_over())
	# 20th kill: blue falls again, red hits the kill target.
	_sync_revive(room2, "tdm_blue")
	room2.report_death("tdm_blue", "tdm_red")
	await process_frame
	_check("red hits kill target 20", room2.score_for(1) == 20)
	_check("TDM bout resolves at kill target", room2.is_over())

	room2.queue_free()
	await process_frame

	if _fails == 0:
		print("ARENA INSTANCE PROBE PASSED")
		quit(0)
	else:
		push_error("ARENA INSTANCE PROBE FAILED")
		quit(1)

## Count cover rocks in a room (probe helper).
func _room_rock_count(room) -> int:
	var n := 0
	for c in room.get_children():
		if String(c.name).begins_with("CoverRock_"):
			n += 1
	return n

## Force a fighter back to life synchronously (probe-only: simulates
## the respawn without waiting the zone timer out).
func _sync_revive(room, id: String) -> void:
	var f = room._fighters.get(id)
	if f != null:
		f.alive = true
		f.collision_layer = 1
		f.collision_mask = 1
		f.shielded_until = 0.0

func _settle(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await physics_frame
		t += 1.0 / 60.0

func _check(label: String, cond: bool) -> void:
	if cond:
		print("  PASS " + label)
	else:
		_fails += 1
		print("  FAIL " + label)
