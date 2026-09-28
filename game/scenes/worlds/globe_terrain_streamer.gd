## GlobeTerrainStreamer - icosahedral face patch streaming (S5b)
## The planet's visuals stream as 20 spherical-triangle REGIONS (the
## icosahedron faces, via IcosahedralFaces). The active set is always
## the player's current face plus its 3 edge-neighbors (max 4 patches);
## crossing a face border swaps exactly the stale patches out.
## Visual-only: the globe's sphere StaticBody stays the physics truth;
## patch tiles dip below it by <6 cm at prototype scale (sagitta).
## RefCounted helper (preloaded by the globe scene; no autoload).
extends RefCounted

const FacePatches = preload("res://core/frame/math/icosahedral_faces.gd")

## Tiles render just above the scene's visual sphere shell (which sits
## at radius + SKIN_THICKNESS = +0.5) so they never hide inside it.
const TILE_LIFT: float = 0.52

signal face_changed(old_face: int, new_face: int)
signal patch_loaded(face: int)
signal patch_unloaded(face: int)

var radius: float = 100.0
## Target patch tile edge in meters; subdivision level derives from it.
var target_patch_edge: float = 7.0

var current_face: int = -1
var parent: Node3D

var _patches := {}  # int face -> MeshInstance3D
var _face_tints := {}  # int face -> Color (deterministic per face)


## Wire the streamer to a scene. Call before the first update().
func configure(p_radius: float, p_target_edge: float, p_parent: Node3D) -> void:
	radius = p_radius
	target_patch_edge = p_target_edge
	parent = p_parent


## Call every physics frame with the player position. Loads the
## current face + neighbors, unloads stale patches, emits signals on
## changes. Returns a stats dict for probes/tests.
func update(player_pos: Vector3) -> Dictionary:
	var f: int = FacePatches.face_for_position(player_pos, radius)
	if f == current_face:
		return {"face": f, "loaded": [], "unloaded": [], "active": _patches.keys()}
	var old: int = current_face
	current_face = f

	var want := {f: true}
	for n in FacePatches.neighbors(f):
		want[n] = true

	var loaded: Array = []
	var unloaded: Array = []
	for face in want:
		if not _patches.has(face):
			_load_patch(face)
			loaded.append(face)
	for face in _patches.keys():
		if not want.has(face):
			_unload_patch(face)
			unloaded.append(face)
	if old >= 0:
		face_changed.emit(old, f)
	return {"face": f, "loaded": loaded, "unloaded": unloaded, "active": _patches.keys()}


## Number of live patch nodes (steady state: 4).
func patch_count() -> int:
	return _patches.size()


func is_loaded(face: int) -> bool:
	return _patches.has(face)


## All live face ids.
func active_faces() -> Array:
	return _patches.keys()


## Total triangles across live patches (probe/observability).
func triangle_count() -> int:
	var total := 0
	for face in _patch_tris:
		total += _patch_tris[face]
	return total

var _patch_tris := {}


# -- internals ---------------------------------------------------------

func _load_patch(face: int) -> void:
	if parent == null:
		return
	var fv: PackedInt32Array = FacePatches.face_vertices(face)
	var tile_r: float = radius + TILE_LIFT
	var a: Vector3 = Icosahedral.VERTICES[fv[0]].normalized() * tile_r
	var b: Vector3 = Icosahedral.VERTICES[fv[1]].normalized() * tile_r
	var c: Vector3 = Icosahedral.VERTICES[fv[2]].normalized() * tile_r

	var level: int = _level_for_edge()
	var verts: Array = []  # tile corner triples (world space)
	_subdivide(a, b, c, level, verts)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tint: Color = _tint_for(face)
	for tri in verts:
		for v in tri:
			st.set_normal(v.normalized())
			st.set_color(tint)
			st.add_vertex(v)
	var mesh: ArrayMesh = st.commit()

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = "Patch%d" % face
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mi.material_override = mat
	parent.add_child(mi)
	_patches[face] = mi
	_patch_tris[face] = verts.size()
	patch_loaded.emit(face)


func _unload_patch(face: int) -> void:
	var mi: MeshInstance3D = _patches.get(face)
	if mi and is_instance_valid(mi):
		mi.queue_free()
	_patches.erase(face)
	_patch_tris.erase(face)
	patch_unloaded.emit(face)


## Subdivision level so tile edges land near target_patch_edge.
## Unit-icosahedron edge chord is ~1.0515; each level halves the edge.
func _level_for_edge() -> int:
	var edge_full: float = 1.0515 * radius
	# GDScript has no log2 builtin: log(x) is the natural log.
	var lvl: float = log(edge_full / maxf(target_patch_edge, 0.001)) / log(2.0)
	return clampi(int(round(lvl)), 1, 6)


## Recursive spherical midpoint subdivision; preserves outward winding.
func _subdivide(a: Vector3, b: Vector3, c: Vector3, depth: int, out: Array) -> void:
	if depth <= 0:
		out.append([a, b, c])
		return
	var r: float = a.length()
	var mab: Vector3 = (a + b).normalized() * r
	var mbc: Vector3 = (b + c).normalized() * r
	var mca: Vector3 = (c + a).normalized() * r
	_subdivide(a, mab, mca, depth - 1, out)
	_subdivide(mab, b, mbc, depth - 1, out)
	_subdivide(mca, mbc, c, depth - 1, out)
	_subdivide(mab, mbc, mca, depth - 1, out)


## Deterministic per-face tint (visible patch boundaries for streaming
## verification; subtle enough to read as natural ground variation).
func _tint_for(face: int) -> Color:
	if not _face_tints.has(face):
		var h: float = float((face * 2654435761) % 997) / 997.0
		var k: float = 0.85 + 0.3 * h
		_face_tints[face] = Color(0.32 * k, 0.55 * k, 0.35 * k)
	return _face_tints[face]
