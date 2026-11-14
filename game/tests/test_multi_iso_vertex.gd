## MultiIso spatial-vertex receipt (tests/test_multi_iso_vertex.gd).
##
## labs/prd-perf-bridges.md: the Julia multi-iso orchestrator's spatial
## axis is only meaningful if the vertex it buckets an entity into is the
## REAL nearest icosahedron vertex to that entity's world position. Before
## this round MultiIsoService._on_entity_registered fabricated the vertex
## from the entity's team_id/faction hash, so every spatial query answered
## a lie. This receipt pins the honest law: position -> nearest vertex,
## with the faction cluster as the no-position fallback only.
##
## Legs:
##   1. A body at a known icosahedron vertex direction maps to that vertex.
##   2. An off-vertex direction maps to the nearest vertex (agrees with
##      Icosahedral's own nearest-vertex law).
##   3. planet_center is honored (the globe frame, not the world origin).
##   4. A bare body with NO position falls back to the faction bucket.
##   5. The faction bucket hashes an authored faction_id stably.
##
## Run:
##   godot --headless --path . --script res://tests/test_multi_iso_vertex.gd
extends SceneTree

const SVC_PATH := "res://core/services/multi_iso_service.gd"
const ICOSA := "res://core/frame/math/icosahedral.gd"


## A minimal body carrying the real fields the hooks duck-read. A bare
## Node3D gains NO properties from set() (script-mode lore), so the
## fields must be declared.
class FakeBody:
	extends Node3D
	var planet_center: Vector3 = Vector3.ZERO
	var team_id: int = 0
	var faction_id: String = ""
	var relation: int = 0

var _passed: int = 0
var _failed: int = 0
var _svc: Node = null


func _initialize() -> void:
	print("--- MULTI-ISO SPATIAL VERTEX ---")
	await process_frame
	var script: GDScript = load(SVC_PATH)
	if script == null or not script.can_instantiate():
		_fail("multi_iso_service.gd did not load")
		_finish()
		return
	_svc = script.new()
	_svc.enabled = false  # pure-law receipt: never egress
	root.add_child(_svc)
	await process_frame
	_test_vertex_from_position()
	_test_off_vertex()
	_test_planet_center()
	_test_no_position_fallback()
	_test_faction_bucket()
	_finish()


func _ok(msg: String) -> void:
	_passed += 1
	print("  [OK] ", msg)


func _fail(msg: String) -> void:
	_failed += 1
	printerr("  [FAIL] ", msg)


func _body(pos: Vector3) -> FakeBody:
	var n := FakeBody.new()
	n.position = pos
	return n


func _test_vertex_from_position() -> void:
	# The icosahedron vertex 0 is (0, 1, phi) normalized; place a body
	# far along that exact direction and it must bucket to vertex 0.
	var ico = load(ICOSA)
	var v0: Vector3 = ico.VERTICES[0].normalized()
	var body := _body(v0 * 20000.0)
	var got: int = _svc._vertex_for_entity(body)
	if got == 0:
		_ok("body on vertex 0 direction buckets to vertex 0")
	else:
		_fail("vertex-0 body bucketed to %d" % got)
	body.free()


func _test_off_vertex() -> void:
	# A direction between two vertices must land on the nearest one, and
	# that must agree with Icosahedral's own nearest-vertex law.
	var ico = load(ICOSA)
	var ico_inst = ico.new()
	var d := Vector3(0.3, 0.9, 0.31).normalized()
	var want: int = ico_inst.to_cell(rad_to_deg(asin(d.y)), rad_to_deg(atan2(d.z, d.x)))
	var body := _body(d * 20000.0)
	var got: int = _svc._vertex_for_entity(body)
	if got == want:
		_ok("off-vertex direction agrees with the icosahedral law (vertex %d)" % got)
	else:
		_fail("off-vertex disagreed: got %d, law %d" % [got, want])
	body.free()


func _test_planet_center() -> void:
	# The SAME radial direction, but the planet center is shifted: the
	# vertex must be computed against planet_center (the globe frame),
	# not the world origin.
	var ico = load(ICOSA)
	var center := Vector3(1000.0, 2000.0, -500.0)
	var dir: Vector3 = ico.VERTICES[5].normalized()
	var body := _body(center + dir * 20000.0)
	body.planet_center = center
	var got: int = _svc._vertex_for_entity(body)
	if got == 5:
		_ok("planet_center honored (shifted body buckets to vertex 5)")
	else:
		_fail("planet_center not honored: got %d, want 5" % got)
	body.free()


func _test_no_position_fallback() -> void:
	# A body with no position and a team_id clusters on the team bucket
	# -- the honest fallback, never a fabricated position vertex.
	var body := _body(Vector3.ZERO)
	body.team_id = 7
	var got: int = _svc._vertex_for_entity(body)
	if got == (7 % 12):
		_ok("position-less body falls back to the team bucket (vertex %d)" % got)
	else:
		_fail("position-less fallback wrong: %d" % got)
	body.free()


func _test_faction_bucket() -> void:
	var a := _body(Vector3.ZERO)
	var b := _body(Vector3.ZERO)
	a.faction_id = "faction_human"
	b.faction_id = "faction_human"
	var fa: int = _svc._faction_for_entity(a)
	var fb: int = _svc._faction_for_entity(b)
	if fa == fb and fa >= 0 and fa < 100:
		_ok("faction bucket is stable for an authored faction_id (%d)" % fa)
	else:
		_fail("faction bucket unstable: %d vs %d" % [fa, fb])
	a.free()
	b.free()


func _finish() -> void:
	if _svc != null:
		root.remove_child(_svc)
		_svc.free()
	if _failed == 0:
		print("MULTI-ISO SPATIAL VERTEX RECEIPT PASS (%d)" % _passed)
		quit(0)
	else:
		printerr("MULTI-ISO SPATIAL VERTEX RECEIPT FAIL (%d)" % _failed)
		quit(1)
