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

	_finish()

func _check_line(cond_label: String, cond: bool) -> void:
	if cond:
		_ok(cond_label)
	else:
		_fail(cond_label)
