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
const MarkovScript = preload("res://core/frame/srv/markov.gd")

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
const KIND_CACTUS: int = 9
const KIND_FERN: int = 10

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

## The grass carpet's per-chunk ceiling: even a very dense biome caps its
## blades per chunk so the derive stays bounded (the near view still reads
## as a carpet; the far view never pays for it).
const GRASS_PER_CHUNK_CAP: int = 640

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

# Land harvestables (mushrooms / ore / bushes) already registered this
# session, keyed by node id -- a chunk reload must not re-register.
var _land_registered: Dictionary = {}

# Predictive prefetch (the canonical read side): a Markov model of the
# viewer's chunk-to-chunk movement warms the cell it is heading into
# BEFORE arrival, so props are ready and the build queue is empty on
# crossing. Off by default; a consumer enables it via enable_prefetch().
var _markov = null
var _prefetch_enabled: bool = false
var _prefetch_viewer_id: String = ""
var _prefetched: Dictionary = {}


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


## Turn on predictive prefetch for one viewer. The layer learns the
## viewer's canonical chunk-to-chunk movement and warms the predicted
## next cell before arrival (the read side of the canonical addressing).
func enable_prefetch(viewer_id: String) -> void:
	_markov = MarkovScript.new()
	_prefetch_viewer_id = viewer_id
	_prefetch_enabled = true


func disable_prefetch() -> void:
	_prefetch_enabled = false


## The canonical chunk key the viewer currently occupies.
func current_chunk_key() -> int:
	if _markov == null or _prefetch_viewer_id == "":
		return -1
	return int(_markov.get_current_chunk(_prefetch_viewer_id))


## One prefetch step: observe the viewer's cell, then derive (cache) the
## top predicted cell so the build queue has nothing to do on arrival.
func _prefetch_step(viewer_dir: Vector3) -> void:
	var key: int = PropChunk.chunk_for_dir(viewer_dir, chunk_depth)
	_markov.observe(_prefetch_viewer_id, key, chunk_depth)
	var preds: Array = _markov.predict_next(_prefetch_viewer_id)
	if preds.is_empty():
		return
	var target: int = int(preds[0].get("chunk_key", -1))
	if target < 0 or target == key:
		return
	# Only warm cells inside the load radius -- a prediction never
	# reaches past what the streamer could build anyway.
	var ang_load: float = _load_radius / maxf(radius_m, 1.0)
	if PropChunk.chunk_center_dir(target, chunk_depth).angle_to(viewer_dir) > ang_load:
		return
	if not _cache.has(target):
		_derive_chunk(target)          # pure: fills the LRU, no scene nodes
		_prefetched[target] = true


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
	# Predictive prefetch rides the SAME viewer direction: observe the
	# current canonical chunk and warm the predicted next one.
	if _prefetch_enabled:
		_prefetch_step(dir)
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
	if not data.get("grass", []).is_empty():
		_build_grass_batch(data["grass"], node)
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
	var detail_n: int = _stochastic_count(detail_density * area_km2, _chunk_rng(key, "dcount", false))
	if detail_n > 0:
		_derive_details(key, detail_n, out)
	# Grass carpet (the dense ground-cover field): a world may declare a
	# separate per-biome grass density so a meadow can be thick without
	# flooding the discrete detail kinds. One MultiMesh per chunk.
	if provider.has_method("grass_density"):
		var grass_density: float = provider.grass_density(bid)
		var grass_n: int = _stochastic_count(grass_density * area_km2, _chunk_rng(key, "gcount", false))
		if grass_n > 0:
			_derive_grass(key, grass_n, out)
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
		# THE VINE LAW (v7): wood-creeper threads hang from the wet bands'
		# canopies -- JUNGLE dense (2..4), FOREST sparse (0..2), SWAMP mossy
		# (1..3). Pure paint (no collider, no harvest); a dead snag bears none.
		var vine_n: int = 0
		if sp != TerrainGen.TreeSpecies.DEAD_SNAG:
			match bid:
				TerrainGen.BiomeId.JUNGLE:
					vine_n = 2 + (rng.randi() % 3)
				TerrainGen.BiomeId.FOREST:
					vine_n = rng.randi() % 3
				TerrainGen.BiomeId.SWAMP:
					vine_n = 1 + (rng.randi() % 3)
		out["instances"].append({
			"family": FAMILY_TREE, "dir": dir, "h": h, "species": sp,
			"trunk_h": rng.randf_range(1.8, 3.2),
			"crown": rng.randf_range(1.1, 2.0),
			"gval": 0.3 + 0.14 * rng.randf(),
			"tint_r": 0.18 + 0.06 * rng.randf(),
			"yaw": rng.randf_range(0.0, TAU),
			"vine_n": vine_n,
		})
		placed += 1


## Detail props: a biome-weighted kind per site, placed on the ground.
## The kind law mirrors the streamer's tiers (tufts fill the meadow; the
## wet bands grow mushrooms + mycelium; the dry bands split brush vs ore;
## the shore splits shells vs kelp wrack; the marsh grows cattail; shrub
## bands grow bushes).
func _derive_details(key: int, count: int, out: Dictionary) -> void:
	# The site PLACEMENT (and every harvestable kind's params) is anchored:
	# world-seed only, so the drawn prop is the gatherable node across days.
	var rng: RandomNumberGenerator = _chunk_rng(key, "detail", false)
	# The tuft field is the decorative band (grass): it mixes the session
	# salt so the meadow look recombines between days (FIELD-2 split).
	var tuft_rng: RandomNumberGenerator = _chunk_rng(key, "tuft", true)
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
					"scale": tuft_rng.randf_range(0.7, 1.6), "yaw": tuft_rng.randf_range(0.0, TAU)})
			placed += 1
			continue
		# The stable per-site id (chunk-keyed): the paint and the harvest
		# registration derive it from the SAME cell, so the drawn prop is the
		# gatherable node (the one placement law, both halves).
		var site_id: String = "hs_%d_%d" % [key, placed]
		var rec: Dictionary = {"family": FAMILY_DETAIL, "kind": kind, "dir": dir, "h": h,
				"bid": bid, "site_id": site_id}
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
			KIND_CACTUS:
				rec["h_c"] = rng.randf_range(1.0, 2.2)
				rec["arms"] = rng.randi() % 3
			KIND_FERN:
				rec["fronds"] = 5 + rng.randi() % 3
				rec["frond_h"] = rng.randf_range(0.4, 0.9)
			_:
				rec["scale"] = rng.randf_range(0.7, 1.6)
				rec["yaw"] = rng.randf_range(0.0, TAU)
		out["instances"].append(rec)
		placed += 1


## Grass carpet: dense blade clusters placed like the tuft field but at the
## biome's grass density. Purely decorative (no harvest, no collider); one
## MultiMesh per chunk. Session-salted so the carpet recombines between days
## (the FIELD-2 decorative split -- grass is not anchored culture).
func _derive_grass(key: int, count: int, out: Dictionary) -> void:
	count = mini(count, GRASS_PER_CHUNK_CAP)
	var rng: RandomNumberGenerator = _chunk_rng(key, "grass", true)
	var sea: float = provider.sea_level()
	var blades: Array = []
	var attempts: int = 0
	while blades.size() < count and attempts < count * 2:
		attempts += 1
		var dir: Vector3 = PropChunk.cell_point(key, rng.randf(), rng.randf(), chunk_depth)
		if provider.grass_density(provider.biome_id(dir)) <= 0.0:
			continue
		var h: float = provider.ground_height(dir)
		if h < sea - 0.6:
			continue
		blades.append({"dir": dir, "h": h,
				"scale": rng.randf_range(0.6, 1.5), "yaw": rng.randf_range(0.0, TAU)})
	out["grass"] = blades


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
			if ff < 0.13:
				return KIND_MUSHROOM
			if ff < 0.20:
				return KIND_MYCELIUM
			if ff < 0.32:
				return KIND_BUSH
			if ff < 0.42:
				return KIND_FERN
			if ff < 0.52:
				return KIND_FLOWER
			return KIND_TUFT
		TerrainGen.BiomeId.DESERT, TerrainGen.BiomeId.BADLANDS:
			var fd: float = rng.randf()
			if fd < 0.30:
				return KIND_CACTUS
			if fd < 0.62:
				return KIND_TUFT
			return KIND_ORE
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
	var face_acc: int = _face_acc(face)
	var rock_i: int = 0
	for s in provider.rock_specs(face):
		var d: Vector3 = s.dir
		var h: float = provider.ground_height(d)
		if h < sea - 0.6:
			continue
		var k: int = PropChunk.chunk_for_dir(d, chunk_depth)
		if not _rocks_by_chunk.has(k):
			_rocks_by_chunk[k] = []
		var rec: Dictionary = {"family": FAMILY_ROCK, "dir": d, "h": h,
				"scale": s.scale, "yaw": s.yaw, "face": face}
		_scree_for(rec, face_acc, rock_i, d, h, float(s.scale))
		_rocks_by_chunk[k].append(rec)
		rock_i += 1
	var boulder_i: int = 0
	for b in provider.boulder_specs(face):
		var d2: Vector3 = b.dir
		var h2: float = provider.ground_height(d2)
		if h2 < sea - 0.6:
			continue
		var k2: int = PropChunk.chunk_for_dir(d2, chunk_depth)
		if not _boulders_by_chunk.has(k2):
			_boulders_by_chunk[k2] = []
		var rec2: Dictionary = {"family": FAMILY_BOULDER, "dir": d2, "h": h2,
				"radius": b.radius, "yaw": b.yaw, "face": face}
		_collar_for(rec2, face_acc, boulder_i, d2, float(b.radius))
		_boulders_by_chunk[k2].append(rec2)
		boulder_i += 1


## The scree collar (v7): in the rocky bands (alpine/tundra/badlands) each
## rock drops a seeded 2..4-rubble collar on its rim. Pure paint -- no
## walk-cap change (the rubble sits below the cap the rock already raises).
## Computed once per rock at bucket time (deterministic from the face seed).
func _scree_for(rec: Dictionary, face_acc: int, rock_i: int, dir: Vector3, h: float, scale: float) -> void:
	var bid: int = provider.biome_id(dir)
	if bid != TerrainGen.BiomeId.ALPINE and bid != TerrainGen.BiomeId.TUNDRA \
			and bid != TerrainGen.BiomeId.BADLANDS:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = (face_acc * 131 + rock_i * 7 + 3) % 9007199254740991
	var rock_r: float = radius_m + h + TerrainGen.ROCK_EMBED
	var n: int = rng.randi_range(2, 4)
	var out: Array = []
	for _k in range(n):
		var hint: Vector3 = Vector3(0, 1, 0) if absf(dir.dot(Vector3(0, 1, 0))) < 0.9 else Vector3(1, 0, 0)
		var axis: Vector3 = dir.cross(hint).normalized()
		var sdir: Vector3 = dir.rotated(axis, \
				(TerrainGen.ROCK_RADIUS * scale * (1.25 + 0.4 * rng.randf())) / maxf(rock_r, 1.0) \
				+ rng.randf_range(0.0, 0.03)).normalized()
		out.append({"dir": sdir, "r": TerrainGen.ROCK_RADIUS * rng.randf_range(0.22, 0.45)})
	rec["scree"] = out


## The boulder rim collar (v7): 1-2 small rocks decorate a boulder's base.
## Decorative only -- the walk-over caps already cover the ring.
func _collar_for(rec: Dictionary, face_acc: int, boulder_i: int, dir: Vector3, radius: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = (face_acc * 257 + boulder_i * 13 + 5) % 9007199254740991
	var boulder_r: float = radius_m + radius * 0.28
	var n: int = rng.randi_range(1, 2)
	var out: Array = []
	for _k in range(n):
		var hint: Vector3 = Vector3(0, 1, 0) if absf(dir.dot(Vector3(0, 1, 0))) < 0.9 else Vector3(1, 0, 0)
		var axis: Vector3 = dir.cross(hint).normalized()
		var rdir: Vector3 = dir.rotated(axis, \
				(radius * 0.95) / maxf(boulder_r, 1.0) + rng.randf_range(0.0, 0.02)).normalized()
		out.append({"dir": rdir})
	rec["collar"] = out


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
func _chunk_rng(key: int, family: String, salted: bool = true) -> RandomNumberGenerator:
	var seed_bytes: PackedByteArray = SeedChain.derive_seed([world_seed], "props/%s/%d/%d" % [family, chunk_depth, key])
	var acc: int = 0
	for b in seed_bytes:
		acc = (acc * 131 + b) % 9007199254740991
	var rng := RandomNumberGenerator.new()
	# THE FIELD-2 SPLIT: decorative families (canopies, tufts) mix the
	# session salt so nature recombines between days; anchored culture
	# (the harvestable detail kinds) derives from the world seed alone so
	# depletion/respawn ownership survives a re-stream (salted=false).
	rng.seed = (acc + (_decor_salt if salted else 0)) % 9007199254740991
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
	_register_land_harvest(inst)
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
		KIND_CACTUS:
			_build_cactus(inst, node)
		KIND_FERN:
			_build_fern(inst, node)


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


## The grass carpet: one MultiMesh per chunk (a node per blade would flood
## the tree; the streamer paints the field the same way). The mesh is a
## shared 3-blade cluster; per-site variance rides the transform (scale/yaw).
func _build_grass_batch(blades: Array, node: Node3D) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _shared_grass_mesh()
	mm.instance_count = blades.size()
	for i in range(blades.size()):
		var b: Dictionary = blades[i]
		var dir: Vector3 = b["dir"]
		var up: Vector3 = dir
		var hint := Vector3(0, 1, 0)
		if absf(up.dot(hint)) > 0.999:
			hint = Vector3(1, 0, 0)
		var east: Vector3 = (hint - up * hint.dot(up)).normalized()
		var basis := Basis(east, up, east.cross(up)).rotated(up, float(b["yaw"])).scaled(Vector3.ONE * float(b["scale"]))
		mm.set_instance_transform(i, Transform3D(basis, dir * (radius_m + float(b["h"]))))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Grass"
	mmi.multimesh = mm
	mmi.material_override = _grass_material()
	node.add_child(mmi)


## The grass-blade cluster: one shared 3-blade mesh, vertex-graded base ->
## sun-tip (the streamer's tuft law, taller). One instance per grass site.
func _shared_grass_mesh() -> Mesh:
	var key: String = "grass_mesh"
	if _mesh_registry.has(key):
		return _mesh_registry[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base_col := Color(0.30, 0.42, 0.20)
	var tip_col := Color(0.62, 0.70, 0.34)
	for b in range(3):
		var ang: float = TAU * float(b) / 3.0
		var bx: float = cos(ang)
		var bz: float = sin(ang)
		var wide: float = 0.06
		var lean: float = 0.10
		st.set_color(base_col)
		st.add_vertex(Vector3(bx * wide, 0.0, bz * wide))
		st.set_color(base_col)
		st.add_vertex(Vector3(bx * -wide, 0.0, bz * -wide))
		st.set_color(tip_col)
		st.add_vertex(Vector3(bx * lean, 0.55, bz * lean))
	_mesh_registry[key] = st.commit()
	return _mesh_registry[key]


func _grass_material() -> StandardMaterial3D:
	var key: String = "grass_mat"
	if _mesh_registry.has(key):
		return _mesh_registry[key]
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh_registry[key] = mat
	return mat


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


func _build_cactus(inst: Dictionary, node: Node3D) -> void:
	var dir: Vector3 = inst["dir"]
	var base: Vector3 = dir * (radius_m + float(inst["h"]))
	var g := Node3D.new()
	g.name = "Cactus%d" % node.get_child_count()
	g.position = base
	var h: float = float(inst["h_c"])
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.26, 0.42, 0.24)
	mat.roughness = 1.0
	var trunk := MeshInstance3D.new()
	trunk.mesh = _shared_cyl(0.16, 0.19, h)
	trunk.position = Vector3(0.0, h * 0.5, 0.0)
	trunk.material_override = mat
	g.add_child(trunk)
	for a in range(int(inst.get("arms", 0))):
		var arm_h: float = h * (0.35 + 0.15 * float(a))
		var arm := MeshInstance3D.new()
		arm.mesh = _shared_cyl(0.10, 0.11, arm_h * 0.5)
		arm.material_override = mat
		var side: float = 1.0 if a % 2 == 0 else -1.0
		arm.position = Vector3(side * 0.16, arm_h, 0.0)
		arm.rotation.z = side * deg_to_rad(70.0)
		g.add_child(arm)
	node.add_child(g)


func _build_fern(inst: Dictionary, node: Node3D) -> void:
	var dir: Vector3 = inst["dir"]
	var base: Vector3 = dir * (radius_m + float(inst["h"]))
	var g := Node3D.new()
	g.name = "Fern%d" % node.get_child_count()
	g.position = base
	var frond_h: float = float(inst["frond_h"])
	var n: int = int(inst.get("fronds", 5))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.40, 0.20)
	mat.roughness = 1.0
	for k in range(n):
		var frond := MeshInstance3D.new()
		frond.mesh = _shared_cyl(0.015, 0.03, frond_h)
		frond.material_override = mat
		var fa: float = TAU * float(k) / float(n)
		frond.position = Vector3(cos(fa) * 0.05, frond_h * 0.42, sin(fa) * 0.05)
		frond.rotation = Vector3(sin(fa) * deg_to_rad(48.0), 0.0, -cos(fa) * deg_to_rad(48.0))
		g.add_child(frond)
	node.add_child(g)


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
	# The scree collar (v7): rubble on the rock's rim, two tints darker.
	for rubble in inst.get("scree", []):
		var sdir: Vector3 = rubble["dir"]
		var srmi := MeshInstance3D.new()
		srmi.name = "Scree%d" % node.get_child_count()
		srmi.mesh = _shared_sphere(float(rubble["r"]), 2.0)
		var srmat := StandardMaterial3D.new()
		srmat.albedo_color = _rock_color(sdir).darkened(0.25)
		srmat.roughness = 1.0
		srmi.material_override = srmat
		srmi.position = sdir * (radius_m + float(inst["h"]) + TerrainGen.ROCK_EMBED * 0.4)
		node.add_child(srmi)


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
	# The rim collar (v7): 1-2 small decorative rocks at the base.
	for rim in inst.get("collar", []):
		var rdir: Vector3 = rim["dir"]
		var crmi := MeshInstance3D.new()
		crmi.name = "Collar%d" % node.get_child_count()
		crmi.mesh = _shared_sphere(TerrainGen.ROCK_RADIUS, 2.0)
		crmi.material_override = bmat
		crmi.position = rdir * (radius_m + float(inst["h"]) + TerrainGen.ROCK_EMBED)
		node.add_child(crmi)


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
		# The vine hangs (v7): thin tapered threads chained down the canopy rim.
		var vine_n: int = int(inst.get("vine_n", 0))
		var canopy_rim: float = trunk_h + crown * canopy_h_mult * 0.35
		for kv in range(vine_n):
			var hang_len: float = crown * 0.9 + 0.3
			var hang := MeshInstance3D.new()
			hang.mesh = _shared_cyl(0.035, 0.012, hang_len)
			var hang_mat := StandardMaterial3D.new()
			hang_mat.albedo_color = Color(0.24, 0.40, 0.20)
			hang_mat.roughness = 1.0
			hang.material_override = hang_mat
			var vang: float = TAU * float(kv) / float(vine_n) + 0.4
			hang.position = Vector3(cos(vang) * crown * canopy_w_mult * 0.55, canopy_rim - hang_len * 0.5, sin(vang) * crown * canopy_w_mult * 0.55)
			tree.add_child(hang)
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
	# THE PER-PLANT COVERAGE LAW: every registered plant must paint at least one
	# strand, else a live harvest node would show nothing to gather. Strands are
	# labelled plant_k in order, each first claimed by the nearest still-unpainted
	# plant; once all three are covered the rest fall back to plain nearest.
	var covered: Array = [false, false, false]
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
			stalk.set_meta("plant_k", _claim_plant(plant_dirs, d_k, covered))
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
			spire.set_meta("plant_k", _claim_plant(plant_dirs, sd, covered))
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


## Register a land detail's harvestable node (the gather half of the one
## placement law, for the drawn mushrooms / ore / bushes). The zone comes
## from the provider (the main world's homeland -> the starter plains);
## a world with no zone law registers nothing (its flora is paint only).
## Main thread only (service registration is a side effect).
func _register_land_harvest(inst: Dictionary) -> void:
	var kind: int = int(inst.get("kind", -1))
	var item_id: String = ""
	var respawn: float = 60.0
	match kind:
		KIND_MUSHROOM:
			item_id = "res_mooncap"
			respawn = 240.0
		KIND_ORE:
			item_id = "res_iron_ore"
			respawn = 90.0
		KIND_BUSH:
			item_id = _bush_item(int(inst.get("bid", -1)))
			respawn = 45.0
		_:
			return
	var dir: Vector3 = inst["dir"]
	var zone_id: String = provider.zone_for_dir(dir) if provider.has_method("zone_for_dir") else ""
	if zone_id.is_empty():
		return
	var svc = _harvest_service()
	if svc == null or not svc.has_method("register_node"):
		return
	var site_id: String = str(inst.get("site_id", ""))
	if site_id.is_empty() or _land_registered.has(site_id):
		return
	_land_registered[site_id] = true
	svc.register_node(site_id, zone_id, item_id,
		dir * (radius_m + float(inst.get("h", 0.0))), 1, respawn)


## The bush's yield: the alpine meadow's herb, else iron ore (the streamer's
## own bush law -- the biome the site stands in decides).
func _bush_item(bid: int) -> String:
	if bid == TerrainGen.BiomeId.ALPINE_MEADOW:
		return "res_moonpetal"
	return "res_iron_ore"


## The plant a strand stands on (nearest of the bed's three), so per-plant
## depletion shears the paint honestly.
func _nearest_plant(plant_dirs: Array, d: Vector3) -> int:
	var owner: int = 0
	for pk in range(plant_dirs.size()):
		if (plant_dirs[pk] as Vector3).angle_to(d) < (plant_dirs[owner] as Vector3).angle_to(d):
			owner = pk
	return owner


## Assign a strand to the nearest plant, but guarantee every plant is painted
## at least once: an unpainted plant outranks a painted one so no registered
## harvest node is left with nothing to gather. `covered` is mutated in place.
func _claim_plant(plant_dirs: Array, d: Vector3, covered: Array) -> int:
	var owner: int = -1
	var best: float = INF
	for pk in range(plant_dirs.size()):
		if bool(covered[pk]):
			continue
		var a: float = (plant_dirs[pk] as Vector3).angle_to(d)
		if a < best:
			best = a
			owner = pk
	if owner < 0:
		return _nearest_plant(plant_dirs, d)
	covered[owner] = true
	return owner


## The stable per-face accumulator the bed seeds read (world-seed only, no
## day salt -- anchored culture must survive a re-stream). Reads the SAME
## face seed bytes the streamer's authored beds derived from, so the garden
## paint (strand placement + its plant_k shearing) is byte-identical to the
## pre-port look.
func _face_acc(face: int) -> int:
	var bytes: PackedByteArray = TerrainGen.face_seed_bytes(world_seed, face)
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
