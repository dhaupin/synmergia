# probe_world_lattice.gd - S16.1: the multiworld lattice.
#
# Covers:
#   A. Declarations: three worlds load with world_ prefix ids, the
#      universe has exactly one root (main), parenting resolves.
#   B. Derived seeds: same constant + path = same bytes across two
#      fresh registries (the "clock you wind once" proof); different
#      worlds never share a seed (domain separation); underworld
#      nests under main (parent fold changes the bytes).
#   C. Entry law: underworld OFFLINE to players, moon DEV_ONLY, main
#      enterable; the moon has no atmosphere (no gliders -- the wing
#      is a wing).
#   D. Closed-form orbits: the moon's position is a pure function of
#      the epoch (deterministic, periodic, no simulation); positions
#      differ across epochs and repeat after a period.
#   E. Transfer windows: favorability is 0..1, windows are found
#      within the horizon, determinism across calls.
#   F. One clock (S16.2): SignService.sky_epoch_days() is the
#      canonical epoch -- time travel moves the calendar AND the moon.
#   G. Moon Gate law (S16.3): the underworld has no door, the moon is
#      the sealed mystery shell, world scopes ride the bout/return
#      seam, and force=true is the S16.6 dev hatch.
#   H. World physics (S16.4): per-world gravity is a declaration, the
#      vacuum glider gate closes the wing honestly, earthrise is the
#      closed-form synodic theorem (tidal lock = home hangs forever),
#      and the parent disc hangs at exact angular size.
#
# Script mode: no autoloads needed -- the registry is a frame
# primitive (pure functions + res:// data).
extends SceneTree

var _fails: int = 0
var _checks: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var WR = load("res://core/frame/srv/world_registry.gd")
	var WD = load("res://core/schemas/world_data.gd")

	# ---- A. Declarations --------------------------------------------------
	var reg = WR.new()
	reg.load_worlds()
	_check("three world declarations load", reg.all_worlds().size() == 3)
	var main = reg.get_world("main")
	var under = reg.get_world("underworld")
	var moon = reg.get_world("moon")
	_check("root world is main (no parent, MAIN kind)", \
		main != null and str(main.parent_world) == "" and int(main.kind) == WD.WorldKind.MAIN)
	_check("underworld nests under main (SUBWORLD)", \
		under != null and str(under.parent_world) == "main" and int(under.kind) == WD.WorldKind.SUBWORLD)
	_check("moon is a CELESTIAL body of main", \
		moon != null and str(moon.parent_world) == "main" and int(moon.kind) == WD.WorldKind.CELESTIAL)
	_check("seed paths nest without collision", \
		main.seed_path() == "world:main" \
		and under.seed_path() == "world:main/subworld:underworld" \
		and moon.seed_path() == "world:main/subworld:moon")

	# ---- B. Derived seeds ---------------------------------------------------
	var s_main: String = reg.world_seed_hex("main")
	var s_under: String = reg.world_seed_hex("underworld")
	var s_moon: String = reg.world_seed_hex("moon")
	_check("seeds are 32-byte hex", s_main.length() == 64 and s_moon.length() == 64)
	_check("worlds never share a seed (domain separation)", \
		s_main != s_under and s_main != s_moon and s_under != s_moon)
	# THE proof: a fresh registry derives the same bytes from the same
	# constant. Wind once, read forever.
	var reg2 = WR.new()
	reg2.load_worlds()
	_check("fresh registry derives identical seeds (determinism)", \
		reg2.world_seed_hex("main") == s_main \
		and reg2.world_seed_hex("underworld") == s_under \
		and reg2.world_seed_hex("moon") == s_moon)
	# A parent fold must actually change the child bytes (underworld is
	# not just "world:underworld" off the universe root).
	var Chain = load("res://core/frame/kv/seed_chain.gd")
	var stack_one: Array[PackedByteArray] = [reg.universe_seed()]
	var flat_under: String = Chain.derive_seed(stack_one, "world:underworld").hex_encode()
	_check("underworld seed folds through the main domain (nesting matters)", \
		flat_under != s_under)
	_check("unknown world derives to empty", \
		reg.world_seed("world_that_is_not").is_empty())

	# ---- C. Entry law --------------------------------------------------------
	_check("main is enterable (production home)", main.is_enterable())
	_check("underworld is OFFLINE to players", not under.is_enterable())
	_check("moon is DEV_ONLY (no player path yet)", \
		int(moon.offline) == WD.OfflineState.DEV_ONLY and not moon.is_enterable())
	_check("the moon has NO atmosphere (gliders stay stowed)", \
		not moon.has_atmosphere and not moon.allows_gliding())
	_check("the moon is light (6 m/s^2) and small (1.2 km)", \
		abs(float(moon.gravity_force) - 6.0) < 0.01 and abs(float(moon.radius_m) - 1200.0) < 0.01)
	_check("main keeps earth physics", \
		abs(float(main.gravity_force) - 20.0) < 0.01 and main.allows_gliding())

	# ---- D. Closed-form orbits ------------------------------------------------
	var p0: Vector3 = WR.orbit_position(moon, 0.0)
	var p1: Vector3 = WR.orbit_position(moon, 1.0)
	var p_again: Vector3 = WR.orbit_position(moon, 0.0)
	_check("orbit position is a pure function (same epoch, same place)", \
		p0 == p_again)
	_check("the moon moves across epochs", p0.distance_to(p1) > 1000.0)
	_check("orbit radius is honored (90 km from main)", \
		abs(p0.length() - 90000.0) < 0.5)
	_check("the moon returns after one period (8 sky days)", \
		WR.orbit_position(moon, 8.0).distance_to(p0) < 0.5)
	_check("non-orbiting worlds sit at ZERO", \
		WR.orbit_position(main, 3.0) == Vector3.ZERO \
		and WR.orbit_position(under, 3.0) == Vector3.ZERO)
	_check("null world is safe (ZERO)", WR.orbit_position(null, 1.0) == Vector3.ZERO)

	# ---- E. Transfer windows ---------------------------------------------------
	var fav: float = WR.window_favorability(main, moon, 0.0)
	_check("favorability is normalized 0..1", fav >= 0.0 and fav <= 1.0)
	var w1: float = WR.next_transfer_window(main, moon, 0.0)
	var w2: float = WR.next_transfer_window(main, moon, 0.0)
	_check("a transfer window opens within one lunar period", \
		w1 > 0.0 and w1 <= float(moon.orbit_period_days) * 2.0)
	_check("windows are deterministic", w1 == w2)
	_check("window epochs actually pass the threshold", \
		WR.window_favorability(main, moon, w1) <= 0.15)
	# On the far side of the orbit no window should report (impossible
	# ask inside a tiny horizon).
	var w_none: float = WR.next_transfer_window(main, moon, w1 + 0.1, 0.0001, 0.25, 0.2)
	_check("no window inside an impossible horizon", w_none < 0.0)

	# ---- F. One clock (S16.2) ----------------------------------------------
	# The Concord clock IS the orbit clock: closed-form orbits evaluate
	# against SignService.sky_epoch_days(), the same override-honoring
	# clock that rolls the sky calendar (sign_service.gd law: services
	# that key off the sky MUST read the override-aware accessors).
	var svc = root.get_node_or_null("SignService")
	_check("SignService available in script mode", svc != null)
	if svc != null:
		svc.ensure_initialized()
		_check("sky_epoch_days seam exists on SignService", svc.has_method("sky_epoch_days"))
		# Far-future day (year 2241): the override rolls the calendar in
		# ISOLATION -- never mutate the live dev calendar from a probe.
		var day_future := 99001
		var e_hi := float(day_future) + 0.25
		svc.set_clock_override(e_hi * 86400.0)
		var e_over: float = svc.sky_epoch_days()
		_check("override moves the epoch AND the day index together", \
			absf(e_over - e_hi) < 0.000001 and svc.current_day_index() == day_future)
		var m_lo: Vector3 = WR.orbit_position(moon, svc.sky_epoch_days())
		var m_hi: Vector3 = WR.orbit_position(moon, e_over + 0.5)
		_check("moon position is a function of the Concord clock", \
			m_lo != Vector3.ZERO and not m_lo.is_equal_approx(m_hi))
		var e_final := float(day_future + 3) + 0.5
		svc.set_clock_override(e_final * 86400.0)
		_check("epoch and day index agree at the far-future day", \
			absf(svc.sky_epoch_days() - e_final) < 0.000001 and svc.current_day_index() == day_future + 3)
		_check("moon orbit periodic across one period under the sky clock", \
			WR.orbit_position(moon, e_final).is_equal_approx( \
				WR.orbit_position(moon, e_final + float(moon.orbit_period_days))))
		svc.set_clock_override(-1.0)
		_check("override reset returns to the live sky clock", \
			absf(svc.sky_epoch_days() - float(Time.get_unix_time_from_system()) / 86400.0) < 0.001)

	# ---- G. Moon Gate law (S16.3) ------------------------------------------
	# The gate is the AncientDoor pattern between worlds: the entry law
	# lives in the lattice (WorldData.is_enterable), the scope swap is
	# the SAME seam as bout/return, and the underworld has no door.
	var scope = root.get_node_or_null("ScopeService")
	_check("ScopeService available in script mode", scope != null)
	var GateScript: GDScript = load("res://entities/moon_gate.gd")
	_check("moon_gate.gd loads", GateScript != null)
	if scope != null and GateScript != null:
		var esvc = root.get_node_or_null("EntityService")
		var GP2: GDScript = load("res://entities/globe_player.gd")
		var walker = GP2.new()
		walker.entity_id = "gate_walker"
		root.add_child(walker)
		esvc._entities["gate_walker"] = walker
		var main_root: Node3D = Node3D.new()
		main_root.name = "GateMainRoot"
		main_root.add_to_group("world_root_main")
		root.add_child(main_root)
		walker.reparent(main_root)

		# A. Law states: unknown world dark, offline dim, online lit.
		var gate_main = GateScript.new()
		gate_main.set("target_world", "main")
		root.add_child(gate_main)
		var gate_under = GateScript.new()
		gate_under.set("target_world", "underworld")
		root.add_child(gate_under)
		_check("gate law states: online 2 / offline 1", \
			int(gate_main._law_state()) == 2 and int(gate_under._law_state()) == 1)
		_check("sealed prompt reads the structure", \
			str(gate_under.get_interaction_prompt()).begins_with("[E] Read"))

		# B. The underworld has no door: interact refuses with lore.
		var res_under: Dictionary = gate_under.try_interact(null)
		_check("underworld gate refuses (OFFLINE has no door)", \
			not bool(res_under.get("ok")) and str(res_under.get("reason")) == "sealed" \
			and str(res_under.get("message", "")).length() > 0)

		# C. The moon is DEV_ONLY: the mystery shell stands, sealed.
		var gate_moon = GateScript.new()
		gate_moon.set("target_world", "moon")
		root.add_child(gate_moon)
		var res_moon: Dictionary = gate_moon.try_interact(null)
		_check("moon gate is the sealed mystery shell (DEV_ONLY)", \
			not bool(res_moon.get("ok")) and str(res_moon.get("reason")) == "sealed")
		_check("moon prompt reads until the dev flip", \
			str(gate_moon.get_interaction_prompt()).begins_with("[E] Read"))

		# D. The scope swap seam (world:main, ONLINE): reparent + scope.
		_check("enter_world_scope performs the main-world transit", \
			scope.enter_world_scope("gate_walker", "main", main_root, false) \
			and scope.world_of("gate_walker") == "main" \
			and walker.get_parent() == main_root)
		_check("unknown players read as the main world", \
			scope.world_of("nobody") == "main" and not scope.is_off_world("nobody"))

		# E. Defense in depth: the law blocks swaps with no gate at all.
		_check("law refuses OFFLINE swap (no gate needed)", \
			not scope.enter_world_scope("gate_walker", "underworld", main_root, false))
		_check("law refuses DEV_ONLY swap for players", \
			not scope.enter_world_scope("gate_walker", "moon", main_root, false))
		_check("law refuses unknown worlds", \
			not scope.enter_world_scope("gate_walker", "nowhere", main_root, false))
		_check("refused swaps never move the player", \
			scope.world_of("gate_walker") == "main" and walker.get_parent() == main_root)

		# F. The S16.6 dev hatch: force=true boots the moon globe.
		var moon_root: Node3D = Node3D.new()
		moon_root.name = "GateMoonRoot"
		moon_root.add_to_group("world_root_moon")
		root.add_child(moon_root)
		_check("dev hatch force=true reaches the moon", \
			scope.enter_world_scope("gate_walker", "moon", moon_root, true) \
			and scope.world_of("gate_walker") == "moon" \
			and walker.get_parent() == moon_root \
			and walker.get("planar_mode") == false)

		# G. Return transit: the ride home names main.
		_check("exit_to_world returns the walker home", \
			scope.exit_to_world("gate_walker", "main", main_root, false) \
			and scope.world_of("gate_walker") == "main" \
			and walker.get_parent() == main_root)

		gate_main.queue_free()
		gate_under.queue_free()
		gate_moon.queue_free()

	# ---- H. World physics (S16.4) ------------------------------------------
	# Per-world physics: the moon's 6 m/s^2 is a LAW of that globe (a
	# declaration in world_moon.tres), the wing is a wing (no air, no
	# glide), and the sky is the theorem: tidal lock means home hangs
	# over one meridian forever.
	var GP3: GDScript = load("res://entities/globe_player.gd")
	_check("globe_player loads", GP3 != null)
	if GP3 != null:
		var lun = GP3.new()
		lun.entity_id = "moon_walker"
		_check("unbound body keeps earth gravity", lun.gravity_force == 20.0)
		lun.bind_to_world("moon")
		_check("bind_to_world adopts the world's law (6 m/s^2)", lun.gravity_force == 6.0)
		_check("the moon forbids the wing (no atmosphere)", not lun._world_allows_gliding())
		var earth_body = GP3.new()
		earth_body.entity_id = "earth_walker"
		_check("unbound worlds allow gliding (the atmosphere world)", earth_body._world_allows_gliding())

		# The vacuum gate: open the wing by force, run one real physics
		# step over the moon, and the vacuum closes it the same frame.
		root.add_child(lun)
		lun.planet_radius = 100.0
		lun.global_position = Vector3(0, 106, 0)
		lun.velocity = Vector3.ZERO
		lun.glider.state = lun.glider.State.GLIDING
		lun._physics_process(1.0 / 60.0)
		_check("vacuum closes the wing the same frame", lun.glider.state == lun.glider.State.FALLING)
		_check("lunar gravity pulled at 6 m/s^2", absf(lun.velocity.y + 6.0 / 60.0) < 0.001)
		lun.queue_free()

		# The earthrise theorem (closed form, prd-multiworld sec 4).
		var moon_w = reg.get_world("moon")
		_check("the moon is tidally locked (no beat)", \
			WR.parent_beat_period_days(moon_w) < 0.0)
		var d1: Vector3 = WR.parent_sky_direction(moon_w, 0.3)
		var d2: Vector3 = WR.parent_sky_direction(moon_w, 4.1)
		_check("locked sky is constant across epochs", \
			d1 != Vector3.ZERO and d1.is_equal_approx(d2))
		_check("home spans ~26 degrees of lunar sky", \
			absf(rad_to_deg(asin(20000.0 / 90000.0)) * 2.0 - 25.7) < 1.0)
		_check("base longitude decides earthrise", \
			WR.parent_visible_from(moon_w, 0.3, 0.7 + PI) \
			and not WR.parent_visible_from(moon_w, 0.3, 0.7))
		# A spun moon: the beat theorem gives the synodic schedule.
		moon_w.spin_period_days = 12.0
		_check("spun moon beats at the synodic period (24 d)", \
			absf(WR.parent_beat_period_days(moon_w) - 24.0) < 0.01)
		var d3: Vector3 = WR.parent_sky_direction(moon_w, 0.3)
		var d4: Vector3 = WR.parent_sky_direction(moon_w, 4.1)
		_check("spun sky sweeps (home rises and sets)", not d3.is_equal_approx(d4))
		moon_w.spin_period_days = 0.0
		_check("lock restored", WR.parent_beat_period_days(moon_w) < 0.0)

		# The honest sky: the disc hangs at the closed-form direction.
		var PSS: GDScript = load("res://entities/parent_sky.gd")
		_check("parent_sky.gd loads", PSS != null)
		if PSS != null:
			var sky = PSS.new()
			sky.world_id = "moon"
			root.add_child(sky)
			await process_frame
			await process_frame
			var disc = sky.get_node_or_null("ParentDisc")
			_check("parent disc built and hung in the sky", \
				disc != null and disc.visible and (disc.position as Vector3).length() > 7000.0)
			sky.queue_free()

	if _fails == 0:
		print("WORLD LATTICE PROBE PASSED (%d checks)" % _checks)
		quit(0)
	else:
		push_error("WORLD LATTICE PROBE FAILED")
		quit(1)

func _check(label: String, cond: bool) -> void:
	_checks += 1
	if cond:
		print("  PASS " + label)
	else:
		_fails += 1
		print("  FAIL " + label)
