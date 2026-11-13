## PropLayer -- the renderer-agnostic, chunk-addressed prop system
## (labs/prd-clipmap.md section 9).
##
## The clipmap draws the ground MESH and nothing else; every prop law lived
## only in the legacy streamer, addressed by icosa FACE. This layer is a
## THIRD system, independent of any renderer, addressed by a stable prop
## CHUNK (`PropChunk`): a chunk is a PURE FUNCTION of `(world_seed, key)`, so
## its content re-derives byte-identically everywhere, caches in an LRU, and
## streams around every viewer. The clipmap, the streamer, the underworld, and
## the moon all consume this one layer.
##
## The layer owns three things and nothing else:
##   1. DERIVE  -- `_derive_chunk(key)` -> an ordered list of prop instances,
##      pure, off the main thread (worker threads, the clipmap's S6 pattern).
##   2. CACHE   -- an LRU keyed by chunk key so overlapping viewers share one
##      derive.
##   3. APPLY   -- build the chunk's scene nodes (near: real Node3D + colliders
##      + harvest; far: batched MultiMesh), budgeted per frame so no frame
##      stalls.
##
## It reads the ground through a `GroundProvider`, never `TerrainGen`
## directly, so any globe can back it. It never touches the mesh renderer.
extends RefCounted

const PropChunk = preload("res://core/frame/geometry/prop_chunk.gd")
const SeedChain = preload("res://core/frame/kv/seed_chain.gd")
const TerrainGen = preload("res://scenes/worlds/terrain_gen.gd")
const PropCollider = preload("res://entities/prop_collider.gd")

## Prop families (the dispatch key). BiomeBand.Family maps onto these.
const FAMILY_TREE: int = 0
const FAMILY_ROCK: int = 1
const FAMILY_BOULDER: int = 2
const FAMILY_DETAIL: int = 3

## Per-frame build budget (ms) -- the clipmap's own L3 law.
const BUILD_BUDGET_MS: int = 3

## Near/far split: chunks within this many meters of the viewer build real
## nodes (colliders, harvest); beyond, batched MultiMesh; beyond
## `_load_radius`, not built at all. A 1.6 km load radius keeps the near
## view full (grassland ~9 trees/km2 -> ~40 trees) without a huge chunk set.
const NEAR_RADIUS_M: float = 220.0

var provider                # GroundProvider
var world_seed: PackedByteArray
var radius_m: float = 20000.0
var chunk_depth: int = PropChunk.DEFAULT_DEPTH
var _root: Node3D           # the layer's scene parent (set by the renderer)
var _salt: int = 0          # the decorative session salt (FIELD-2 split)

var _cache: Dictionary = {}       # key -> derived chunk data
var _cache_order: Array = []      # LRU order (oldest first)
var _cache_cap: int = 4096
var _built: Dictionary = {}       # key -> Node3D (the built chunk node)
var _built_order: Array = []      # streaming order
var _build_queue: Array = []      # keys awaiting build (nearest first)
var _load_radius: float = 1600.0
var _unload_radius: float = 1900.0
var _last_center: Vector3 = Vector3.ZERO
var _scan_center: Vector3 = Vector3.ZERO
var _recenter_m: float = 120.0
var _decor_salt: int = 0

# The shared prop mesh registry (quantized-key dedup, the streamer's law).
var _mesh_registry: Dictionary = {}

# Rocks + boulders are PER-FACE fixed content (TerrainGen.rock_specs /
# boulder_specs), bucketed into chunks lazily: the first time a chunk near a
# face is derived, that face's specs are computed once and each spec is
# assigned to the chunk containing its direction. Same specs the streamer
# used, so parity holds; the chunk grid stays the addressing truth.
var _rocks_by_chunk: Dictionary = {}
var _boulders_by_chunk: Dictionary = {}
var _rocks_faces_done: Dictionary = {}


func configure(p_provider, p_radius: float, p_parent: Node3D, p_depth: int = PropChunk.DEFAULT_DEPTH) -> void:
	provider = p_provider
	radius_m = p_radius
	chunk_depth = p_depth
	_root = Node3D.new()
	_root.name = "PropLayerRoot"
	p_parent.add_child(_root)
	world_seed = provider.seed_bytes() if provider.has_method("seed_bytes") else TerrainGen.world_seed_bytes()
	# The decorative salt: a day-granular session salt so canopies/grass
	# recombine between sessions while anchored culture stays seed-stable.
	_decor_salt = int(Time.get_unix_time_from_system()) / 86400


## The streaming tick: recenter on the viewer, queue near chunks, build
## within budget, unload far chunks. `viewer_pos` is planet-relative.
## HYSTERESIS: the chunk set only re-scans when the viewer drifts past
## `_recenter_m` from the last scan center (the clipmap's own law) -- a
## stationary or slowly-moving viewer pays nothing after the first scan.
func update(viewer_pos: Vector3) -> void:
	if _root == null:
		return
	var dir: Vector3 = viewer_pos.normalized() if viewer_pos.length() > 0.001 else Vector3(1, 0, 0)
	_last_center = dir
	if _scan_center != Vector3.ZERO and _scan_center.angle_to(dir) * radius_m < _recenter_m:
		_advance_build(dir)
		return
	_scan_center = dir
	var ang_load: float = _load_radius / maxf(radius_m, 1.0)
	var ang_unload: float = _unload_radius / maxf(radius_m, 1.0)
	# Queue chunks in radius (nearest first).
	var want: Array = PropChunk.chunks_in_radius(dir, ang_load, chunk_depth)
	want.sort_custom(func(a, b):
		return PropChunk.chunk_center_dir(a, chunk_depth).dot(dir) > PropChunk.chunk_center_dir(b, chunk_depth).dot(dir))
	for k in want:
		if not _built.has(k) and not _build_queue.has(k):
			_build_queue.append(k)
	# Unload chunks past the unload radius.
	var drop: Array = []
	for k in _built.keys():
		if PropChunk.chunk_center_dir(k, chunk_depth).angle_to(dir) > ang_unload:
			drop.append(k)
	for k in drop:
		_unload_chunk(k)
	_advance_build(dir)


## Build queued chunks within the frame budget, near first.
func _advance_build(viewer_dir: Vector3) -> void:
	var t0: int = Time.get_ticks_msec()
	var guard: int = 0
	while not _build_queue.is_empty() and Time.get_ticks_msec() - t0 < BUILD_BUDGET_MS and guard < 64:
		guard += 1
		var k: int = _build_queue.pop_front()
		if _built.has(k):
			continue
		_build_chunk(k, viewer_dir)


## Build one chunk's scene node (near nodes or far batch) and cache it.
func _build_chunk(key: int, viewer_dir: Vector3) -> void:
	var data: Dictionary = _derive_chunk(key)
	var node: Node3D = Node3D.new()
	node.name = "PropChunk_%d" % key
	_root.add_child(node)
	var center: Vector3 = PropChunk.chunk_center_dir(key, chunk_depth)
	var near: bool = center.angle_to(viewer_dir) * radius_m <= NEAR_RADIUS_M
	for inst in data.get("instances", []):
		_build_instance(inst, node, near)
	_built[key] = node
	_built_order.append(key)


func _unload_chunk(key: int) -> void:
	var node = _built.get(key)
	if node != null and is_instance_valid(node):
		node.queue_free()
	_built.erase(key)
	_built_order.erase(key)


## DERIVE one chunk: pure, deterministic, off-thread-safe. Returns
## { "instances": [ {family, dir, ...}, ... ] }.
func _derive_chunk(key: int) -> Dictionary:
	var cached = _cache.get(key)
	if cached != null:
		return cached
	var out: Dictionary = {"key": key, "instances": []}
	var center: Vector3 = PropChunk.chunk_center_dir(key, chunk_depth)
	var area_km2: float = PropChunk.chunk_area_km2(radius_m, chunk_depth)
	var bid: int = provider.biome_id(center)
	var sea: float = provider.sea_level()
	# Rocks + boulders (per-face specs, bucketed into this chunk).
	_bucket_face_content(PropChunk.face_of(key))
	for r in _rocks_by_chunk.get(key, []):
		out["instances"].append(r)
	for b in _boulders_by_chunk.get(key, []):
		out["instances"].append(b)
	# Trees. Count = density * area with UNBIASED stochastic rounding, so a
	# small chunk still gets a tree some of the time and the average matches
	# the density (a plain round() would zero every chunk below 0.5 expected).
	var tree_density: float = provider.tree_density(bid)
	var tree_n: int = _stochastic_count(tree_density * area_km2, _chunk_rng(key, "tcount"))
	if tree_n > 0:
		_derive_trees(key, tree_n, out)
	# Cache (LRU).
	_cache[key] = out
	_cache_order.append(key)
	while _cache_order.size() > _cache_cap:
		var old = _cache_order.pop_front()
		_cache.erase(old)
	return out


func _derive_trees(key: int, count: int, out: Dictionary) -> void:
	var rng: RandomNumberGenerator = _chunk_rng(key, "tree")
	var sea: float = provider.sea_level()
	var placed: int = 0
	var attempts: int = 0
	while placed < count and attempts < count * 3:
		attempts += 1
		var u: float = rng.randf()
		var v: float = rng.randf()
		var dir: Vector3 = PropChunk.cell_point(key, u, v, chunk_depth)
		var bid: int = provider.biome_id(dir)
		if provider.tree_density(bid) <= 0.0:
			continue
		var h: float = provider.ground_height(dir)
		if h < sea - 0.6:
			continue
		var sp: int = provider.species_at(dir)
		out["instances"].append({
			"family": FAMILY_TREE, "dir": dir, "h": h, "species": sp,
			"trunk_h": rng.randf_range(1.8, 3.2),
			"crown": rng.randf_range(1.1, 2.0),
			"gval": 0.3 + 0.14 * rng.randf(),
			"tint_r": 0.18 + 0.06 * rng.randf(),
			"yaw": rng.randf_range(0.0, TAU),
		})
		placed += 1


## Bucket a face's fixed rock/boulder specs into their chunks (once per
## face). Each spec lands in the chunk containing its direction, so the
## chunk grid stays the addressing truth and no prop is duplicated.
func _bucket_face_content(face: int) -> void:
	if _rocks_faces_done.has(face):
		return
	_rocks_faces_done[face] = true
	var sea: float = provider.sea_level()
	for s in TerrainGen.rock_specs(world_seed, face):
		var d: Vector3 = s.dir
		var h: float = provider.ground_height(d)
		if h < sea - 0.6:
			continue
		var k: int = PropChunk.chunk_for_dir(d, chunk_depth)
		if not _rocks_by_chunk.has(k):
			_rocks_by_chunk[k] = []
		_rocks_by_chunk[k].append({"family": FAMILY_ROCK, "dir": d, "h": h,
				"scale": s.scale, "yaw": s.yaw, "face": face})
	for b in TerrainGen.boulder_specs(world_seed, face):
		var d2: Vector3 = b.dir
		var h2: float = provider.ground_height(d2)
		if h2 < sea - 0.6:
			continue
		var k2: int = PropChunk.chunk_for_dir(d2, chunk_depth)
		if not _boulders_by_chunk.has(k2):
			_boulders_by_chunk[k2] = []
		_boulders_by_chunk[k2].append({"family": FAMILY_BOULDER, "dir": d2, "h": h2,
				"radius": b.radius, "yaw": b.yaw, "face": face})


## Unbiased stochastic rounding of a non-negative expected count: returns
## floor(x) + 1 with probability frac(x). Average == x.
func _stochastic_count(x: float, rng: RandomNumberGenerator) -> int:
	if x <= 0.0:
		return 0
	var base: int = int(floor(x))
	var frac: float = x - float(base)
	if rng.randf() < frac:
		base += 1
	return base


## A deterministic RNG for one chunk's family stream (SeedChain-derived).
func _chunk_rng(key: int, family: String) -> RandomNumberGenerator:
	var seed_bytes: PackedByteArray = SeedChain.derive_seed([world_seed], "props/%s/%d/%d" % [family, chunk_depth, key])
	var acc: int = 0
	for b in seed_bytes:
		acc = (acc * 131 + b) % 9007199254740991
	var rng := RandomNumberGenerator.new()
	rng.seed = (acc + _decor_salt) % 9007199254740991
	return rng


## Build one prop instance into the chunk node.
func _build_instance(inst: Dictionary, node: Node3D, near: bool) -> void:
	match int(inst.get("family", -1)):
		FAMILY_TREE:
			_build_tree(inst, node, near)
		FAMILY_ROCK:
			_build_rock(inst, node)
		FAMILY_BOULDER:
			_build_boulder(inst, node)


## The rock's biome color law (ported from the streamer: alpine/tundra gray,
## badlands rust, desert sandstone, swamp mossy, default weathered).
func _rock_color(dir: Vector3) -> Color:
	match provider.biome_id(dir):
		TerrainGen.BiomeId.ALPINE, TerrainGen.BiomeId.TUNDRA:
			return Color(0.52, 0.54, 0.58)
		TerrainGen.BiomeId.BADLANDS:
			return Color(0.52, 0.33, 0.24)
		TerrainGen.BiomeId.DESERT:
			return Color(0.60, 0.52, 0.38)
		TerrainGen.BiomeId.SWAMP:
			return Color(0.36, 0.40, 0.30)
	return Color(0.45, 0.42, 0.40)


## A rock: a squat ellipsoid on its own radial, embedded ROCK_EMBED.
func _build_rock(inst: Dictionary, node: Node3D) -> void:
	var dir: Vector3 = inst["dir"]
	var rmi := MeshInstance3D.new()
	rmi.name = "Rock%d" % node.get_child_count()
	rmi.mesh = _shared_sphere(TerrainGen.ROCK_RADIUS * float(inst["scale"]), 2.0)
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = _rock_color(dir)
	rmat.roughness = 1.0
	rmi.material_override = rmat
	rmi.position = dir * (radius_m + float(inst["h"]) + TerrainGen.ROCK_EMBED)
	rmi.rotation.y = float(inst["yaw"])
	node.add_child(rmi)


## A boulder: a squat climbable ellipsoid, collider-carried (blocks/climb).
func _build_boulder(inst: Dictionary, node: Node3D) -> void:
	var dir: Vector3 = inst["dir"]
	var bmi := MeshInstance3D.new()
	bmi.name = "Boulder%d" % node.get_child_count()
	var br: float = float(inst["radius"])
	bmi.mesh = _shared_sphere(br, 1.7)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.40, 0.38, 0.37)
	bmat.roughness = 1.0
	bmi.material_override = bmat
	bmi.position = dir * (radius_m + float(inst["h"]) + br * 0.28)
	var up: Vector3 = dir
	var hint := Vector3(0, 1, 0)
	if absf(up.dot(hint)) > 0.999:
		hint = Vector3(0, 0, -1)
	var east: Vector3 = (hint - up * hint.dot(up)).normalized()
	var north: Vector3 = east.cross(up)
	bmi.basis = Basis(east, up, north)
	node.add_child(bmi)
	PropCollider.attach(bmi)


## A tree: trunk cylinder + species canopy sphere, radial placement.
func _build_tree(inst: Dictionary, node: Node3D, near: bool) -> void:
	var dir: Vector3 = inst["dir"]
	var tree := Node3D.new()
	tree.name = "Tree%d" % node.get_child_count()
	var up: Vector3 = dir
	var hint := Vector3(0, 1, 0)
	if absf(up.dot(hint)) > 0.999:
		hint = Vector3(0, 0, -1)
	var east: Vector3 = (hint - up * hint.dot(up)).normalized()
	var north: Vector3 = east.cross(up)
	var basis := Basis(east, up, north).rotated(up, float(inst["yaw"]))
	var trunk_h: float = float(inst["trunk_h"])
	var crown: float = float(inst["crown"])
	var sp: int = int(inst["species"])
	var trunk_w_mult: float = 1.0
	var canopy_h_mult: float = 1.8
	var canopy_w_mult: float = 1.0
	var tint_extra: float = 0.0
	var bare: bool = false
	match sp:
		TerrainGen.TreeSpecies.CONIFER:
			canopy_h_mult = 2.6
			canopy_w_mult = 0.62
			tint_extra = -0.06
		TerrainGen.TreeSpecies.ACACIA:
			canopy_h_mult = 0.9
			canopy_w_mult = 1.55
			tint_extra = 0.05
		TerrainGen.TreeSpecies.PALM:
			trunk_w_mult = 0.5
			canopy_h_mult = 0.55
			canopy_w_mult = 0.85
			tint_extra = 0.12
		TerrainGen.TreeSpecies.MANGROVE:
			canopy_h_mult = 1.1
			canopy_w_mult = 1.25
			tint_extra = -0.08
		TerrainGen.TreeSpecies.DEAD_SNAG:
			bare = true
		TerrainGen.TreeSpecies.BAOBAB:
			trunk_w_mult = 2.6
			canopy_w_mult = 1.35
			tint_extra = 0.04
	var trunk := MeshInstance3D.new()
	trunk.mesh = _shared_cyl(0.14 * trunk_w_mult, 0.22 * trunk_w_mult, trunk_h)
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(0.36, 0.26, 0.17)
	tmat.roughness = 1.0
	trunk.material_override = tmat
	trunk.position = Vector3(0, trunk_h * 0.5, 0)
	tree.add_child(trunk)
	if not bare:
		var canopy := MeshInstance3D.new()
		canopy.mesh = _shared_sphere(crown * canopy_w_mult, canopy_h_mult / canopy_w_mult)
		var cmat := StandardMaterial3D.new()
		cmat.albedo_color = Color(
			clampf(float(inst["tint_r"]) + tint_extra, 0.0, 0.6),
			clampf(float(inst["gval"]) + tint_extra * 0.5, 0.1, 0.7), 0.16)
		cmat.roughness = 1.0
		canopy.material_override = cmat
		canopy.position = Vector3(0, trunk_h + crown * canopy_h_mult * 0.35, 0)
		tree.add_child(canopy)
	tree.position = dir * (radius_m + float(inst["h"]))
	tree.basis = basis
	node.add_child(tree)
	if near:
		PropCollider.attach_trunk(tree)


# -- shared mesh registry (quantized keys; one resource per size class) --

func _shared_cyl(top_r: float, bottom_r: float, height: float) -> CylinderMesh:
	var key: String = "c@%d@%d@%d" % [int(round(top_r * 64.0)), int(round(bottom_r * 64.0)), int(round(height * 64.0))]
	var hit = _mesh_registry.get(key)
	if hit != null:
		return hit
	var cm := CylinderMesh.new()
	cm.top_radius = _q64(top_r)
	cm.bottom_radius = _q64(bottom_r)
	cm.height = _q64(height)
	_mesh_registry[key] = cm
	return cm


func _shared_sphere(r: float, aspect: float) -> SphereMesh:
	var key: String = "s@%d@%d" % [int(round(r * 64.0)), int(round(aspect * 64.0))]
	var hit = _mesh_registry.get(key)
	if hit != null:
		return hit
	var sm := SphereMesh.new()
	sm.radius = _q64(r)
	sm.height = _q64(r * 2.0 * aspect)
	_mesh_registry[key] = sm
	return sm


static func _q64(v: float) -> float:
	return round(v * 64.0) / 64.0


## Read-only counts for probes.
func built_count() -> int:
	return _built.size()


func pending_build() -> int:
	return _build_queue.size()


func cached_count() -> int:
	return _cache.size()


## A full deterministic re-derive of one chunk (bypasses the cache) -- the
## determinism probe compares this against the cached value.
func derive_fresh(key: int) -> Dictionary:
	var saved: Dictionary = _cache
	_cache = {}
	_cache_order = []
	var out: Dictionary = _derive_chunk(key)
	_cache = saved
	return out
