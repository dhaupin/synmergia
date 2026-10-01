## GlobeTerrainStreamer - icosahedral face patch streaming (S5b)
## The planet's visuals stream as 20 spherical-triangle REGIONS (the
## icosahedron faces, via IcosahedralFaces). The active set is always
## the player's current face plus its 3 edge-neighbors (max 4 patches);
## crossing a face border swaps exactly the stale patches out.
## Visual-only: the globe's sphere StaticBody stays the physics truth
## at prototype scale; at planet scale the globe scene's re-anchored
## surface pad carries the collision (see globe_world._build_surface_pad).
##
## TERRAIN ARC (v2): patches are no longer flat. Each tile vertex is
## displaced radially by TerrainGen.terrain_height -- the seeded
## heightfield (one big continent, hills, inland mountains, a lake,
## the offshore island plateau, an ocean floor). Props pose onto the
## displaced surface, boulders join as big climbable colliders, and
## the scene reads walk_surface_h() for the pad lift and the snap
## provider, so visuals and physics share ONE ground law.
## S8 FLOATING ORIGIN: patches are planet-relative children of the
## scene's world_root, and all patch vertices are LOCAL to the patch
## node (world-space vertices at |r| ~20 km silently break Godot's
## physics import even for visuals-adjacent paths; rendering is fine).
## RefCounted helper (preloaded by the globe scene; no autoload).
extends RefCounted

const FacePatches = preload("res://core/frame/math/icosahedral_faces.gd")
const TerrainGen = preload("res://scenes/worlds/terrain_gen.gd")
## One-law prop collision + climbable registration (play-day:
## "stuff shouldn't be walk-through"). RefCounted helper, no autoload.
const PropCollider = preload("res://entities/prop_collider.gd")

## Tiles render just above the scene's visual sphere shell (which sits
## at radius + SKIN_THICKNESS = +0.5) so they never hide inside it.
## Mirrored by globe_world.STREAMER_TILE_LIFT (spawn / snap / pad).
const TILE_LIFT: float = 0.52

## WATER (terrain arc): at planet scale the scene paints a water shell
## at the terrain sea line. Patches below the waterline dim to a wet
## seabed tint (foreshortening cheat: the shell renders the water
## body; the dimmed ground reads as depth through it).
const WATER_ON: bool = true
## Height-band tints (read like a map): deep seabed -> sand -> grass
## -> forest green -> rock -> snow.
const TINT_DEEP: Color = Color(0.24, 0.30, 0.34)
const TINT_SAND: Color = Color(0.62, 0.55, 0.40)
const TINT_GRASS: Color = Color(0.34, 0.52, 0.30)
const TINT_FOREST: Color = Color(0.22, 0.42, 0.24)
const TINT_ROCK: Color = Color(0.44, 0.42, 0.40)
const TINT_SNOW: Color = Color(0.88, 0.90, 0.93)

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
var _patch_boulders := {}  # int face -> Array of boulder MeshInstance3D
var _patch_mats := {}  # int face -> StandardMaterial3D (per-face cache)
## Terrain arc: the heightfield displaces tile vertices when on
## (planet scale -- the scene flips it; prototype stays the flat
## shell so every S5b/S8 probe contract keeps its geometry).
var terrain_on: bool = false
var _patch_walk_h := {}  # int face -> Callable(dir) -> walk height


## Wire the streamer to a scene. Call before the first update().
## Ground support is NOT the streamer's job: at planet scale the globe
## scene's re-anchored surface pad carries collision (single authority
## for physics; the streamer stays visual-only).
func configure(p_radius: float, p_target_edge: float, p_parent: Node3D) -> void:
	radius = p_radius
	target_patch_edge = p_target_edge
	parent = p_parent
	world_seed = TerrainGen.world_seed_bytes()
	terrain_on = false


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


## -- Terrain arc ground law --------------------------------------------

## The WALK SURFACE (meters above the base shell) at world direction
## `dir`: the displaced terrain (terrain arc, planet scale) with the
## small-rock walk-over caps on top. Boulder tops are NOT included:
## boulders block (their collider carries that) and are climbed, not
## ridden. The scene feeds this to the pad lift and the snap provider
## -- one ground law for visuals and physics.
func walk_surface_h(dir: Vector3) -> float:
	var d: Vector3 = dir.normalized()
	var face: int = FacePatches.face_for_direction(d)
	if not is_loaded(face):
		# Not streamed (should not happen: the walker streams its own
		# face): the analytic terrain alone is still the truth.
		var base: float = TerrainGen.terrain_height(d, world_seed) if terrain_on else 0.0
		return base
	return _patch_walk_h[face].call(d)


## Terrain height at a direction, live value of the streamer's flag.
func terrain_h(dir: Vector3) -> float:
	return TerrainGen.terrain_height(dir.normalized(), world_seed) if terrain_on else 0.0


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

	# -- Terrain arc: radial displacement per vertex --------------------
	# The corner directions are GLOBE directions: the tile corners are
	# patch-LOCAL (face-center subtracted), so the direction must be
	# reconstructed as (v + center).normalized() -- normalizing the local
	# vector alone points somewhere near the face EDGE with a ~5 km
	# magnitude, and displacing along it scattered every vertex into
	# invisible debris (play-day round 5: the world looked like open
	# ocean -- the water shell was the only intact sphere). The cache is
	# keyed on the quantized GLOBE direction, so shared tile corners
	# still read identical heights (no border cracks). Vertices are
	# emitted back in patch-LOCAL space: globe point minus the center.
	var dir_h := {}  # Vector3 (quantized globe dir) -> displaced radius
	var sea: float = TerrainGen.sea_level(world_seed)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for tri in verts:
		for i in range(3):
			var v: Vector3 = tri[i]
			var d_abs: Vector3 = (v + center).normalized()
			var r_abs: float = tile_r
			if terrain_on:
				var key: Vector3 = (d_abs * 4096.0).floor()
				if not dir_h.has(key):
					dir_h[key] = tile_r + TerrainGen.terrain_height(d_abs, world_seed)
				r_abs = dir_h[key]
			st.set_normal(d_abs)
			# Prototype keeps the S7 per-face tint; terrain-on paints the
			# height-band map (seabed through snow).
			var col: Color = _tint_for(face) if not terrain_on else _band_color(r_abs - tile_r, sea)
			st.set_color(col)
			# Planar UVs on the tangent plane (patch-local x/z). Gives the
			# tile a real texture map so ground motion reads while walking
			# (play-day feedback #7: the pure-vertex-tint globe had zero
			# ground detail -- nothing to see move under you).
			st.set_uv(Vector2(v.x, v.z) * 0.22)
			st.add_vertex(d_abs * r_abs - center)
	var mesh: ArrayMesh = st.commit()

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = "Patch%d" % face
	var mat: StandardMaterial3D = _patch_mats.get(face)
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 0.95
		# Subtle grass checker (seeded per-run like the planar floor): keeps
		# the face tint readable while giving walking a parallax cue.
		mat.albedo_texture = _make_checker_texture()
		mat.uv1_scale = Vector3(1, 1, 1)
		_patch_mats[face] = mat
	mi.material_override = mat
	mi.position = center
	parent.add_child(mi)
	_patches[face] = mi
	_patch_tris[face] = verts.size()
	# Terrain arc: the per-face walk law for walk_surface_h(). The
	# closure captures the same displacement law the mesh used, so
	# physics and visuals can never disagree about the ground.
	var captured_seed: PackedByteArray = world_seed
	var captured_on: bool = terrain_on
	var captured_radius: float = radius
	_patch_walk_h[face] = func(d: Vector3) -> float:
		var base: float = TerrainGen.terrain_height(d, captured_seed) if captured_on else 0.0
		return base + TerrainGen.rock_top_height(d, captured_seed, face, captured_radius)

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


## Height-band ground color (the map you walk on): seabed through
## snowline. Blend bands overlap so no hard rings. Wet tint below the
## waterline (the shell paints the water; dimmed ground reads as
## depth through it).
func _band_color(lift: float, sea: float) -> Color:
	var c: Color
	if lift < sea - 4.0:
		c = TINT_DEEP
	elif lift < sea - 0.8:
		c = TINT_DEEP.lerp(TINT_SAND, (lift - (sea - 4.0)) / 3.2)
	elif lift < sea + 1.2:
		c = TINT_SAND
	elif lift < sea + 9.0:
		c = TINT_SAND.lerp(TINT_GRASS, (lift - (sea + 1.2)) / 7.8)
	elif lift < sea + 20.0:
		c = TINT_GRASS.lerp(TINT_FOREST, (lift - (sea + 9.0)) / 11.0)
	elif lift < sea + 30.0:
		c = TINT_FOREST.lerp(TINT_ROCK, (lift - (sea + 20.0)) / 10.0)
	else:
		c = TINT_ROCK.lerp(TINT_SNOW, clampf((lift - (sea + 30.0)) / 8.0, 0.0, 1.0))
	if lift < sea - 0.2:
		c = c.darkened(0.45)
	return c


## Seeded rocks + trees + boulders for one face: deterministic
## content (S7), parented under the patch node so unload is free.
## TERRAIN ARC (v2):
##  - every prop poses ONTO the displaced surface (its base rides the
##    terrain law + the small-rock walk-over cap),
##  - props below the waterline are SKIPPED (no kelp forests yet --
##    the shelf is honest water),
##  - BOULDERS join: big climbable colliders (PropCollider.attach)
##    -- they block, the climb law grabs them, and their collar ring
##    of small rocks decorates the base.
## WALK-OVER LAW (unchanged): small rocks stay collider-less; the
## snap provider carries their tops. TUNNEL LAW: nothing is buried;
## tree trunks get colliders via PropCollider.attach_trunk.
func _spawn_rocks(face: int) -> void:
	var specs: Array = TerrainGen.rock_specs(world_seed, face)
	var nodes: Array = []
	var patch_node: MeshInstance3D = _patches[face]
	# The patch node's offset (same derivation as _load_patch).
	var patch_center: Vector3 = FacePatches.face_center(face) * (radius + TILE_LIFT)
	var sea: float = TerrainGen.sea_level(world_seed)
	var scaled: float = radius + TILE_LIFT
	for s in specs:
		var base_h: float = _prop_ground_h(face, s.dir)
		# WATER SKIP (terrain arc only): no props in the ocean yet. The
		# prototype (terrain off) keeps its S7 greenery untouched.
		if terrain_on and base_h < sea - 0.6:
			continue
		var rmi := MeshInstance3D.new()
		var rmesh := SphereMesh.new()
		rmesh.radius = TerrainGen.ROCK_RADIUS * s.scale
		rmesh.height = rmesh.radius * 2.0
		var rmat := StandardMaterial3D.new()
		rmat.albedo_color = Color(0.45, 0.42, 0.40)
		rmat.roughness = 1.0
		rmesh.material = rmat
		rmi.mesh = rmesh
		# Radial placement: the rock rides its own direction at (scaled
		# + terrain), ROCKS EXCLUDING their own walk-over cap (walk_height
		# would double-count it). At prototype scale (terrain 0) this
		# reduces to the S7 formula exactly (probe-pinned).
		var rock_r: float = scaled + TerrainGen.terrain_height(s.dir, world_seed) if terrain_on else scaled
		rmi.position = _tangent_patch_local(s.dir, patch_center, rock_r + TerrainGen.ROCK_EMBED)
		rmi.rotation.y = s.yaw
		patch_node.add_child(rmi)
		nodes.append(rmi)
	if terrain_on:
		_spawn_boulders(face, patch_node)
	_spawn_trees(face, patch_node)
	_patch_rocks[face] = nodes
	# One-law collision (play-day: "stuff shouldn't be walk-through"):
	# tree TRUNKS block movement and join the climbable group so the
	# climb law can grab them. Canopies stay intangible (walking under
	# a crown must not feel like a ceiling). Bodies are tree children,
	# so streamed-out faces drop theirs for free.
	for tree in patch_node.get_children():
		if tree is Node3D and str(tree.name).begins_with("Tree"):
			PropCollider.attach_trunk(tree)


## Big climbable boulders (terrain arc): PropCollider-carried, so they
## BLOCK movement and join the climbable group. A decorative collar of
## small rocks (1-2, seeded) decorates the base -- and their walk-over
## caps are already part of the ground law, so the ring never tunnels
## the boulder (a cap rises to >= collar top at the boulder rim).
func _spawn_boulders(face: int, patch_node: MeshInstance3D) -> void:
	var specs: Array = TerrainGen.boulder_specs(world_seed, face)
	var nodes: Array = []
	var patch_center: Vector3 = FacePatches.face_center(face) * (radius + TILE_LIFT)
	var scaled: float = radius + TILE_LIFT
	var sea: float = TerrainGen.sea_level(world_seed)
	for s in specs:
		var base_h: float = _prop_ground_h(face, s.dir)
		if base_h < sea - 0.6:
			continue  # boulders are land content (for now)
		var bmi := MeshInstance3D.new()
		var bmesh := SphereMesh.new()
		bmesh.radius = s.radius
		bmesh.height = s.radius * 1.7  # squat, not a perfect ball
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = Color(0.40, 0.38, 0.37)
		bmat.roughness = 1.0
		bmesh.material = bmat
		bmi.mesh = bmesh
		bmi.name = "Boulder%d" % nodes.size()
		# Sink the squat ellipsoid by ~1/3 radius: a believable embed
		# whose visible top is 1.13*radius above the ground (center sits
		# 0.28*radius above the surface; the lower 0.57*radius is buried).
		# Placement is RADIAL (height baked into the arc distance along
		# the boulder's own direction), and the basis stands the squash
		# axis along the local radial up (world +y is TANGENT at the
		# spawn face -- an identity basis would squash sideways).
		var bdir_r: float = scaled + TerrainGen.terrain_height(s.dir, world_seed) if terrain_on else scaled
		bmi.position = _tangent_patch_local(s.dir, patch_center, bdir_r + s.radius * 0.28)
		var bup: Vector3 = s.dir
		var bhint := Vector3(0, 1, 0)
		if abs(bup.dot(bhint)) > 0.999:
			bhint = Vector3(0, 0, -1)
		var beast: Vector3 = (bhint - bup * bhint.dot(bup)).normalized()
		var bnorth: Vector3 = beast.cross(bup)
		bmi.basis = Basis(beast, bup, bnorth)
		patch_node.add_child(bmi)
		nodes.append(bmi)
		PropCollider.attach(bmi)
		# Decorative collar: 1-2 small rocks at the rim (seeded from the
		# face stream + boulder index -- same fold discipline as rocks).
		var acc: int = 0
		for b in TerrainGen.face_seed_bytes(world_seed, face):
			acc = (acc * 256 + b) % 9007199254740991
		acc = (acc * 131 + nodes.size()) % 9007199254740991
		var rng := RandomNumberGenerator.new()
		rng.seed = acc
		var collar_n: int = rng.randi_range(1, 2)
		for k in range(collar_n):
			var rim_hint: Vector3 = Vector3(0, 1, 0) if abs(s.dir.dot(Vector3(0, 1, 0))) < 0.9 else Vector3(1, 0, 0)
			var rim_axis: Vector3 = s.dir.cross(rim_hint).normalized()
			var rim_dir: Vector3 = s.dir.rotated(rim_axis, \
				(s.radius * 0.95) / maxf(bdir_r, 1.0) + rng.randf_range(0.0, 0.02))
			var crmi := MeshInstance3D.new()
			var crm := SphereMesh.new()
			crm.radius = TerrainGen.ROCK_RADIUS
			crm.height = crm.radius * 2.0
			crm.material = bmat
			crmi.mesh = crm
			crmi.position = _tangent_patch_local(rim_dir, patch_center, bdir_r + TerrainGen.ROCK_EMBED)
			patch_node.add_child(crmi)
	_patch_boulders[face] = nodes


## Trees: 4-8 seeded scatters per face -- trunk cylinder + canopy
## sphere on the displaced surface. TERRAIN ARC: the scatter direction
## (patch-tangent arc placement, like the rocks) rides terrain_height;
## trees below the waterline are skipped and mountain tops (above the
## tree line) grow no trees. The canopy greens shift subtly per
## tree (same hash family as the face tints).
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
	var scaled: float = radius + TILE_LIFT
	var sea: float = TerrainGen.sea_level(world_seed)
	for i in range(count):
		var v: Vector3 = Icosahedral.VERTICES[verts[rng.randi_range(0, 2)]].normalized()
		var dir: Vector3 = (FacePatches.face_center(face) * 0.55 + v * 0.45).normalized()
		var base_h: float = _prop_ground_h(face, dir)
		# WATER SKIP + tree line (terrain arc only; the prototype keeps
		# its S7 greenery untouched).
		if terrain_on and (base_h < sea - 0.6 or base_h > sea + 24.0):
			continue
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
		# Radial placement riding the displaced ground: the walk-surface
		# height (terrain + any rock cap beneath) is baked into the
		# RADIAL distance so the tree rides its own direction exactly
		# (patch-local +y is world up, not surface up).
		tree.position = _tangent_patch_local(dir, patch_center, scaled + base_h)
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
	_patch_boulders.erase(face)
	_patch_mats.erase(face)
	_patch_walk_h.erase(face)
	patch_unloaded.emit(face)


## Radial prop placement: the patch-LOCAL position of the point at
## radius `r` along direction `dir` (the patch node sits at the
## face-center offset, so local = absolute point minus that offset).
## This is the S7 chord formula and it is EXACT for a radial point:
## the rotated-arc construction it replaced reduces to this identity.
func _tangent_patch_local(dir: Vector3, patch_center: Vector3, r: float) -> Vector3:
	return dir.normalized() * r - patch_center


## Prop ground law: the walk-surface height (terrain + small-rock
## cap) at the prop's direction via the face's captured closure.
func _prop_ground_h(face: int, dir: Vector3) -> float:
	var closure = _patch_walk_h.get(face)
	if closure != null:
		return float(closure.call(dir))
	return TerrainGen.terrain_height(dir, world_seed) if terrain_on else 0.0


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
