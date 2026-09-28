## GlobeTerrainStreamer - icosahedral face patch streaming (S5b)
## The planet's visuals stream as 20 spherical-triangle REGIONS (the
## icosahedron faces, via IcosahedralFaces). The active set is always
## the player's current face plus its 3 edge-neighbors (max 4 patches);
## crossing a face border swaps exactly the stale patches out.
## Visual-only: the globe's sphere StaticBody stays the physics truth
## at prototype scale; at planet scale the globe scene's re-anchored
## surface pad carries the collision (see globe_island._build_surface_pad).
## S8 FLOATING ORIGIN: patches are planet-relative children of the
## scene's world_root, and all patch vertices are LOCAL to the patch
## node (world-space vertices at |r| ~20 km silently break Godot's
## physics import even for visuals-adjacent paths; rendering is fine).
## RefCounted helper (preloaded by the globe scene; no autoload).
extends RefCounted

const FacePatches = preload("res://core/frame/math/icosahedral_faces.gd")
const TerrainGen = preload("res://scenes/worlds/terrain_gen.gd")

## Tiles render just above the scene's visual sphere shell (which sits
## at radius + SKIN_THICKNESS = +0.5) so they never hide inside it.
## Mirrored by globe_island.STREAMER_TILE_LIFT (spawn / snap / pad).
const TILE_LIFT: float = 0.52

signal face_changed(old_face: int, new_face: int)
signal patch_loaded(face: int)
signal patch_unloaded(face: int)

var radius: float = 100.0
## Target patch tile edge in meters; subdivision level derives from it.
var target_patch_edge: float = 7.0

var current_face: int = -1
var parent: Node3D
## World seed bytes for deterministic content (TerrainGen).
var world_seed: PackedByteArray = PackedByteArray()

var _patches := {}  # int face -> MeshInstance3D
var _face_tints := {}  # int face -> Color (deterministic per face)
var _patch_rocks := {}  # int face -> Array of rock MeshInstance3D


## Wire the streamer to a scene. Call before the first update().
## Ground support is NOT the streamer's job: at planet scale the globe
## scene's re-anchored surface pad carries collision (single authority
## for physics; the streamer stays visual-only).
func configure(p_radius: float, p_target_edge: float, p_parent: Node3D) -> void:
	radius = p_radius
	target_patch_edge = p_target_edge
	parent = p_parent
	world_seed = TerrainGen.world_seed_bytes()


## Call every physics frame with the player position. Loads the
## current face + neighbors, unloads stale patches, emits signals on
## changes. Returns a stats dict for probes/tests.
func update(player_pos: Vector3) -> Dictionary:
	# player_pos must be PLANET-RELATIVE (the globe scene passes
	# player.global_position - planet_center). Planet-relative coords
	# are invariant under floating-origin shifts, so face addressing
	# never sees the shift at all.
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


var _patch_tris := {}


## Total triangles across live patches (probe/observability).
func triangle_count() -> int:
	var total := 0
	for face in _patch_tris:
		total += _patch_tris[face]
	return total


# -- internals ---------------------------------------------------------

func _load_patch(face: int) -> void:
	if parent == null:
		return
	var fv: PackedInt32Array = FacePatches.face_vertices(face)
	var tile_r: float = radius + TILE_LIFT
	var center: Vector3 = FacePatches.face_center(face) * tile_r
	var a: Vector3 = Icosahedral.VERTICES[fv[0]].normalized() * tile_r - center
	var b: Vector3 = Icosahedral.VERTICES[fv[1]].normalized() * tile_r - center
	var c: Vector3 = Icosahedral.VERTICES[fv[2]].normalized() * tile_r - center

	var level: int = _level_for_edge()
	var verts: Array = []  # tile corner triples, LOCAL to the patch node
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
	mi.position = center
	parent.add_child(mi)
	_patches[face] = mi
	_patch_tris[face] = verts.size()

	_spawn_rocks(face)
	patch_loaded.emit(face)


## Seeded rocks for one face: deterministic content (S7), parented
## under the patch node so unload is free. VISUAL-ONLY: the walk-over
## authority is the snap_height_provider (the exact smoothstep cap) --
## adding StaticBody colliders duplicates that authority and fights
## it (slide friction stalls the walk; test-caught lesson). If
## projectiles/raycasts ever need rock hits, add colliders on a
## separate physics layer, not the player's.
func _spawn_rocks(face: int) -> void:
	var specs: Array = TerrainGen.rock_specs(world_seed, face)
	var nodes: Array = []
	var patch_node: MeshInstance3D = _patches[face]
	for s in specs:
		var rmi := MeshInstance3D.new()
		var rmesh := SphereMesh.new()
		rmesh.radius = TerrainGen.ROCK_RADIUS * s.scale
		rmesh.height = rmesh.radius * 2.0
		var rmat := StandardMaterial3D.new()
		rmat.albedo_color = Color(0.45, 0.42, 0.40)
		rmat.roughness = 1.0
		rmesh.material = rmat
		rmi.mesh = rmesh
		rmi.position = s.dir * (radius + TerrainGen.ROCK_EMBED)
		rmi.rotation.y = s.yaw
		patch_node.add_child(rmi)
		nodes.append(rmi)
	_patch_rocks[face] = nodes


func _unload_patch(face: int) -> void:
	var mi: MeshInstance3D = _patches.get(face)
	if mi and is_instance_valid(mi):
		mi.queue_free()
	_patches.erase(face)
	_patch_tris.erase(face)
	_patch_rocks.erase(face)
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
