extends SceneTree

## Julia bridge loop receipt (tests/test_julia_bridge.gd):
## MultiIsoService <-> srv/julia-bridge/server.jl.
##
## The bridge is best-effort: with no sidecar running every leg must
## degrade to an empty result and never crash. The LIVE legs run only
## when a server answers /health on localhost:8080, so this receipt is
## green in CI (no Julia) and proves the real loop on a dev box (Julia
## up). Run:
##   godot --headless --path . --script res://tests/test_julia_bridge.gd
##
## Server side is covered by orchestrator.jl's own self-tests
## (julia --project=. orchestrator.jl) and the GDScript<->Julia parity
## receipt (tests/test_julia_parity.gd vs presolve.jl).

const EXPECTED_MAIN_SEED := "5d8e24a05d428934c6adf4badb6cc6aa9afbaacbf4ed44c801d6a615a814603b"

var _failures: int = 0
var _svc: Node = null

func _ok(msg: String) -> void:
	print("[OK] ", msg)

func _fail(msg: String) -> void:
	_failures += 1
	printerr("[FAIL] ", msg)

func _initialize() -> void:
	_run()

func _run() -> void:
	print("--- Julia bridge loop ---")

	# 1. The service script loads and inherits Node (autoload law).
	var script: GDScript = load("res://core/services/multi_iso_service.gd")
	if script == null or not script.can_instantiate():
		_fail("multi_iso_service.gd did not load")
		quit(1)
		return
	_ok("multi_iso_service.gd loads")

	# 2. Seed parity anchor: the GDScript frame derivation the Julia
	#    worldmath.jl mirrors must still produce the canonical seed.
	var reg = load("res://core/frame/srv/world_registry.gd").new()
	reg.load_worlds()
	var main_seed: String = reg.world_seed_hex("main")
	reg = null
	if main_seed != EXPECTED_MAIN_SEED:
		_fail("world_seed(main) drifted: %s" % main_seed)
	else:
		_ok("world_seed(main) matches the Julia parity anchor")

	# 3. Fresh service instance, controlled (not the autoload) so the
	#    receipt owns its lifecycle.
	var svc: Node = script.new()
	_svc = svc
	svc.use_localhost = true
	svc.enabled = true
	root.add_child(svc)  # _ready runs: health probe + entity bind
	await process_frame
	await process_frame
	_ok("service instantiates and readies")

	# 4. Disabled mode never touches the network and returns empty.
	svc.enabled = false
	var off: Array = await svc.query_spatial(3)
	if not off.is_empty():
		_fail("disabled service returned data: %s" % str(off))
	else:
		_ok("disabled service degrades to empty (no egress)")
	svc.enabled = true

	# 5. LIVE legs: only when a server answers /health.
	var healthy: bool = await svc.is_healthy()
	if not healthy:
		print("[SKIP] no Julia sidecar on localhost:8080 -- live legs skipped")
		_report()
		return
	_ok("Julia sidecar reachable (live legs running)")

	# 6. register -> query -> unregister round-trip.
	var probe_id := "receipt_probe_%d" % Time.get_ticks_usec()
	await svc.register_entity(probe_id, 3, 7, 2, 1)
	var hits: Array = await svc.query_intersect(3, 7, 2)
	if not hits.has(probe_id):
		_fail("registered entity not found by intersect: %s" % str(hits))
	else:
		_ok("register -> multi-axis intersect finds the entity")

	await svc.unregister_entity(probe_id)
	var after: Array = await svc.query_intersect(3, 7, 2)
	if after.has(probe_id):
		_fail("unregistered entity still present: %s" % str(after))
	else:
		_ok("unregister removes the entity from every axis")

	_report()

func _report() -> void:
	if _svc != null and is_instance_valid(_svc):
		root.remove_child(_svc)
		_svc.free()
		_svc = null
	if _failures == 0:
		print("JULIA BRIDGE RECEIPT PASS")
		quit(0)
	else:
		printerr("JULIA BRIDGE RECEIPT FAIL (%d)" % _failures)
		quit(1)
