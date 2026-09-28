## Instances/lobby contract probe (prd-spherical-mvp.md S9)
## Verifies the S9 contract end to end:
##   A. Contract constants: instances are PLANAR (-Y gravity, force
##      20.0) whatever the world shape says; deadline override.
##   B. Lobby-state math: OPEN/FULL/LOCKED/CLOSED derivation + party
##      fits (pure functions of the ZoneManager instance dict shape).
##   C. Arena ZoneData: zone_ prefix == filename == id, instanced
##      flag, capacity 12, deadline override, FREE_PVP.
##   D. Service: join routes to a live instance, fills to capacity 8,
##      the 13th queues (capacity_ok=false), lobby transitions
##      OPEN -> FULL, forced-seam routing, contract served per zone.
## Run: godot --headless --path . --script res://tests/test_instance_contract.gd
extends SceneTree

const ContractScript := "res://core/schemas/instance_contract.gd"

var _fails := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var Contract := load(ContractScript)

	# ---- A. Contract constants --------------------------------------
	var g: Dictionary = Contract.gravity_contract()
	_check("planar gravity contract shape", \
		g.get("shape") == "planar" and g.get("up_direction") == Vector3(0, 1, 0))
	_check("gravity force is the shared 20.0", float(g.get("gravity_force")) == 20.0)
	var stub_deadline: RefCounted = load(ContractScript).new()
	_check("deadline default falls back (20)", \
		Contract.entry_deadline(stub_deadline) == Contract.DEFAULT_ENTRY_DEADLINE)

	# ---- B. Lobby-state math (plain dicts, no autoloads needed) ------
	# zdata is a duck-read: the plain dict carries instance_capacity.
	var inst := {"zone_data": {"instance_capacity": 2}, "players": []}
	_check("empty lobby is OPEN", Contract.lobby_state_for(inst, false) == Contract.LobbyState.OPEN)
	inst.players = [1]
	_check("one seat left is OPEN", Contract.lobby_state_for(inst, false) == Contract.LobbyState.OPEN)
	inst.players = [1, 2]
	_check("at capacity is FULL", Contract.lobby_state_for(inst, false) == Contract.LobbyState.FULL)
	_check("started is LOCKED even at capacity", Contract.lobby_state_for(inst, true) == Contract.LobbyState.LOCKED)
	_check("CLOSED for missing instance", Contract.lobby_state_for({}, false) == Contract.LobbyState.CLOSED)
	inst.players = [1]
	_check("party of 1 fits the last seat", Contract.party_fits(inst, 1, false))
	_check("party of 2 does not fit one seat", not Contract.party_fits(inst, 2, false))
	inst.players = []
	_check("party of 2 fits an empty 2-cap instance", Contract.party_fits(inst, 2, false))
	_check("party of 3 does not fit (2-cap)", not Contract.party_fits(inst, 3, false))
	inst.players = [1, 2]
	_check("no party fits a started instance", not Contract.party_fits(inst, 1, true))
	var unlimited := {"zone_data": {"instance_capacity": 0}, "players": [1, 2, 3]}
	_check("capacity 0 is unlimited", Contract.party_fits(unlimited, 50, false))

	# ---- C. Arena ZoneData ------------------------------------------
	var packed: Resource = load("res://data/zones/zone_arena_coliseum.tres")
	_check("arena zone loads", packed != null)
	if packed != null:
		var arena: Resource = packed
		_check("arena id == filename stem", arena.id == "zone_arena_coliseum")
		_check("arena is instanced", arena.is_instanced)
		_check("arena capacity 12 (full 6v6)", arena.instance_capacity == 12)
		_check("arena mode ELIMINATION", arena.instance_mode == Contract.InstanceMode.ELIMINATION)
		var arena_rules: Dictionary = Contract.bout_rules(arena)
		_check("arena rules: no respawn, no kill target", \
			not bool(arena_rules.get("respawn_allowed")) \
			and int(arena_rules.get("kill_target")) == 0)
		_check("arena FREE_PVP", arena.pvp_mode == ZoneData.PvPZoneMode.FREE_PVP)
		_check("arena deadline override (60)", Contract.entry_deadline(arena) == 60.0)
		_check("arena planar contract served", \
			Contract.gravity_contract().get("shape") == "planar")

	# ---- C2. Instance modes on disk (all three modes exist) ----------
	var sandpit: Resource = load("res://data/zones/zone_arena_sandpit.tres")
	_check("sandpit zone loads", sandpit != null)
	if sandpit != null:
		_check("sandpit mode TEAM_DEATHMATCH", \
			sandpit.instance_mode == Contract.InstanceMode.TEAM_DEATHMATCH)
		var sp_rules: Dictionary = Contract.bout_rules(sandpit)
		_check("sandpit rules: respawn + kill target 20 + shield 4", \
			bool(sp_rules.get("respawn_allowed")) \
			and int(sp_rules.get("kill_target")) == 20 \
			and float(sp_rules.get("spawn_shield_seconds")) == 4.0)
		_check("sandpit time limit 480 from zone override", \
			float(sp_rules.get("time_limit_seconds")) == 480.0)
	var valley: Resource = load("res://data/zones/zone_royale_valley.tres")
	_check("valley zone loads", valley != null)
	if valley != null:
		_check("valley mode ROYALE", \
			valley.instance_mode == Contract.InstanceMode.ROYALE)
		var vr_rules: Dictionary = Contract.bout_rules(valley)
		_check("valley rules: no respawn, 15 min cap", \
			not bool(vr_rules.get("respawn_allowed")) \
			and float(vr_rules.get("time_limit_seconds")) == 900.0)
		_check("valley seats 30", valley.instance_capacity == 30)
	var null_rules: Dictionary = Contract.bout_rules(null)
	_check("bout_rules(null) is elimination default", \
		int(null_rules.get("mode")) == Contract.InstanceMode.ELIMINATION \
		and float(null_rules.get("time_limit_seconds")) == Contract.DEFAULT_TIME_LIMIT_SECONDS)

	# ---- D. Service behaviors (real autoloads via get_node_or_null) --
	var isvc = root.get_node_or_null("InstanceService")
	var zm = root.get_node_or_null("ZoneManager")
	_check("InstanceService autoload present", isvc != null)
	_check("ZoneManager autoload present", zm != null)
	if isvc != null and zm != null:
		# Script-mode boots do not run autoload _ready chains for zone
		# registration; load the .tres zones exactly like the boot does,
		# then re-read the service's arena registry (it was built before
		# any zones existed in this boot).
		zm.load_zones()
		isvc.refresh_registry()
		_check("deadline override wins (45)", _deadline_case(Contract, 45.0) == 45.0)
		_check("arena zone registered in ZoneManager", \
			zm.get_zone("zone_arena_coliseum") != null)
		_check("service sees arena as instanced zone", \
			isvc.is_instanced_zone("zone_arena_coliseum"))

		var contract: Dictionary = isvc.get_contract("zone_arena_coliseum")
		_check("service contract: planar", contract.get("shape") == "planar")
		_check("service contract: capacity 12", int(contract.get("capacity")) == 12)
		_check("service contract: deadline 60", float(contract.get("entry_deadline")) == 60.0)
		var other: Dictionary = isvc.get_contract("zone_nexus_central")
		_check("unknown zone gets shared constants (cap 0)", \
			other.get("shape") == "planar" and int(other.get("capacity")) == 0)

		# Real Entity stubs: entity_id + level 1 (can_enter passes).
		var p1 = _make_stub("probe_fighter_1")
		var join1: Dictionary = isvc.join_instance(p1, "zone_arena_coliseum")
		_check("solo join accepted", bool(join1.get("capacity_ok")))
		var iid: String = str(join1.get("instance_id", ""))
		_check("join returns an instance id", iid != "")
		_check("live_instance_id routes to the joined instance", \
			isvc.live_instance_id("zone_arena_coliseum") == iid)
		_check("joined entity is in the instance zone", \
			zm.get_entity_zone_id(p1) == iid)
		_check("lobby OPEN after first join", \
			isvc.get_lobby_state("zone_arena_coliseum") == Contract.LobbyState.OPEN)

		# Fill the remaining 11 seats (capacity 12 total).
		var filled := 1
		for i in range(11):
			var pj = _make_stub("probe_fighter_%d" % (i + 2))
			var r: Dictionary = isvc.join_instance(pj, "zone_arena_coliseum")
			if bool(r.get("capacity_ok")):
				filled += 1
		_check("seats fill to 12 (got %d)" % filled, filled == 12)
		_check("lobby FULL at capacity", \
			isvc.get_lobby_state("zone_arena_coliseum") == Contract.LobbyState.FULL)

		# The 9th must queue: join refused, existing instance kept.
		var p13 = _make_stub("probe_queued_thirteenth")
		var r13: Dictionary = isvc.join_instance(p13, "zone_arena_coliseum")
		_check("13th join queues (capacity_ok=false)", \
			not bool(r13.get("capacity_ok")))
		_check("queued join did not create a new instance", \
			isvc.live_instance_id("zone_arena_coliseum") == iid)

		# Forced-seam routing: a second live instance for the same
		# base zone; the seam returns it directly.
		var iid2: String = zm.create_instance("zone_arena_coliseum")
		isvc._force_instance("zone_arena_coliseum", iid2)
		var p10 = _make_stub("probe_forced_seam")
		var r10: Dictionary = isvc.join_instance(p10, "zone_arena_coliseum")
		_check("forced seam routes to the forced instance", \
			str(r10.get("instance_id", "")) == iid2 and bool(r10.get("capacity_ok")))

		# Cleanup: destroy created instances so the KV store stays
		# clean for later boots.
		isvc._forced_instance.clear()
		zm.destroy_instance(iid)
		zm.destroy_instance(iid2)

	# ---- E. S11 primitives (locked owner decisions) -------------------
	_check_s11_primitives(Contract)

	if _fails == 0:
		print("INSTANCE CONTRACT PROBE PASSED")
		quit(0)
	else:
		push_error("INSTANCE CONTRACT PROBE FAILED")
		quit(1)


## ---- S11 primitives (locked owner decisions, 2026-09-28) ------------
func _check_s11_primitives(Contract) -> void:
	# Scatter: golden-angle ring, index 0 on +X, height preserved.
	var s0: Vector3 = Contract.scatter_spawn(Vector3(10, 4, 10), 0)
	_check("scatter 0 on +X of ring", s0.distance_to(Vector3(13, 4, 10)) < 0.001)
	_check("scatter deterministic", \
		Contract.scatter_spawn(Vector3.ZERO, 7) == Contract.scatter_spawn(Vector3.ZERO, 7))
	# Bands: base 10, widening halves distance, gulfs never pass.
	_check("band base: 25 vs 30 ok", Contract.level_band_ok(25, 30))
	_check("band base: 25 vs 36 refused", not Contract.level_band_ok(25, 36))
	_check("band widens at 30 s wait", Contract.level_band_ok(25, 36, 30.0))
	_check("gulf never auto-passes", not Contract.level_band_ok(5, 60, 999.0))
	# Power: capped normalize; ratio 2 ceiling keeps levels meaningful.
	_check("normalize caps at ratio 2 (5 vs 60 -> 10)", Contract.normalized_level(5, 60) == 10)
	_check("normalize full-reaches reference (30 vs 60 -> 60)", Contract.normalized_level(30, 60) == 60)
	_check("normalize never nerfs", Contract.normalized_level(70, 60) == 70)
	# Power scale: the combat multiplier form of the same cap.
	var ps5: float = Contract.power_scale(5, 60)
	var ps70: float = Contract.power_scale(70, 60)
	_check("power_scale caps at 2.0 and never nerfs", \
		abs(ps5 - 2.0) < 0.0001 and abs(ps70 - 1.0) < 0.0001)
	var scaled: Dictionary = Contract.power_scale_target( \
		{"strength": 10, "vitality": 10, "damage_multiplier": 1.5}, 30, 60)
	_check("power_scale_target doubles base six, skips extras", \
		int(scaled.get("strength", 0)) == 20 and int(scaled.get("vitality", 0)) == 20 \
		and not scaled.has("damage_multiplier"))
	# AFK: zone override wins; shared default 90 s; 0 disables.
	var no_zone: float = Contract.afk_kick_seconds(null)
	_check("afk default 90 s", no_zone == 90.0)
	var z := ZoneData.new()
	z.instance_afk_kick = 45.0
	_check("afk zone override wins", Contract.afk_kick_seconds(z) == 45.0)
	z.instance_afk_kick = 0.0
	_check("afk 0 falls back to default", Contract.afk_kick_seconds(z) == 90.0)


## ZoneData duck-type case with an explicit override (45 s): a plain
## object carrying the property beats the shared default.
func _deadline_case(Contract, value: float) -> float:
	var z := ZoneData.new()
	z.instance_entry_deadline = value
	return Contract.entry_deadline(z)


func _make_stub(pid: String):
	# A real Entity stub: entity_id + level 1 satisfy ZoneData.can_enter
	# and ZoneManager bookkeeping (entity_type PLAYER lands it in the
	# instance's player roster). Not added to the scene tree -- the
	# zone machinery is data-side only. Runtime load(): parse-time
	# Entity references compile before autoloads in --script mode and
	# abort the whole probe (load-then-new is the pattern that works).
	var E: GDScript = load("res://core/entities/entity.gd")
	var e = E.new()
	e.entity_id = pid
	e.display_name = pid
	e.level = 1
	e.entity_type = E.EntityType.PLAYER
	return e


func _check(label: String, cond: bool) -> void:
	if cond:
		print("  PASS " + label)
	else:
		_fails += 1
		print("  FAIL " + label)
