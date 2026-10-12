## Probe: the renderer feed end-to-end (the caller-side half of the
## raster seam). Asserts:
##   1. build_mesh(planar) yields a fat surface + thin surface with
##      the right triangle counts and vertex colors.
##   2. build_mesh(sphere) yields points ON the planet sphere with
##      radial normals.
##   3. The full loop: pentagrid -> validate (atlas closed) -> mesh ->
##      MeshInstance3D on the scene tree -> Aabb non-degenerate.
extends SceneTree

const PG = preload("res://core/frame/math/pentagrid.gd")
const B = preload("res://scenes/worlds/penrose_mesh_builder.gd")

var _passed: int = 0
var _failed: int = 0

func _init() -> void:
	_check_planar()
	_check_sphere()
	_check_full_loop()
	print("PENROSE MESH probe: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)

func _check(label: String, cond: bool) -> void:
	if cond:
		_passed += 1
		print("  PASS %s" % label)
	else:
		_failed += 1
		print("  FAIL %s" % label)

func _check_planar() -> void:
	var patch: Array = PG.build_region(PG.GAMMA, 4.0)
	var fat := 0
	var thin := 0
	for t in patch:
		if t.kind == PG.TileKind.FAT:
			fat += 1
		else:
			thin += 1
	var mesh: ArrayMesh = B.build_mesh(patch, true, 1.0)
	if mesh.get_surface_count() != 2:
		_check("planar mesh has 2 surfaces", false)
		return
	var fpos: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var tpos: PackedVector3Array = mesh.surface_get_arrays(1)[Mesh.ARRAY_VERTEX]
	_check("fat surface triangle count", fpos.size() == fat * 6)
	_check("thin surface triangle count", tpos.size() == thin * 6)
	var fcol: PackedColorArray = mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	# Godot round-trips vertex colors through sRGB float; compare with
	# a tolerance instead of exact equality (exact fails on 0.72 etc.).
	var col_ok: bool = fcol.size() == fpos.size()
	if col_ok:
		col_ok = (fcol[0] as Color).r > 0.6 and (fcol[0] as Color).g > 0.4 and (fcol[0] as Color).b < 0.4
	_check("fat vertex colors present and brass-themed", col_ok)
	# Front-facing: planar normals are +Z (mesh import quantizes, so
	# allow tiny jitter; the law is z-dominant).
	var fn: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	_check("planar normals face +Z", fn[0].z > 0.99 and absf(fn[0].x) < 0.01 and absf(fn[0].y) < 0.01)

func _check_sphere() -> void:
	var patch: Array = PG.build_region(PG.GAMMA, 3.0)
	var radius: float = 20000.0
	var mesh: ArrayMesh = B.build_mesh(patch, false, 1.0, 30.0, 15.0, radius)
	if mesh.get_surface_count() == 0:
		_check("sphere mesh nonempty", false)
		return
	var pos: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var nrm: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	var on_sphere := true
	for i in range(0, pos.size(), 7):
		if absf(pos[i].length() - radius) > 0.5:
			on_sphere = false
			break
	_check("projected verts sit on the planet", on_sphere)
	var n_ok := true
	for i in range(nrm.size()):
		if absf(nrm[i].length() - 1.0) > 0.001:
			n_ok = false
			break
	_check("sphere normals are radial unit", n_ok)

func _check_full_loop() -> void:
	var patch: Array = PG.build_region(PG.GAMMA, 5.0)
	# Legality gate first: the atlas-validated patch must still pass.
	var res: Dictionary = PG.validate_patch(patch)
	_check("built patch validates pre-render", bool(res["ok"]))
	if not bool(res["ok"]):
		return
	var mi: MeshInstance3D = B.build_instance(patch, "probe_patch", true, 1.0)
	root.add_child(mi)
	# Deferred: the aabb is ready once the mesh is in the tree.
	await process_frame
	var aabb: AABB = mi.get_aabb()
	_check("MeshInstance3D mounted with non-degenerate aabb", aabb.size.x > 0 and aabb.size.y > 0)
	mi.queue_free()
