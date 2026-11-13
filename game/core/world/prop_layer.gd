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

## Detail-prop kinds (the dense near-field layer).
const KIND_TUFT: int = 0
const KIND_FLOWER: int = 1
const KIND_MUSHROOM: int = 2
const KIND_MYCELIUM: int = 3
const KIND_SHELL: int = 4
const KIND_WRACK: int = 5
const KIND_CATTAIL: int = 6
const KIND_BUSH: int = 7
const KIND_ORE: int = 8

## The DEEP family (the Sundered Sea's kelp/pearl gardens): a per-bed
## cluster, not a scattered point. Owned by the world's provider
## (`deep_beds()`), grown here so the RENDERER no longer owns the garden.
const FAMILY_DEEP: int = 4
## Deep-bed tuning (ported from the streamer's DEEP_* constants): the
## shelf's kelp band + the trench's pearl band, their anchor depths, and
## respawn windows.
const DEEP_KELP_M: float = 38.0
const DEEP_KELP_BAND: Vector2 = Vector2(30.0, 45.0)
const DEEP_PEARL_M: float = 54.0
const DEEP_PEARL_BAND: Vector2 = Vector2(50.0, 58.0)
const DEEP_KELP_RESPAWN: float = 420.0
const DEEP_PEARL_RESPAWN: float = 900.0

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

# Deep beds are per-face authored content (provider.deep_beds()), bucketed
# into chunks the same way rocks/boulders are.
var _deep_by_chunk: Dictionary = {}
var _deep_faces_done: Dictionary = {}
# Beds already registered this session (a chunk reload must NOT reset the
# service's depletion book -- register once per bed, ever).
var _deep_registered: Dictionary = {}


func configure(p_provider, p_radius: float, p_parent: Node3D, p_depth: int = PropChunk.DEFAULT_DEPTH) -> void:
	provider = p_provider
	radius_m = p_radius
	chunk_depth = p_depth
	_root = Node3D.new()
	_root.name = "PropLayerRoot"
	p_parent.add_child(_root)
	# The streaming radius scales with the globe: a 2 km world's 1600 m load
	# radius would cover most of the sphere, so clamp to a fraction of the
	# radius (the main world keeps its tuned 1600 m).
	_load_radius = minf(1600.0, maxf(radius_m * 0.35, 120.0))
	_unload_radius = _load_radius * 1.2
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
	if not data.get("tufts", []).is_empty():
		_build_tuft_batch(data["tufts"], node)
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
	var out: Dictionary = {"key": key, "instances": [], "tufts": []}
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
	# Deep-water beds (the Sundered Sea's kelp/pearl gardens): per-face
	# authored content, bucketed into this chunk.
	_bucket_deep_content(PropChunk.face_of(key))
	for bed in _deep_by_chunk.get(key, []):
		out["instances"].append(bed)
	# Trees. Count = density * area with UNBIASED stochastic rounding, so a
	# small chunk still gets a tree some of the time and the average matches
	# the density (a plain round() would zero every chunk below 0.5 expected).
	var tree_density: float = provider.tree_density(bid)
	var tree_n: int = _stochastic_count(tree_density * area_km2, _chunk_rng(key, "tcount"))
	if tree_n > 0:
		_derive_trees(key, tree_n, out)
	# Detail props (the dense near-field layer: tufts, flowers, mushrooms,
	# mycelium, shells, wrack, cattail, bush, ore).
	var detail_density: float = provider.detail_density(bid)
	var detail_n: int = _stochastic_count(detail_density * area_km2, _chunk_rng(key, "dcount"))
	if detail_n > 0:
		_derive_details(key, detail_n, out)
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


## Detail props: a biome-weighted kind per site, placed on the ground.
## The kind law mirrors the streamer's tiers (tufts fill the meadow; the
## wet bands grow mushrooms + mycelium; the dry bands split brush vs ore;
## the shore splits shells vs kelp wrack; the marsh grows cattail; shrub
## bands grow bushes).
func _derive_details(key: int, count: int, out: Dictionary) -> void:
	var rng: RandomNumberGenerator = _chunk_rng(key, "detail")
	var sea: float = provider.sea_level()
	var placed: int = 0
	var attempts: int = 0
	while placed < count and attempts < count * 3:
		attempts += 1
		var u: float = rng.randf()
		var v: float = rng.randf()
		var dir: Vector3 = PropChunk.cell_point(key, u, v, chunk_depth)
		var bid: int = provider.biome_id(dir)
		if provider.detail_density(bid) <= 0.0:
			continue
		var h: float = provider.ground_height(dir)
		if h < sea - 0.6:
			continue
		var kind: int = _detail_kind(bid, rng)
		if kind < 0:
			continue
		if kind == KIND_TUFT:
			# The tuft field is one MultiMesh per chunk (the batch law).
			out["tufts"].append({"dir": dir, "h": h,
					"scale": rng.randf_range(0.7, 1.6), "yaw": rng.randf_range(0.0, TAU)})
			placed += 1
			continue
		var rec: Dictionary = {"family": FAMILY_DETAIL, "kind": kind, "dir": dir, "h": h, "bid": bid}
		match kind:
			KIND_FLOWER:
				rec["stem_h"] = rng.randf_range(0.20, 0.38)
				rec["r_h"] = rng.randf_range(0.055, 0.105)
				rec["pal"] = rng.randi() % 5
			KIND_MUSHROOM:
				rec["cap_r"] = rng.randf_range(0.10, 0.30)
				rec["stem_h"] = rng.randf_range(0.18, 0.55)
				rec["pal"] = rng.randi() % 4
			KIND_MYCELIUM:
				rec["patch_r"] = rng.randf_range(0.5, 1.3)
				rec["hue"] = rng.randf()
			KIND_SHELL:
				rec["r_s"] = rng.randf_range(0.05, 0.12)
			KIND_WRACK:
				rec["r_w"] = rng.randf_range(0.25, 0.55)
				rec["tint"] = rng.randf()
			KIND_CATTAIL:
				rec["h_stalk"] = rng.randf_range(0.9, 1.4)
			KIND_BUSH:
				rec["r_b"] = rng.randf_range(0.4, 0.9)
				rec["tint_r"] = 0.22 + 0.1 * rng.randf()
				rec["tint_g"] = 0.42 + 0.1 * rng.randf()
			KIND_ORE:
				rec["r_o"] = rng.randf_range(0.35, 0.7)
			_:
				rec["scale"] = rng.randf_range(0.7, 1.6)
				rec["yaw"] = rng.randf_range(0.0, TAU)
		out["instances"].append(rec)
		placed += 1


## The detail kind for a biome (mirrors the streamer's tier ladder).
func _detail_kind(bid: int, rng: RandomNumberGenerator) -> int:
	# A world may own the biome->kind law (BiomeBand family dispatch); the
	# provider returns -2 to defer to this built-in main-world ladder.
	if provider != null and provider.has_method("detail_kind"):
		var owned: int = provider.detail_kind(bid, rng)
		if owned != -2:
			return owned
	match bid:
		TerrainGen.BiomeId.SHORE:
			var r: float = rng.randf()
			if r < 0.60:
				return KIND_SHELL
			if r < 0.77:
				return KIND_WRACK
			return -1  # bare sand
		TerrainGen.BiomeId.SWAMP:
			var fs: float = rng.randf()
			if fs < 0.14:
				return KIND_MUSHROOM
			if fs < 0.22:
				return KIND_MYCELIUM
			if fs < 0.35:
				return KIND_CATTAIL
			if fs < 0.55:
				return KIND_BUSH
			return KIND_TUFT
		TerrainGen.BiomeId.FOREST, TerrainGen.BiomeId.JUNGLE, TerrainGen.BiomeId.TAIGA:
			var ff: float = rng.randf()
			if ff < 0.14:
				return KIND_MUSHROOM
			if ff < 0.22:
				return KIND_MYCELIUM
			if ff < 0.35:
				return KIND_BUSH
			if ff < 0.45:
				return KIND_FLOWER
			return KIND_TUFT
		TerrainGen.BiomeId.DESERT, TerrainGen.BiomeId.BADLANDS, \
		TerrainGen.BiomeId.TUNDRA, TerrainGen.BiomeId.STEPPE, TerrainGen.BiomeId.ALPINE:
			if rng.randf() < 0.55:
				return KIND_TUFT
			return KIND_ORE
		TerrainGen.BiomeId.GRASSLAND:
			var fg: float = rng.randf()
			if fg < 0.10:
				return KIND_FLOWER
			if fg > 0.82:
				return KIND_BUSH
			return KIND_TUFT
		TerrainGen.BiomeId.SAVANNA, TerrainGen.BiomeId.ALPINE_MEADOW:
			var fv: float = rng.randf()
			if fv < 0.06:
				return KIND_FLOWER
			if fv > 0.86:
				return KIND_BUSH
			return KIND_TUFT
	return -1


## Bucket a face's fixed rock/boulder specs into their chunks (once per
## face). Each spec lands in the chunk containing its direction, so the
## chunk grid stays the addressing truth and no prop is duplicated.
func _bucket_face_content(face: int) -> void:
	if _rocks_faces_done.has(face):
		return
	_rocks_faces_done[face] = true
	var sea: float = provider.sea_level()
	for s in provider.rock_specs(face):
		var d: Vector3 = s.dir
		var h: float = provider.ground_height(d)
		if h < sea - 0.6:
			continue
		var k: int = PropChunk.chunk_for_dir(d, chunk_depth)
		if not _rocks_by_chunk.has(k):
			_rocks_by_chunk[k] = []
		_rocks_by_chunk[k].append({"family": FAMILY_ROCK, "dir": d, "h": h,
				"scale": s.scale, "yaw": s.yaw, "face": face})
	for b in provider.boulder_specs(face):
		var d2: Vector3 = b.dir
		var h2: float = provider.ground_height(d2)
		if h2 < sea - 0.6:
			continue
		var k2: int = PropChunk.chunk_for_dir(d2, chunk_depth)
		if not _boulders_by_chunk.has(k2):
			_boulders_by_chunk[k2] = []
		_boulders_by_chunk[k2].append({"family": FAMILY_BOULDER, "dir": d2, "h": h2,
				"radius": b.radius, "yaw": b.yaw, "face": face})


## Bucket the world's authored deep beds (provider.deep_beds()) into
## chunks: each bed is a per-bed cluster that rides the chunk containing
## its direction. Computed once per face.
func _bucket_deep_content(face: int) -> void:
	if _deep_faces_done.has(face):
		return
	_deep_faces_done[face] = true
	if provider == null or not provider.has_method("deep_beds"):
		return
	for bed in provider.deep_beds():
		var d: Vector3 = bed["dir"]
		if PropChunk.face_containing(d) != face:
			continue
		var k: int = PropChunk.chunk_for_dir(d, chunk_depth)
		if not _deep_by_chunk.has(k):
			_deep_by_chunk[k] = []
		_deep_by_chunk[k].append({"family": FAMILY_DEEP, "dir": d,
				"deep_kind": int(bed["kind"]), "bed": int(bed["bed"]),
				"face": face})


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
		FAMILY_DETAIL:
			_build_detail(inst, node)
		FAMILY_DEEP:
			_build_deep_bed(inst, node, near)


## Detail prop build: tufts go to the batch (below); the rest are small nodes.
func _build_detail(inst: Dictionary, node: Node3D) -> void:
	match int(inst.get("kind", -1)):
		KIND_FLOWER:
			_build_flower(inst, node)
		KIND_MUSHROOM:
			_build_mushroom(inst, node)
		KIND_MYCELIUM:
			_build_mycelium(inst, node)
		KIND_SHELL:
			_build_shell(inst, node)
		KIND_WRACK:
			_build_wrack(inst, node)
		KIND_CATTAIL:
			_build_cattail(inst, node)
		KIND_BUSH:
			_build_bush(inst, node)
		KIND_ORE:
			_build_ore(inst, node)


## The tuft field: one MultiMesh per chunk (a node per blade would flood
## the tree; the streamer paints the field the same way).
func _build_tuft_batch(tufts: Array, node: Node3D) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _shared_tuft_mesh()
	mm.instance_count = tufts.size()
	for i in range(tufts.size()):
		var t: Dictionary = tufts[i]
		var dir: Vector3 = t["dir"]
		var up: Vector3 = dir
		var hint := Vector3(0, 1, 0)
		if absf(up.dot(hint)) > 0.999:
			hint = Vector3(1, 0, 0)
		var east: Vector3 = (hint - up * hint.dot(up)).normalized()
		var b := Basis(east, up, east.cross(up)).rotated(up, float(t["yaw"])).scaled(Vector3.ONE * float(t["scale"]))
		mm.set_instance_transform(i, Transform3D(b, dir * (radius_m + float(t["h"]))))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Tufts"
	mmi.multimesh = mm
	mmi.material_override = _tuft_material()
	node.add_child(mmi)


## A tuft: a thin tapered cone (a blade clump), pivoted at the ground.
func _shared_tuft_mesh() -> Mesh:
	var key: String = "tuft"
	if _mesh_registry.has(key):
		return _mesh_registry[key]
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.02
	mesh.bottom_radius = 0.09
	mesh.height = 0.35
	mesh.radial_segments = 5
	mesh.rings = 1
	mesh.cap_top = false
	_mesh_registry[key] = mesh
	return mesh


func _tuft_material() -> StandardMaterial3D:
	var key: String = "tuft_mat"
	if _mesh_registry.has(key):
		return _mesh_registry[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.44, 0.20)
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh_registry[key] = mat
	return mat


func _build_flower(inst: Dictionary, node: Node3D) -> void:
	var dir: Vector3 = inst["dir"]
	var base: Vector3 = dir * (radius_m + float(inst["h"]))
	var g := Node3D.new()
	g.name = "Flower%d" % node.get_child_count()
	g.position = base
	var stem_h: float = float(inst["stem_h"])
	var stem := MeshInstance3D.new()
	stem.mesh = _shared_cyl(0.022, 0.022, stem_h)
	stem.position = Vector3(0.0, stem_h * 0.5, 0.0)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.25, 0.40, 0.18)
	stem.material_override = smat
	g.add_child(stem)
	var head := MeshInstance3D.new()
	head.mesh = _shared_sphere(float(inst["r_h"]), 1.3)
	head.position = Vector3(0.0, stem_h, 0.0)
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = _bloom_palette()[int(inst["pal"]) % _bloom_palette().size()]
	head.material_override = hmat
	g.add_child(head)
	node.add_child(g)


func _bloom_palette() -> Array:
	return [Color(0.95, 0.85, 0.35), Color(0.90, 0.45, 0.60), Color(0.75, 0.55, 0.90),
			Color(0.95, 0.60, 0.30), Color(0.92, 0.92, 0.88)]


func _build_mushroom(inst: Dictionary, node: Node3D) -> void:
	var dir: Vector3 = inst["dir"]
	var base: Vector3 = dir * (radius_m + float(inst["h"]))
	var g := Node3D.new()
	g.name = "Mushroom%d" % node.get_child_count()
	g.position = base
	var stem_h: float = float(inst["stem_h"])
	var stem := MeshInstance3D.new()
	stem.mesh = _shared_cyl(0.04, 0.04, stem_h)
	stem.position = Vector3(0.0, stem_h * 0.5, 0.0)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.85, 0.82, 0.72)
	stem.material_override = smat
	g.add_child(stem)
	var cap := MeshInstance3D.new()
	cap.mesh = _shared_sphere(float(inst["cap_r"]), 1.5)
	cap.position = Vector3(0.0, stem_h + float(inst["cap_r"]) * 0.2, 0.0)
	cap.scale = Vector3(1.0, 0.6, 1.0)
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = [Color(0.75, 0.30, 0.25), Color(0.55, 0.35, 0.70),
			Color(0.85, 0.70, 0.30), Color(0.35, 0.55, 0.45)][int(inst["pal"]) % 4]
	cap.material_override = cmat
	g.add_child(cap)
	node.add_child(g)


func _build_mycelium(inst: Dictionary, node: Node3D) -> void:
	var dir: Vector3 = inst["dir"]
	var mi := MeshInstance3D.new()
	mi.name = "Mycelium%d" % node.get_child_count()
	var r: float = float(inst["patch_r"])
	var disc := CylinderMesh.new()
	disc.top_radius = r
	disc.bottom_radius = r
	disc.height = 0.03
	disc.radial_segments = 10
	mi.mesh = disc
	var mat := StandardMaterial3D.new()
	var hue: float = float(inst["hue"])
	mat.albedo_color = Color(0.35 + 0.2 * hue, 0.30, 0.55 + 0.2 * (1.0 - hue))
	mat.emission_enabled = true
	mat.emission = Color(0.30, 0.45, 0.75)
	mat.emission_energy_multiplier = 1.2
	mi.material_override = mat
	mi.position = dir * (radius_m + float(inst["h"]) + 0.03)
	node.add_child(mi)


func _build_shell(inst: Dictionary, node: Node3D) -> void:
	var dir: Vector3 = inst["dir"]
	var r: float = float(inst["r_s"])
	var mi := MeshInstance3D.new()
	mi.name = "Shell%d" % node.get_child_count()
	mi.mesh = _shared_sphere(r, 1.4)
	mi.scale = Vector3(1.0, 0.5, 1.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.92, 0.90, 0.84)
	mi.material_override = mat
	mi.position = dir * (radius_m + float(inst["h"]) + r * 0.35)
	node.add_child(mi)


func _build_wrack(inst: Dictionary, node: Node3D) -> void:
	var dir: Vector3 = inst["dir"]
	var r: float = float(inst["r_w"])
	var mi := MeshInstance3D.new()
	mi.name = "Wrack%d" % node.get_child_count()
	mi.mesh = _shared_sphere(r, 1.5)
	mi.scale = Vector3(1.0, 0.7, 1.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.32, 0.18).lerp(Color(0.30, 0.24, 0.14), float(inst["tint"]))
	mi.material_override = mat
	mi.position = dir * (radius_m + float(inst["h"]) + r * 0.25)
	node.add_child(mi)


func _build_cattail(inst: Dictionary, node: Node3D) -> void:
	var dir: Vector3 = inst["dir"]
	var base: Vector3 = dir * (radius_m + float(inst["h"]) + 0.05)
	var g := Node3D.new()
	g.name = "Cattail%d" % node.get_child_count()
	g.position = base
	var h: float = float(inst["h_stalk"])
	var stalk := MeshInstance3D.new()
	stalk.mesh = _shared_cyl(0.02, 0.02, h)
	stalk.position = Vector3(0.0, h * 0.5, 0.0)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.35, 0.45, 0.25)
	stalk.material_override = smat
	g.add_child(stalk)
	var head := MeshInstance3D.new()
	head.mesh = _shared_cyl(0.05, 0.05, 0.22)
	head.position = Vector3(0.0, h - 0.1, 0.0)
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.42, 0.30, 0.16)
	head.material_override = hmat
	g.add_child(head)
	node.add_child(g)


func _build_bush(inst: Dictionary, node: Node3D) -> void:
	var dir: Vector3 = inst["dir"]
	var r: float = float(inst["r_b"])
	var mi := MeshInstance3D.new()
	mi.name = "Bush%d" % node.get_child_count()
	mi.mesh = _shared_sphere(r, 1.4)
	mi.scale = Vector3(1.0, 0.8, 1.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(float(inst["tint_r"]), float(inst["tint_g"]), 0.22)
	mi.material_override = mat
	mi.position = dir * (radius_m + float(inst["h"]) + r * 0.25)
	node.add_child(mi)


func _build_ore(inst: Dictionary, node: Node3D) -> void:
	var dir: Vector3 = inst["dir"]
	var r: float = float(inst["r_o"])
	var mi := MeshInstance3D.new()
	mi.name = "Ore%d" % node.get_child_count()
	mi.mesh = _shared_sphere(r, 1.2)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.28, 0.26, 0.30)
	mat.metallic = 0.7
	mat.roughness = 0.4
	mi.material_override = mat
	mi.position = dir * (radius_m + float(inst["h"]) + r * 0.2)
	node.add_child(mi)


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


## A deep-water bed (the Sundered Sea's kelp shelf / pearl trench): a
## per-bed CLUSTER -- kelp strands + reef boulders on the shelf, vent
## spires + drowned stones in the trench -- plus three hidden stumps the
## deep_garden_binder flips per the harvest book. The garden rides a
## 'deep_garden' node carrying the plant ids, so the binder joins paint to
## the service's own depletion truth (the S14.7.3 law, now chunk-addressed).
func _build_deep_bed(inst: Dictionary, node: Node3D, near: bool) -> void:
	var dir: Vector3 = inst["dir"]
	var kind: int = int(inst["deep_kind"])
	var face: int = int(inst["face"])
	var bed_idx: int = int(inst["bed"])
	var zone_id: String = str(inst.get("zone_id", "zone_sundered_sea"))
	var up: Vector3 = dir
	var hint := Vector3(0, 1, 0)
	if absf(up.dot(hint)) > 0.999:
		hint = Vector3(1, 0, 0)
	var east: Vector3 = (hint - up * hint.dot(up)).normalized()
	var north: Vector3 = up.cross(east)
	var sea_r: float = radius_m + provider.sea_level()
	var root_r: float = sea_r - (DEEP_KELP_M if kind == 1 else DEEP_PEARL_M)
	var band: Vector2 = DEEP_KELP_BAND if kind == 1 else DEEP_PEARL_BAND
	var depth_m: float = DEEP_KELP_M if kind == 1 else DEEP_PEARL_M
	var acc: int = _face_acc(face)
	# THE PER-PLANT TRUTH (the register call's jitter replayed seed-for-seed):
	# the paint learns which strand stands on which registered plant, so
	# per-plant depletion can shear the paint honestly.
	var plants := RandomNumberGenerator.new()
	plants.seed = (acc + 9091 + bed_idx * 101) % 9007199254740991
	var plant_dirs: Array = []
	var plant_depths: Array = []
	for k in range(3):
		var jx: float = plants.randf_range(-0.0016, 0.0016)
		var jy: float = plants.randf_range(-0.0016, 0.0016)
		plant_dirs.append((dir + east * jx + north * jy).normalized())
		plant_depths.append(clampf(depth_m + plants.randf_range(-3.0, 3.0), band.x + 1.0, band.y - 1.0))
	var prefix := "deep_kelp" if kind == 1 else "deep_pearl"
	var plant_ids: Array = []
	for k in range(3):
		plant_ids.append("%s_%d_%d_%d" % [prefix, face, bed_idx, k])
	_register_deep_bed(zone_id, kind, plant_ids, plant_dirs, plant_depths, sea_r)
	var grove := Node3D.new()
	grove.name = "DeepGarden%d_%d" % [face, bed_idx]
	grove.add_to_group("deep_garden")
	grove.set_meta("deep_kind", kind)
	grove.set_meta("harvest_ids", plant_ids)
	var rng := RandomNumberGenerator.new()
	rng.seed = (acc + 31337 + bed_idx * 101) % 9007199254740991
	if kind == 1:
		# THE KELP SHELF: strands tall enough to read from the surface.
		for k in range(14):
			var spread: float = rng.randf_range(0.0008, 0.0075)
			var d_k: Vector3 = (dir + east * rng.randf_range(-spread, spread)
				+ north * rng.randf_range(-spread, spread)).normalized()
			var h: float = rng.randf_range(7.0, 14.0)
			var stalk := MeshInstance3D.new()
			stalk.name = "Kelp%d" % k
			stalk.mesh = _shared_cyl(0.09, 0.17, h)
			stalk.material_override = _kelp_material()
			stalk.position = d_k * (sea_r - DEEP_KELP_M + h * 0.5)
			stalk.basis = Basis(east, d_k, north).rotated(d_k, rng.randf_range(0.0, TAU))
			stalk.set_meta("plant_k", _nearest_plant(plant_dirs, d_k))
			grove.add_child(stalk)
		for k in range(4):
			var bd: Vector3 = (dir + east * rng.randf_range(-0.004, 0.004)
				+ north * rng.randf_range(-0.004, 0.004)).normalized()
			var boulder := MeshInstance3D.new()
			boulder.name = "Reef%d" % k
			boulder.mesh = _shared_cyl(1.2, 2.4, rng.randf_range(1.4, 2.8))
			boulder.material_override = _reef_material()
			boulder.position = bd * (sea_r - DEEP_KELP_M - 3.0)
			grove.add_child(boulder)
	else:
		# THE TRENCH: pale vent spires + drowned stones.
		for k in range(6):
			var sd: Vector3 = (dir + east * rng.randf_range(-0.003, 0.003)
				+ north * rng.randf_range(-0.003, 0.003)).normalized()
			var sh: float = rng.randf_range(5.0, 11.0)
			var spire := MeshInstance3D.new()
			spire.name = "Spire%d" % k
			spire.mesh = _shared_cyl(0.35, 1.1, sh)
			spire.material_override = _reef_material()
			spire.position = sd * (root_r + sh * 0.5)
			spire.set_meta("plant_k", _nearest_plant(plant_dirs, sd))
			grove.add_child(spire)
		for k in range(2):
			var pd: Vector3 = (dir + east * rng.randf_range(-0.002, 0.002)
				+ north * rng.randf_range(-0.002, 0.002)).normalized()
			var stone := MeshInstance3D.new()
			stone.name = "TrenchStone%d" % k
			stone.mesh = _shared_cyl(1.0, 1.8, rng.randf_range(1.0, 1.8))
			stone.material_override = _reef_material()
			stone.position = pd * (root_r - 1.5)
			grove.add_child(stone)
	# THE STUMPS: hidden at build; the deep_garden_binder flips them off the
	# service's own depletion book (never a second book here).
	var stump_mat: Material = _kelp_material() if kind == 1 else _reef_material()
	var stump_dims: Vector3 = Vector3(0.10, 0.16, 0.55) if kind == 1 else Vector3(0.35, 0.6, 0.6)
	for k in range(3):
		var stump := MeshInstance3D.new()
		stump.name = "Stump%d" % k
		stump.mesh = _shared_cyl(stump_dims.x, stump_dims.y, stump_dims.z)
		stump.material_override = stump_mat
		stump.position = plant_dirs[k] * (root_r + stump_dims.z * 0.5)
		stump.set_meta("plant_k", k)
		stump.visible = false
		grove.add_child(stump)
	node.add_child(grove)


## Register a bed's three plants as live HarvestService nodes (the gather
## half of the one placement law). Main thread only (service registration
## is a side effect, never worker work).
func _register_deep_bed(zone_id: String, kind: int, plant_ids: Array,
		plant_dirs: Array, plant_depths: Array, sea_r: float) -> void:
	var svc = _harvest_service()
	if svc == null or not svc.has_method("register_node"):
		return
	if _deep_registered.has(plant_ids[0]):
		return
	_deep_registered[plant_ids[0]] = true
	var item_id := "res_kelp_fiber" if kind == 1 else "res_abyss_pearl"
	var band: Vector2 = DEEP_KELP_BAND if kind == 1 else DEEP_PEARL_BAND
	var respawn: float = DEEP_KELP_RESPAWN if kind == 1 else DEEP_PEARL_RESPAWN
	for k in range(plant_ids.size()):
		var d_k: Vector3 = plant_dirs[k]
		var depth_k: float = float(plant_depths[k])
		svc.register_node(str(plant_ids[k]), zone_id, item_id,
			d_k * (sea_r - depth_k), 1, respawn, band.x, band.y)


## The plant a strand stands on (nearest of the bed's three), so per-plant
## depletion shears the paint honestly.
func _nearest_plant(plant_dirs: Array, d: Vector3) -> int:
	var owner: int = 0
	for pk in range(plant_dirs.size()):
		if (plant_dirs[pk] as Vector3).angle_to(d) < (plant_dirs[owner] as Vector3).angle_to(d):
			owner = pk
	return owner


## The stable per-face accumulator the bed seeds read (world-seed only, no
## day salt -- anchored culture must survive a re-stream).
func _face_acc(face: int) -> int:
	var bytes: PackedByteArray = SeedChain.derive_seed([world_seed], "props/deepface/%d" % face)
	var acc: int = 0
	for b in bytes:
		acc = (acc * 131 + b) % 9007199254740991
	return acc


## The HarvestService (absent in bare hosts; registration is then skipped).
func _harvest_service():
	var tree = Engine.get_main_loop()
	if tree == null or not (tree is SceneTree):
		return null
	return (tree as SceneTree).root.get_node_or_null(NodePath("HarvestService"))


## The shelf's green-black kelp (one cached material).
var _kelp_mat_res: StandardMaterial3D = null
var _reef_mat_res: StandardMaterial3D = null

func _kelp_material() -> StandardMaterial3D:
	if _kelp_mat_res != null:
		return _kelp_mat_res
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.10, 0.32, 0.24)
	m.roughness = 1.0
	_kelp_mat_res = m
	return m


## The reef's wet stone (one cached material).
func _reef_material() -> StandardMaterial3D:
	if _reef_mat_res != null:
		return _reef_mat_res
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.24, 0.27, 0.27)
	m.roughness = 1.0
	_reef_mat_res = m
	return m
