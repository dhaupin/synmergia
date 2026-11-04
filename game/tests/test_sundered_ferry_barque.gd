extends SceneTree

## Receipt: THE SUNDERED BARQUE (S14.7.3) -- the strait's scheduled
## ride becomes a physical vessel. The data route veh_sundered_barque
## (6 casts/day, first at 5.5 h, 0.6 h crossing) existed since the
## strait rounds; the hull was the missing half. Standards:
##   1. the vessel stands under world_root with its own name;
##   2. its lane IS the two pins' own (DataService gateway truth,
##      normalized) -- never an in-file bearing;
##   3. FerryService knows her (the route status law answers);
##   4. place()'s one sea law floats her ON the waterline mid-lane,
##      bow along the travel tangent (the runner's law, second lane);
##   5. the deck pieces ride along (the piece-collider law -- the
##      deck is standable, the rider carry law unchanged).
##   6. the harbor buoys (S14.7.4): both pins carry a floating drum +
##      amber lamp ON the sea line, flank-stepped off the berth, and
##      both lamps ride the SAME night law the pier beacon does.
##   7. the dock-warp tier (S14.7.4): the wake lets a sailor step
##      between HER two pins -- the service refuses the warp before
##      the rides are wake-known, pays it after, and the world's
##      landing law clamps the body at or above the water line.
## Run: godot --headless --path . --script res://tests/test_sundered_ferry_barque.gd

var _passed: int = 0
var _failed: int = 0

func _ok(msg: String) -> void:
	_passed += 1
	print("  PASS ", msg)

func _fail(msg: String) -> void:
	_failed += 1
	print("  FAIL ", msg)

func _finish() -> void:
	print("--- SUNDERED BARQUE RECEIPT: %d checks, %d failed ---" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var FV = load("res://entities/ferry_vessel.gd")
	var Gen = load("res://scenes/worlds/terrain_gen.gd")
	var DS = root.get_node_or_null("DataService")
	var FS = root.get_node_or_null("FerryService")
	var sim_root := Node3D.new()
	root.add_child(sim_root)
	if FS != null and FS.has_method("ensure_loaded"):
		FS.call("ensure_loaded")

	# --- 1. THE DATA TRUTH ------------------------------------------------
	var ferry = FS.get_ferry("veh_sundered_barque") if FS != null else null
	_check_line("FerryService declares the barque", ferry != null)
	var ok: bool = ferry != null and ferry.route_gateways != null \
		and ferry.route_gateways.size() >= 2
	_check_line("the barque route names two pins", ok)
	if not ok:
		_finish()
		return
	var st: Dictionary = FS.route_status("veh_sundered_barque")
	_check_line("route status is honest", st.has("status"))
	var g1 = DS.get_gateway("waypoint_strait_moor") if DS != null and DS.has_method("get_gateway") else null
	var g2 = DS.get_gateway("waypoint_strait_seaward") if DS != null and DS.has_method("get_gateway") else null
	_check_line("the moor pin resolves in gateway data", g1 != null)
	_check_line("the seaward pin resolves in gateway data", g2 != null)
	if g1 == null or g2 == null:
		_finish()
		return

	# --- 2. THE BUILD ------------------------------------------------------
	var moor: Vector3 = (g1.source_position as Vector3).normalized()
	var seaward: Vector3 = (g2.source_position as Vector3).normalized()
	_check_line("the lane is a real arc (both pins radial)", moor.length() > 0.9 and seaward.length() > 0.9)
	var world_seed := PackedByteArray()
	var wd = load("res://data/worlds/world_main.tres")
	if wd != null and "seed" in wd:
		world_seed = wd.seed
	var sea: float = Gen.sea_level(world_seed)
	var RADIUS: float = 20000.0
	# THE WALK TRUTH: the real terrain law (the same callable shape the
	# streamer hands the runner) -- at sea dirs it reads the seabed, so
	# place()'s max(walk, sea) is exercised for real.
	var walk: Callable = func(d: Vector3) -> float:
		return float(Gen.terrain_height(d, world_seed))
	var barque: Node3D = FV.build_barque(sim_root, moor, seaward,
		RADIUS, 0.52, walk, sea)
	_check_line("the vessel is named SunderedBarque", barque != null and barque.name == "SunderedBarque")
	_check_line("the hull is standing with deck pieces", barque.get_node_or_null("DeckPanel") != null
		and barque.get_node_or_null("Hull") != null)
	var colliders: Array = barque.get_meta("colliders")
	_check_line("the hull collides in pieces", colliders != null and colliders.size() == 4)
	var lane_a: Vector3 = barque.get_meta("lane_a")
	var lane_b: Vector3 = barque.get_meta("lane_b")
	_check_line("the lane IS the two pins", lane_a.angle_to(moor) < 0.001
		and lane_b.angle_to(seaward) < 0.001)

	# --- 3. THE SEA LAW (the runner's law, second lane) --------------------
	# Mid-lane the hull floats ON the waterline: the radius sits between
	# the sea surface and the sea surface + the float lift (the draft).
	var at_mid := Transform3D()
	FV.place(barque, 0.5)
	at_mid = barque.global_transform
	var mid_dir: Vector3 = at_mid.origin.normalized()
	var mid_r: float = at_mid.origin.length()
	var sea_line: float = RADIUS + sea
	_check_line("mid-lane the hull floats on the sea line",
		mid_r >= sea_line - 0.01 and mid_r <= sea_line + 2.0)
	var up_d: Vector3 = at_mid.basis.y
	_check_line("the hull's up is radial", up_d.dot(mid_dir) > 0.99)
	# Berths: t=0 Meditation-side? NO -- t=0 is the MOOR end, t=1 the
	# seaward pin; the two ends ride their berth lifts (not the deep).
	FV.place(barque, 0.0)
	var moor_r: float = barque.global_transform.origin.length()
	FV.place(barque, 1.0)
	var far_r: float = barque.global_transform.origin.length()
	_check_line("the moor berth lifts clear of the sea line",
		moor_r >= sea_line - 0.01 and moor_r < sea_line + 6.0)
	_check_line("the seaward berth lifts clear of the sea line",
		far_r >= sea_line - 0.01 and far_r < sea_line + 6.0)
	# She is exactly ON her lane: the berth dir under her matches its pin.
	FV.place(barque, 0.0)
	var moor_dir: Vector3 = barque.global_transform.origin.normalized()
	_check_line("t=0 berths at the moor pin", moor_dir.angle_to(moor) < 0.002)
	FV.place(barque, 1.0)
	var far_dir: Vector3 = barque.global_transform.origin.normalized()
	_check_line("t=1 berths at the seaward pin", far_dir.angle_to(seaward) < 0.002)

	# --- 4. THE HARBOR BUOYS (S14.7.4) --------------------------------------
	var HLB = load("res://entities/harbor_lights.gd")
	var buoys: Array = HLB.build_strait_buoys(sim_root, RADIUS, 0.52, moor, seaward, sea)
	_check_line("the two pins carry their buoys", buoys.size() == 2
		and str(buoys[0].name) == "StraitBuoyMoor" and str(buoys[1].name) == "StraitBuoySeaward")
	var buoy_r: float = (buoys[0].global_transform.origin).length()
	_check_line("the buoy rides ON the sea line", absf(buoy_r - sea_line) < 3.0)
	_check_line("the buoy stands OFF its berth pin",
		(buoys[0].global_transform.origin.normalized()).angle_to(moor) > 0.0005)
	var lamp_mat: Material = buoys[0].get_meta("lamp")
	_check_line("the buoy lamp carries the night law's flip",
		lamp_mat != null and lamp_mat is StandardMaterial3D)
	if lamp_mat != null:
		HLB.place_night(buoys[0], 0.77)  # dusk (18.4 h)
		_check_line("the buoy lamp is lit at dusk", lamp_mat.emission_enabled)
		HLB.place_night(buoys[0], 0.30)  # dawn (7.2 h)
		_check_line("the buoy lamp sleeps to the sun", not lamp_mat.emission_enabled)

	# --- 5. THE DOCK-WARP TIER (S14.7.4) ------------------------------------
	var sailor := "probe_wake_sailor"
	var rides: int = FS.rides_recorded(sailor, "veh_sundered_barque") \
		if FS.has_method("rides_recorded") else 0
	if rides == 0:
		var refused: Dictionary = FS.warp_wake(sailor, "veh_sundered_barque", "waypoint_strait_moor")
		_check_line("the wake refuses the unearned warp",
			refused.get("ok") == false and str(refused.get("reason", "")).contains("not yours yet"))
		for k in range(3):
			var paid: Dictionary = FS.record_deck_wake(sailor, "veh_sundered_barque", "waypoint_strait_moor")
			_check_line("deck wake %d is honest" % (k + 1), bool(paid.get("ok")))
		_check_line("the wake is known after three crossings",
			FS.wake_is_known(sailor, "veh_sundered_barque"))
	var warped: Array = []
	FS.wake_warped.connect(func(pid: String, vid: String, gid: String) -> void:
		warped.append([pid, vid, gid]))
	var warp: Dictionary = FS.warp_wake(sailor, "veh_sundered_barque", "waypoint_strait_moor")
	_check_line("the wake pays the earned warp", bool(warp.get("ok")))
	_check_line("the wake signal names her vehicle and pin",
		warped.size() == 1 and warped[0][1] == "veh_sundered_barque"
		and warped[0][2] == "waypoint_strait_moor")

	# THE WORLD'S LANDING LAW: the barque branch clamps the body at or
	# above the water line (runner's wake landing law, second lane).
	var GW: GDScript = load("res://scenes/worlds/globe_world.gd")
	var world := Node3D.new()
	world.set_script(GW)
	world.set("planet_radius", RADIUS)
	world.set("streamer", _sea_streamer_stub(world_seed))
	world.set("sund_ferry_vessel", barque)
	world.set("_barque_pier_gateway", "waypoint_strait_moor")
	world.set("_barque_pans_gateway", "waypoint_strait_seaward")
	var land_moor: Vector3 = world._barque_wake_landing("waypoint_strait_moor")
	_check_line("the moor landing stands ON the barque lane",
		land_moor.normalized().angle_to(moor) < 0.001)
	var sea_stub: float = Gen.sea_level(world_seed)
	_check_line("a seabed walk never lands under the sea line",
		land_moor.length() >= RADIUS + sea_stub + 1.5)
	var land_far: Vector3 = world._barque_wake_landing("waypoint_strait_seaward")
	_check_line("the seaward landing stands on her second pin",
		land_far.normalized().angle_to(seaward) < 0.001)
	_check_line("a foreign pin has no barque landing",
		world._barque_wake_landing("waypoint_capitol_pier") == Vector3.INF)
	world.free()

	_finish()

func _check_line(cond_label: String, cond: bool) -> void:
	if cond:
		_ok(cond_label)
	else:
		_fail(cond_label)


## A real-streamer-shape stub for the landing law: world_seed from the
## world data; the walk law returns a SEABED read (a pin at sea must
## still land the body AT the water line, never under it).
func _sea_streamer_stub(seed_bytes: PackedByteArray):
	var scr := GDScript.new()
	scr.source_code = "extends RefCounted\nvar world_seed := PackedByteArray()\nfunc walk_surface_h(d: Vector3) -> float:\n\treturn -30.0\n"
	scr.reload()
	var stub = scr.new()
	stub.world_seed = seed_bytes
	return stub
