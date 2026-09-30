## GlobeTerrainStreamer - icosahedral face patch streaming (S5b)
## The planet's visuals stream as 20 spherical-triangle REGIONS (the
## icosahedron faces, via IcosahedralFaces). The active set is always
## the player's current face plus its 3 edge-neighbors (max 4 patches);
## crossing a face border swaps exactly the stale patches out.
## Visual-only: the globe's sphere StaticBody stays the physics truth
## at prototype scale; at planet scale the globe scene's re-anchored
## surface pad carries the collision (see globe_world._build_surface_pad).
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
## Mirrored by globe_world.STREAMER_TILE_LIFT (spawn / snap / pad).
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
			# Planar UVs on the tangent plane (patch-local x/z). Gives the
			# tile a real texture map so ground motion reads while walking
			# (play-day feedback #7: the pure-vertex-tint globe had zero
			# ground detail -- nothing to see move under you).
			st.set_uv(Vector2(v.x, v.z) * 0.22)
			st.add_vertex(v)
	var mesh: ArrayMesh = st.commit()

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = "Patch%d" % face
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	# Subtle grass checker (seeded per-run like the planar floor): keeps
	# the face tint readable while giving walking a parallax cue.
	mat.albedo_texture = _make_checker_texture()
	mat.uv1_scale = Vector3(1, 1, 1)
	mi.material_override = mat
	mi.position = center
	parent.add_child(mi)
	_patches[face] = mi
	_patch_tris[face] = verts.size()

	_spawn_rocks(face)
	patch_loaded.emit(face)


## 2x2-pixel green checker. StandardMaterial3D wraps UVs by default,
## so the small texture tiles across the 0.22-scaled UVs.
func _make_checker_texture() -> ImageTexture:
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color(0.42, 0.55, 0.30))
	img.set_pixel(1, 0, Color(0.38, 0.51, 0.27))
	img.set_pixel(0, 1, Color(0.38, 0.51, 0.27))
	img.set_pixel(1, 1, Color(0.42, 0.55, 0.30))
	return ImageTexture.create_from_image(img)


## Seeded rocks + trees for one face: deterministic content (S7),
## parented under the patch node so unload is free. VISUAL-ONLY: the
## walk-over authority is the snap_height_provider (the exact
## smoothstep cap) -- adding StaticBody colliders duplicates that
## authority and fights it (slide friction stalls the walk;
## test-caught lesson). If projectiles/raycasts ever need rock hits,
## add colliders on a separate physics layer, not the player's.
## Play-day feedback #7: TREES joined the rocks -- motion cues. Both
## ride the same seeded RNG stream, so the scatter re-derives
## identically (no drift between visits) and streams with the patch.
func _spawn_rocks(face: int) -> void:
	var specs: Array = TerrainGen.rock_specs(world_seed, face)
	var nodes: Array = []
	var patch_node: MeshInstance3D = _patches[face]
	# The patch node's offset (same derivation as _load_patch).
	var patch_center: Vector3 = FacePatches.face_center(face) * (radius + TILE_LIFT)
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
		# rock_specs dirs are GLOBE-absolute; the patch node sits at the
		# face-center offset, so the child position must be patch-LOCAL:
		# absolute point minus the node's offset. (Pre-existing S7 bug:
		# absolute coords used as local ones displaced every rock roughly
		# a face-width off its true spot -- visually "no rocks near the
		# ground you walk".)
		rmi.position = s.dir * (radius + TerrainGen.ROCK_EMBED) - patch_center
		rmi.rotation.y = s.yaw
		patch_node.add_child(rmi)
		nodes.append(rmi)
	_spawn_trees(face, patch_node)
	_patch_rocks[face] = nodes


## Trees: 4-8 seeded scatters per face -- trunk cylinder + canopy
## sphere on the tangent surface. The canopy greens shift subtly per
## tree (same hash family as the face tints). Height rides the walk
## surface (radius + TILE_LIFT); they are visual-only like the rocks.
func _spawn_trees(face: int, patch_node: MeshInstance3D) -> void:
	var bytes: PackedByteArray = TerrainGen.face_seed_bytes(world_seed, face)
	var acc: int = 0
	for b in bytes:
		acc = (acc * 131 + b) % 9007199254740991
	var rng := RandomNumberGenerator.new()
	rng.seed = acc
	var count: int = rng.randi_range(4, 8)
	var verts: PackedInt32Array = FacePatches.face_vertices(face)
	# Scaled patch offset (matches _load_patch), for patch-local trees.
	var patch_center: Vector3 = FacePatches.face_center(face) * (radius + TILE_LIFT)
	for i in range(count):
		var v: Vector3 = Icosahedral.VERTICES[verts[rng.randi_range(0, 2)]].normalized()
		var dir: Vector3 = (FacePatches.face_center(face) * 0.55 + v * 0.45).normalized()
		var tree := Node3D.new()
		tree.name = "Tree%d" % i
		var trunk_height: float = rng.randf_range(1.8, 3.2)
		var trunk := MeshInstance3D.new()
		var tmesh := CylinderMesh.new()
		tmesh.top_radius = 0.14
		tmesh.bottom_radius = 0.22
		tmesh.height = trunk_height
		var tmat := StandardMaterial3D.new()
		tmat.albedo_color = Color(0.36, 0.26, 0.17)
		tmat.roughness = 1.0
		tmesh.material = tmat
		trunk.mesh = tmesh
		trunk.position = Vector3(0, trunk_height * 0.5, 0)
		tree.add_child(trunk)
		var canopy := MeshInstance3D.new()
		var cmesh := SphereMesh.new()
		var crown: float = rng.randf_range(1.1, 2.0)
		cmesh.radius = crown
		cmesh.height = crown * 1.8
		var g: float = 0.3 + 0.14 * rng.randf()
		var cmat := StandardMaterial3D.new()
		cmat.albedo_color = Color(0.18 + 0.06 * rng.randf(), g, 0.16)
		cmat.roughness = 1.0
		cmesh.material = cmat
		canopy.mesh = cmesh
		canopy.position = Vector3(0, trunk_height + crown * 0.55, 0)
		tree.add_child(canopy)
		# Patch-local like the mesh vertices and the rocks: absolute
		# scatter position minus the patch node's offset.
		tree.position = dir * (radius + TILE_LIFT) - patch_center
		# Stand the trunk along the local radial up.
		var up: Vector3 = dir
		var hint := Vector3(0, 1, 0)
		if abs(up.dot(hint)) > 0.999:
			hint = Vector3(0, 0, -1)
		var east: Vector3 = (hint - up * hint.dot(up)).normalized()
		var north: Vector3 = east.cross(up)
		tree.basis = Basis(east, up, north).rotated(up, rng.randf_range(0.0, TAU))
		patch_node.add_child(tree)


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
