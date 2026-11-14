## GlobeClipmap - the player-centred polar clipmap terrain renderer.
##
## Replaces the retired globe_terrain_streamer's RENDERING (the icosa
## face-patch LOD with skirts + async derive + hot-reload graft) with a
## geometric ring ladder that draws the SAME ground law
## (TerrainGen.terrain_height + splat_skin). Addressing stays
## icosahedral; only the drawn mesh changes.
##
## WHY (see labs/prd-clipmap.md):
##  - The streamer's discrete per-face LOD draws the ground in ~165 m
##    cells at L7, so authored structures (which ride the analytic walk
##    law) float above the coarse drawn mesh and the LOD band flip makes
##    the gap SNAP on approach. The clipmap's innermost cells are ~8 m,
##    so the drawn ground under the player IS the law (measured delta
##    ~0.5 m) and the transition to coarse ground is smooth.
##  - Constant SEG cells across levels stitch the rings with NO skirts and
##    NO seams (level L's outer boundary shares directions with L+1's
##    inner boundary, and the centre cap shares ring 0's inner boundary).
##  - Constant triangle count regardless of visible range.
##
## THE COST LAW (measured, labs/prd-clipmap.md sec 2): a COLD ground-law
## sample is ~245 us (height) / ~681 us (height + splat color); a warm
## (sector-cache hit) sample is ~2 us. A 5.8k-vertex clipmap therefore
## costs ~3 s COLD, so the renderer:
##  L1 HYSTERESIS -- the lattice is snapped to a global arc grid and only
##     re-centres when the player crosses RE_CENTER_M from it, so a
##     rebuild is rare (not every frame, not every step).
##  L2 MEMOIZE -- height + color read through a per-quantized-direction
##     memo (the frame sector_cache); overlapping sectors hit at ~2 us.
##  L3 TIME-BUDGET -- a re-centre marks the rings dirty and the tick
##     advances an incremental builder at most BUDGET_MS per frame, so no
##     single frame pays the full rebuild.
##
## RefCounted helper (preloaded by the globe scene; no autoload), matching
## the streamer's shape so the swap is one line in globe_world.
extends RefCounted

const FacePatches = preload("res://core/frame/math/icosahedral_faces.gd")
const TerrainGen = preload("res://scenes/worlds/terrain_gen.gd")
const PropLayer = preload("res://core/world/prop_layer.gd")
const TerrainProvider = preload("res://scenes/worlds/terrain_provider.gd")

signal face_changed(old_face: int, new_face: int)
signal patch_loaded(face: int)
signal patch_unloaded(face: int)

## Mirrors globe_world.TILE_LIFT: the
## draw sits this far above the base shell so it never hides inside it.
const TILE_LIFT: float = 0.52

## THE RING LADDER. SEG angular cells and RSUB radial cells are CONSTANT
## across levels (the stitch law).
const SEG: int = 128          # angular cells per full circle
const RSUB: int = 8           # radial cells per level
const N_LEVELS: int = 5       # annuli 0..4 -> radii r0 .. r0*2^5
## Inner radius as a fraction of the planet radius. At R=20000 this is a
## ~156 m inner boundary, an ~8 m innermost cell, and level 4 reaches
## ~5 km (past the ~4 km camera far plane; the horizon sphere covers on).
const INNER_R_FRAC: float = 0.0078

## Re-centre hysteresis: the lattice re-snaps only when the player is this
## far (metres of ground arc) from its centre -- a rebuild is rare (L1).
const RE_CENTER_M: float = 150.0

## Per-frame rebuild budget (L3). The incremental builder advances until
## this many ms have elapsed, so a re-centre spreads over many frames.
const BUDGET_MS: float = 4.0

## Centre lattice quantization, metres of ground arc (L1). Sub-cell, so a
## snap moves the tessellation by a fraction of the innermost cell.
const CENTER_SNAP_M: float = 4.0

var radius: float = 20000.0
var world_seed: PackedByteArray = PackedByteArray()
var terrain_on: bool = true
var parent: Node3D = null

## The icosa face under the player (parity with the streamer's boot gate).
var current_face: int = -1

var _root: Node3D = null          # the clipmap holder under world_root
var _cap_mesh: MeshInstance3D = null
var _ring_meshes: Array = []      # int level -> MeshInstance3D
var _ring_tris: Array = []        # int level -> tri count
var _ring_built: Array = []       # int level -> bool (has a live mesh)
## The ground provider (labs/prd-clipmap.md 10): the clipmap reads ALL ground
## law through this seam, so the SAME renderer draws any globe. Default is the
## main world (TerrainProvider); a world passes its own into configure().
var provider = null
## The draw lift above the provider's ground (the tile-lift): the drawn mesh
## sits this far above the walk line to avoid z-fighting. A world whose
## authored geometry already rides the base shell passes 0 (so the draw and
## the structures share one walk line).
var draw_lift: float = TILE_LIFT

## Lattice state: the snapped centre direction (L1).
var _center_dir: Vector3 = Vector3.ZERO
var _last_player_dir: Vector3 = Vector3.ZERO
## Incremental build jobs, near-first: each {kind, level, cursor, st, grid}.
var _jobs: Array = []
var _building: bool = false
var _prop_layer = null            # PropLayer: the chunk-addressed flora
## Parallel cold-build book (build_all): per-job derived vertex arrays
## cross the mutex from the workers; the meshes are installed on the
## main thread (the streamer's derive/apply split, same law).
var _build_mutex := Mutex.new()
var _build_results: Dictionary = {}
var _build_next: int = 0
var _build_jobs: Array = []

## The per-quantized-direction ground sample (L2): ONE fused cache now
## serves both the height and the colour -- TerrainGen owns the memo, so
## the clipmap drops its old parallel _memo_h/_memo_col (Stage 4 of
## labs/prd-ground-sample.md). One ground_sample per vertex feeds both
## _memo_height and _memo_color.

const _skin_shader = preload("res://assets/shaders/terrain_splat.gdshader")
var _skin_mat: ShaderMaterial = null

## The standing-water sheet material (surface 1 on a ring/cap mesh) and the
## raised road-deck mesh. Both read vertex colours, so the tint/bridge laws
## the streamer authored actually show (its materials left
## `vertex_color_use_as_albedo` off, so its water/deck tints never rendered).
var _water_mat: StandardMaterial3D = null
var _deck_mesh: MeshInstance3D = null
var _sea: float = -1.0e9
## Minimum water depth (m) for a sheet to draw (the streamer's Hydro.BEACH_MIN).
const WATER_BEACH_MIN: float = 0.35
## The cartway ribbon half-width, radians of arc (~64 m at the canon radius).
const DECK_RIBBON_HALF: float = 0.0032
## The deck sits this far above the graded bed so planks read over the road
## tint the ground skin already lays down (and never z-fight it).
const DECK_LIFT: float = 0.15
const DECK_PLANK_COLOR := Color(0.44, 0.33, 0.22)


## `p_provider` (optional): the world's GroundProvider. Omitted -> the main
## world's TerrainProvider (so existing callers keep working unchanged).
func configure(p_radius: float, _p_target_edge: float, p_parent: Node3D, p_provider = null, p_draw_lift: float = TILE_LIFT) -> void:
	radius = p_radius
	parent = p_parent
	provider = p_provider if p_provider != null else TerrainProvider.new()
	draw_lift = p_draw_lift
	world_seed = provider.seed_bytes() if provider.has_method("seed_bytes") else TerrainGen.world_seed_bytes()
	_sea = provider.sea_level()
	_root = Node3D.new()
	_root.name = "ClipmapRoot"
	parent.add_child(_root)
	for lvl in range(N_LEVELS):
		_ring_meshes.append(null)
		_ring_tris.append(0)
		_ring_built.append(false)
	# THE PROP LAYER (labs/prd-clipmap.md 9): the ground MESH and the flora
	# are two systems. The clipmap draws the ground; this chunk-addressed
	# layer streams the trees/rocks/detail around the player, shared with
	# every renderer and every world through a GroundProvider.
	_prop_layer = PropLayer.new()
	_prop_layer.configure(provider, p_radius, _root)


func terrain_on_flag() -> bool:
	return terrain_on


## Snap/re-centre + budgeted build tick. Returns the streamer-shaped dict.
func update(player_pos: Vector3) -> Dictionary:
	var t0: int = Time.get_ticks_msec()
	var pdir: Vector3 = player_pos.normalized() if player_pos.length() > 0.001 else _spawn_dir()
	_last_player_dir = pdir

	var old_face: int = current_face
	current_face = FacePatches.face_for_direction(pdir)

	# Re-centre only past the hysteresis ring (L1).
	var recenter: bool = _center_dir == Vector3.ZERO
	if not recenter and _center_dir.angle_to(pdir) * radius >= RE_CENTER_M:
		recenter = true
	if recenter:
		_center_dir = _snap_dir(pdir)
		_queue_all()

	# Rebuild the deck whenever the lattice re-centres: its reach cull
	# follows the drawn ground, so a moving player keeps planks on real
	# terrain (the deck is cheap -- one quad per road node).
	if recenter and terrain_on:
		_install_deck()
	var built: Array = _advance_build(BUDGET_MS)

	# The flora streams on the SAME player position, independent of the mesh.
	if _prop_layer != null and terrain_on:
		_prop_layer.update(player_pos)

	if old_face != current_face:
		face_changed.emit(old_face, current_face)
	return {"face": current_face, "loaded": built, "unloaded": [], "active": active_faces(), "ms": Time.get_ticks_msec() - t0}


## Build the centre cap + all rings synchronously (boot + probes). Returns
## the wall clock ms. This is the COLD build (~3 s); the tick path is the
## budgeted one.
func build_all() -> int:
	var t0: int = Time.get_ticks_msec()
	if _center_dir == Vector3.ZERO:
		var seed_dir: Vector3 = _last_player_dir if _last_player_dir != Vector3.ZERO else _spawn_dir()
		_center_dir = _snap_dir(seed_dir)
	_jobs.clear()
	# S6 (labs/prd-clipmap.md): the cap + each ring is an INDEPENDENT
	# derive, so the cold build fans them onto workers and installs the
	# meshes on the main thread. The terrain law is thread-safe (the
	# sector caches are mutex-guarded; the streamer already derives
	# off-thread), so this is the same derive/apply split, not a new law.
	var jobs: Array = [{"kind": "cap", "level": 0}]
	for lvl in range(N_LEVELS):
		jobs.append({"kind": "ring", "level": lvl})
	var derived: Array = _derive_jobs(jobs)
	for i in range(jobs.size()):
		var pair: Array = derived[i]
		var water: Array = pair[1] if pair.size() > 1 else []
		_install_mesh(str(jobs[i]["kind"]), int(jobs[i]["level"]), pair[0], water)
	_install_deck()
	return Time.get_ticks_msec() - t0


## The parallel-build gate: the streamer's mesh-lane setting
## (synmergia/world/async_mesh, default on) so the boot-wall bench can
## A/B both laws in one build; a single-core host stays serial.
func _parallel_build_ok() -> bool:
	var gate: bool = true
	if ProjectSettings.has_setting("synmergia/world/async_mesh"):
		gate = bool(ProjectSettings.get_setting("synmergia/world/async_mesh"))
	return gate and OS.get_processor_count() > 1


## Derive every job's vertex arrays, in order. Parallel when the gate
## allows (one worker per job), else serial. Pure derives only -- no
## shared clipmap state is touched off the main thread.
## The worker count for the cold build: one per core, capped at the
## job count. Oversubscribing (one thread PER job) contends the terrain
## law's coarse per-cache mutexes and LOSES wall time -- measured, a
## bounded pool is the win.
func _build_workers() -> int:
	return clampi(OS.get_processor_count(), 1, 16)


func _derive_jobs(jobs: Array) -> Array:
	var out: Array = []
	out.resize(jobs.size())
	if _parallel_build_ok() and jobs.size() > 1:
		_build_mutex.lock()
		_build_results.clear()
		_build_next = 0
		_build_jobs = jobs
		_build_mutex.unlock()
		var workers: int = mini(_build_workers(), jobs.size())
		var threads: Array = []
		for w in range(workers):
			var t := Thread.new()
			threads.append(t)
			t.start(Callable(self, "_derive_worker"), Thread.PRIORITY_LOW)
		for t in threads:
			t.wait_to_finish()
		_build_mutex.lock()
		for i in range(jobs.size()):
			out[i] = _build_results.get(i)
		_build_results.clear()
		_build_jobs = []
		_build_mutex.unlock()
		return out
	for i in range(jobs.size()):
		out[i] = _derive_job_arrays(str(jobs[i]["kind"]), int(jobs[i]["level"]))
	return out


## One pool worker: pull the next job index, derive it, store the arrays.
## The counter + result book live behind _build_mutex.
func _derive_worker() -> void:
	while true:
		_build_mutex.lock()
		var idx: int = _build_next
		_build_next += 1
		var job: Dictionary = _build_jobs[idx] if idx < _build_jobs.size() else {}
		_build_mutex.unlock()
		if job.is_empty():
			return
		var arr: Array = _derive_job_arrays(str(job["kind"]), int(job["level"]))
		_build_mutex.lock()
		_build_results[idx] = arr
		_build_mutex.unlock()


## The full geometry of ONE job (cap or ring), derived with a local
## SurfaceTool so it can run on a worker. The incremental tick path
## builds the same geometry row-by-row instead (the time budget).
func _derive_job_arrays(kind: String, level: int) -> Array:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stw := SurfaceTool.new()
	stw.begin(Mesh.PRIMITIVE_TRIANGLES)
	if kind == "cap":
		var r0: float = radius * INNER_R_FRAC
		var center: Dictionary = _vertex_of(_center_dir)
		var rim: Array = []
		for k in range(SEG):
			rim.append(_vertex_of(_ring_dir(TAU * float(k) / float(SEG), r0)))
		for ci in range(SEG):
			var cj: int = (ci + 1) % SEG
			_add_vert(st, center)
			_add_vert(st, rim[ci])
			_add_vert(st, rim[cj])
			_add_water(stw, center, rim[ci], rim[cj])
	else:
		var upper: Array = _ring_row(level, 0)
		for ri in range(1, RSUB + 1):
			var lower: Array = _ring_row(level, ri)
			for ci in range(SEG):
				_emit_quad(st, upper, lower, ci)
				var cj: int = (ci + 1) % SEG
				_add_water(stw, upper[ci], upper[cj], lower[cj])
				_add_water(stw, upper[ci], lower[cj], lower[ci])
			upper = lower
	return [st.commit_to_arrays(), stw.commit_to_arrays()]


## Install a derived job's arrays as a mesh on the MAIN thread (the
## MeshInstance3D + material live in the scene tree). Shared by the
## parallel build and the incremental commit.
func _install_mesh(kind: String, level: int, arrays: Array, water_arrays: Array = []) -> void:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# Standing water rides a SECOND surface (the streamer's surface 2), drawn
	# only where the tile is fully wet, so the mesh is empty on dry rings.
	var has_water: bool = false
	if water_arrays != null and water_arrays.size() > Mesh.ARRAY_VERTEX:
		var wv = water_arrays[Mesh.ARRAY_VERTEX]
		has_water = wv != null and wv.size() > 0
	if has_water:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, water_arrays)
	if kind == "cap":
		if _cap_mesh == null:
			_cap_mesh = MeshInstance3D.new()
			_cap_mesh.name = "ClipmapCap"
			_root.add_child(_cap_mesh)
		_cap_mesh.mesh = mesh
		_cap_mesh.set_surface_override_material(0, _skin_material())
		if has_water:
			_cap_mesh.set_surface_override_material(1, _water_material())
		return
	var mi: MeshInstance3D = _ring_meshes[level]
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = "ClipmapRing%d" % level
		_root.add_child(mi)
		_ring_meshes[level] = mi
	mi.mesh = mesh
	mi.set_surface_override_material(0, _skin_material())
	if has_water:
		mi.set_surface_override_material(1, _water_material())
	_ring_tris[level] = RSUB * SEG * 2
	_ring_built[level] = true
	patch_loaded.emit(level)


## -- public reads (the drawn terrain's seams) --------------------------

## The WALK LAW: unchanged (law + small-rock caps). Physics + props ride
## this, never the mesh.
func walk_surface_h(dir: Vector3) -> float:
	return provider.walk_height(dir.normalized()) if terrain_on else 0.0


func terrain_h(dir: Vector3) -> float:
	return provider.ground_height(dir.normalized()) if terrain_on else 0.0


func is_loaded(_face: int) -> bool:
	return _ring_built.size() > 0 and _ring_built[0]


func active_faces() -> Array:
	return [current_face] if current_face >= 0 else []


func patch_count() -> int:
	var n: int = 0
	for b in _ring_built:
		if b:
			n += 1
	return n


func triangle_count() -> int:
	var total: int = 0
	for t in _ring_tris:
		total += int(t)
	return total


func visible_patch_count() -> int:
	return patch_count()


func pending_jobs() -> int:
	return _jobs.size()


## Drain-wait seam: probes/tests wait for the async build queue to empty
## by polling this (the clipmap builds incrementally through _jobs).
func mesh_pending() -> int:
	return _jobs.size()


func prop_pending() -> int:
	if _prop_layer == null:
		return 0
	return _prop_layer.pending_build()


## The built flora node count (probe/census surface).
func prop_count() -> int:
	if _prop_layer == null:
		return 0
	return _prop_layer.built_count()


## The standing-water surface triangle count across the cap + rings (the
## streamer's `_patch_water_tris` analogue). Reads the committed meshes.
func water_triangle_count() -> int:
	var n: int = 0
	for mi in _all_ground_meshes():
		if mi != null and mi.mesh != null and mi.mesh.get_surface_count() > 1:
			n += int(mi.mesh.surface_get_arrays(1)[Mesh.ARRAY_VERTEX].size()) / 3
	return n


## The raised road-deck quad count (0 when the world has no road).
func deck_quad_count() -> int:
	if _deck_mesh == null or not is_instance_valid(_deck_mesh) or _deck_mesh.mesh == null:
		return 0
	return int(_deck_mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()) / 6


## Every ground mesh the clipmap owns (cap + live rings), for reads.
func _all_ground_meshes() -> Array:
	var out: Array = []
	if _cap_mesh != null:
		out.append(_cap_mesh)
	for mi in _ring_meshes:
		if mi != null:
			out.append(mi)
	return out


## Async build-lane census (probe/bench surface).
func lane_stats() -> Dictionary:
	return {"pending": _jobs.size(), "lanes": 0}


## The drawn ground meshes (cap + live rings) and the flora layer -- the
## public seam receipts read instead of the retired streamer's internals.
func ground_meshes() -> Array:
	return _all_ground_meshes()


func prop_layer():
	return _prop_layer


## Predictive prefetch passthrough: the world arms it once the local
## player's identity is known, so the flora layer warms the chunk the
## player is heading into (the canonical read side).
func enable_prop_prefetch(viewer_id: String) -> void:
	if _prop_layer != null:
		_prop_layer.enable_prefetch(viewer_id)


func prop_prefetch_current_chunk() -> int:
	if _prop_layer == null:
		return -1
	return _prop_layer.current_chunk_key()


func async_shutdown() -> void:
	_jobs.clear()
	if _deck_mesh != null and is_instance_valid(_deck_mesh):
		_deck_mesh.queue_free()
	_deck_mesh = null


func lod_levels() -> Dictionary:
	var d: Dictionary = {}
	for lvl in range(N_LEVELS):
		d[lvl] = _ring_tris[lvl]
	return d


## -- internals ---------------------------------------------------------

func _skin_material() -> ShaderMaterial:
	if _skin_mat != null:
		return _skin_mat
	_skin_mat = ShaderMaterial.new()
	_skin_mat.shader = _skin_shader
	return _skin_mat


## The world's authored spawn direction (renderer boot fallback), read
## through the provider so a world declares its own seat.
func _spawn_dir() -> Vector3:
	return provider.spawn_dir()


## Snap the centre direction to a global arc lattice (L1). Tangential
## offsets are measured against a FIXED world frame (spawn east/north), so
## the lattice is global -- a player-relative lattice would slide.
func _snap_dir(pdir: Vector3) -> Vector3:
	var ref: Vector3 = _spawn_dir()
	var ref_east: Vector3 = Vector3(0, 1, 0).cross(ref)
	if ref_east.length() < 0.001:
		ref_east = Vector3(0, 0, 1).cross(ref)
	ref_east = ref_east.normalized()
	var ref_north: Vector3 = ref.cross(ref_east).normalized()
	var arc: float = maxf(CENTER_SNAP_M / maxf(radius, 1.0), 0.0000001)
	var uq: float = roundf(pdir.dot(ref_east) / arc) * arc
	var vq: float = roundf(pdir.dot(ref_north) / arc) * arc
	return (ref + ref_east * uq + ref_north * vq).normalized()


## Queue every ring dirty, near-first (the centre cap first).
func _queue_all() -> void:
	_jobs.clear()
	_jobs.append(_new_job("cap", 0))
	for lvl in range(N_LEVELS):
		_jobs.append(_new_job("ring", lvl))


func _new_job(kind: String, level: int) -> Dictionary:
	return {"kind": kind, "level": level, "ri": 0, "ci": 0, "qci": 0, "phase": "row",
		"st": null, "stw": null, "wtris": 0, "grid": [], "row": [], "center": null, "rim": []}


## Advance the incremental builder until `budget_ms` elapse or the queue
## drains. Each call completes at most one grid row of work between time
## checks, so a cold frame stays bounded.
func _advance_build(budget_ms: float) -> Array:
	var done: Array = []
	# L3: the budget is honored INSIDE a row too -- a cold ring row is
	# 128 derives (~50 ms), so the row/rim loops check this deadline per
	# cell and resume next tick. Without it a re-centre tick spiked to a
	# whole row (probe_clipmap G5).
	var deadline: int = Time.get_ticks_msec() + int(maxf(1.0, budget_ms))
	while _jobs.size() > 0:
		var job: Dictionary = _jobs[0]
		_step_job(job, done, deadline)
		if int(job["ri"]) >= _job_rows(job) and int(job["ci"]) == 0:
			_jobs.pop_front()
		if Time.get_ticks_msec() >= deadline:
			break
	return done


func _job_rows(job: Dictionary) -> int:
	if job["kind"] == "cap":
		return 1
	return RSUB + 1


## One unit of job progress: the cap advances one angular cell per call;
## a ring advances one grid row per call (its verts are emitted when the
## row above arrives).
func _step_job(job: Dictionary, done: Array, deadline: int) -> void:
	if job["kind"] == "cap":
		_step_cap(job, done, deadline)
	else:
		_step_ring(job, done, deadline)


## The cap: centre vertex, then the rim ring, then the fan cells -- each
## phase chunked against `deadline` (L3: the 4 ms budget is honored INSIDE
## a row; a cold 128-derive phase must not land whole). `phase` tracks
## where we are so a mid-phase return resumes correctly.
func _step_cap(job: Dictionary, done: Array, deadline: int) -> void:
	var st_v = job["st"]
	var st: SurfaceTool
	var stw_v = job["stw"]
	var stw: SurfaceTool
	if st_v == null:
		st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		job["st"] = st
		stw = SurfaceTool.new()
		stw.begin(Mesh.PRIMITIVE_TRIANGLES)
		job["stw"] = stw
	else:
		st = st_v
		stw = stw_v
	var phase: String = str(job["phase"])
	if job["center"] == null:
		job["center"] = _vertex_of(_center_dir)
		job["phase"] = "rim"
		phase = "rim"
	if phase == "rim":
		var r0: float = radius * INNER_R_FRAC
		var rim: Array = job["rim"]
		var k: int = rim.size()
		while k < SEG:
			rim.append(_vertex_of(_ring_dir(TAU * float(k) / float(SEG), r0)))
			k += 1
			if k < SEG and Time.get_ticks_msec() >= deadline:
				job["rim"] = rim
				return
		job["phase"] = "cells"
		phase = "cells"
	var ci: int = int(job["ci"])
	var center: Dictionary = job["center"]
	var rim: Array = job["rim"]
	var wtris: int = int(job.get("wtris", 0))
	while ci < SEG:
		var cj: int = (ci + 1) % SEG
		_add_vert(st, center)
		_add_vert(st, rim[ci])
		_add_vert(st, rim[cj])
		if _add_water(stw, center, rim[ci], rim[cj]):
			wtris += 1
		ci += 1
		if ci < SEG and Time.get_ticks_msec() >= deadline:
			job["ci"] = ci
			job["wtris"] = wtris
			return
	job["ri"] = 1
	job["ci"] = 0
	job["wtris"] = wtris
	_commit_cap(st, stw, done)


## A ring: build each grid row, then emit the quads joining it to the row
## above. Both loops are chunked against `deadline`; `phase` (row|quads)
## keeps a mid-row / mid-quad return resumable.
func _step_ring(job: Dictionary, done: Array, deadline: int) -> void:
	var level: int = int(job["level"])
	var st_v = job["st"]
	var st: SurfaceTool
	var stw_v = job["stw"]
	var stw: SurfaceTool
	if st_v == null:
		st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		job["st"] = st
		stw = SurfaceTool.new()
		stw.begin(Mesh.PRIMITIVE_TRIANGLES)
		job["stw"] = stw
	else:
		st = st_v
		stw = stw_v
	var grid: Array = job["grid"]
	var ri: int = int(job["ri"])
	var phase: String = str(job["phase"])
	if phase == "row":
		var row: Array = job["row"]
		var c: int = row.size()
		while c < SEG:
			row.append(_vertex_of(_ring_dir(TAU * float(c) / float(SEG), _row_radius(level, ri))))
			c += 1
			if c < SEG and Time.get_ticks_msec() >= deadline:
				job["row"] = row
				return
		grid.append(row)
		job["row"] = []
		job["phase"] = "quads"
		phase = "quads"
	var wtris: int = int(job.get("wtris", 0))
	if ri >= 1:
		var upper: Array = grid[ri - 1]
		var lower: Array = grid[ri]
		var ci: int = int(job["qci"])
		while ci < SEG:
			_emit_quad(st, upper, lower, ci)
			var cj: int = (ci + 1) % SEG
			if _add_water(stw, upper[ci], upper[cj], lower[cj]) or _add_water(stw, upper[ci], lower[cj], lower[ci]):
				wtris += 1
			ci += 1
			if ci < SEG and Time.get_ticks_msec() >= deadline:
				job["qci"] = ci
				job["wtris"] = wtris
				return
		grid[ri - 1] = null  # row consumed (keep memory flat)
	job["ri"] = ri + 1
	job["qci"] = 0
	job["phase"] = "row"
	job["wtris"] = wtris
	if int(job["ri"]) >= RSUB + 1:
		job["ri"] = RSUB + 1
		job["ci"] = 0
		_commit_ring(level, st, stw, done)


func _row_radius(level: int, ri: int) -> float:
	var r0: float = radius * INNER_R_FRAC
	var r_in: float = r0 * pow(2.0, float(level))
	var r_out: float = r_in * 2.0
	return r_in + (r_out - r_in) * float(ri) / float(RSUB)


func _ring_row(level: int, ri: int) -> Array:
	var rr: float = _row_radius(level, ri)
	var row: Array = []
	for ci in range(SEG):
		row.append(_vertex_of(_ring_dir(TAU * float(ci) / float(SEG), rr)))
	return row


## The one quad emitter (ring rows ri-1/ri, angular cell ci), shared by
## the incremental tick path and the parallel cold build so the two can
## never drift.
func _emit_quad(st: SurfaceTool, upper: Array, lower: Array, ci: int) -> void:
	var cj: int = (ci + 1) % SEG
	var a: Dictionary = upper[ci]
	var b: Dictionary = upper[cj]
	var c: Dictionary = lower[cj]
	var d: Dictionary = lower[ci]
	_add_vert(st, a)
	_add_vert(st, b)
	_add_vert(st, c)
	_add_vert(st, a)
	_add_vert(st, c)
	_add_vert(st, d)


func _commit_cap(st: SurfaceTool, stw: SurfaceTool, done: Array) -> void:
	_install_mesh("cap", 0, st.commit_to_arrays(), stw.commit_to_arrays())
	done.append("cap")


func _commit_ring(level: int, st: SurfaceTool, stw: SurfaceTool, done: Array) -> void:
	_install_mesh("ring", level, st.commit_to_arrays(), stw.commit_to_arrays())
	done.append(level)


## The planet-relative direction for angular cell `ang` at radius `rr`,
## in the lattice frame (east/north of the snapped centre).
func _ring_dir(ang: float, rr: float) -> Vector3:
	var up: Vector3 = _center_dir
	var east: Vector3 = Vector3(0, 1, 0).cross(up)
	if east.length() < 0.001:
		east = Vector3(0, 0, 1).cross(up)
	east = east.normalized()
	var north: Vector3 = up.cross(east).normalized()
	return (up * radius + east * (cos(ang) * rr) + north * (sin(ang) * rr)).normalized()


## Emit a prebuilt vertex (pos + skin already resolved by _vertex_of).
## The ring quad pass emits each shared vertex up to 6x, so resolving the
## full ground sample + splat ONCE per distinct vertex (not per emission)
## is the S8 slow-system win: the splat is the priciest limb and it is
## identical across a vertex's emissions.
func _add_vert(st: SurfaceTool, v: Dictionary) -> void:
	var p: Vector3 = v["p"]
	st.set_normal(v["d"])
	st.set_color(v["splat"])
	st.set_uv2(v["aux"])
	st.set_uv(Vector2(fposmod(p.x * 0.0015, 1.0), fposmod(p.z * 0.0015, 1.0)))
	st.add_vertex(p)


## Emit ONE standing-water triangle (a,b,c are ground vertices carrying "ws"
## + "gh"). Emits only when ALL three corners are wet (the streamer's law);
## returns true when a triangle landed.
func _add_water(st_w: SurfaceTool, a: Dictionary, b: Dictionary, c: Dictionary) -> bool:
	if not terrain_on:
		return false
	for v in [a, b, c]:
		var ws: float = float(v.get("ws", -1.0e9))
		if ws <= -1.0e8 or ws <= float(v["gh"]) + WATER_BEACH_MIN:
			return false
	var t_h: float = (float(a["ws"]) + float(b["ws"]) + float(c["ws"])) / 3.0
	# Standing water is water ABOVE the sea line (rivers, high ponds): the
	# sea itself is the globe's WaterShell sphere, so a sheet at/below the
	# sea line would double-draw the ocean (the streamer had this flaw; the
	# opaque shell merely hid it).
	if t_h <= _sea + 0.05:
		return false
	var d_mid: Vector3 = ((a["d"] + b["d"] + c["d"]) / 3.0).normalized()
	var g_mid: float = (float(a["gh"]) + float(b["gh"]) + float(c["gh"])) / 3.0
	var tint: Color = provider.water_tint(d_mid, t_h - g_mid)
	for v in [a, b, c]:
		st_w.set_normal(d_mid)
		st_w.set_color(tint)
		st_w.add_vertex(_water_vertex(v["d"], t_h))
	return true


## One fused ground_sample per vertex (TerrainGen memoizes it), feeding
## both the height and the colour -- no parallel clipmap caches. Called
## ONCE per distinct vertex; the quad pass reuses the result.
func _vertex_of(dir: Vector3) -> Dictionary:
	if not terrain_on:
		return {"p": dir * (radius + draw_lift), "d": dir, "splat": Color(0.42, 0.55, 0.30), "aux": Vector2(0.0, 1.0)}
	var ss: Dictionary = provider.surface_sample(dir)
	var gh: float = float(ss["height"])
	return {"p": dir * (radius + draw_lift + gh), "d": dir, "splat": ss["splat"], "aux": ss["aux"],
		"gh": gh, "ws": _water_surface_at(dir)}


## -- standing water (the streamer's surface 2) -------------------------
##
## The clipmap draws the ground mesh; standing water ABOVE the sea line
## (rivers, high ponds) is a SECOND surface of tile quads at the water
## table, drawn only where a tile is FULLY wet (its three corners each
## clear the ground by BEACH_MIN). The streamer owned this law; the clipmap
## now owns it too, so retiring the streamer loses no drawn water. The sea
## itself is NOT drawn here -- the globe's WaterShell sphere floods it.

func _water_material() -> StandardMaterial3D:
	if _water_mat != null:
		return _water_mat
	_water_mat = StandardMaterial3D.new()
	# The streamer left vertex colours OFF, so its water/deck tints never
	# rendered; the clipmap turns them ON so the tint law actually shows.
	_water_mat.vertex_color_use_as_albedo = true
	_water_mat.roughness = 0.12
	_water_mat.metallic = 0.0
	return _water_mat


## The standing-water surface height at `dir`, or -1e9 if none. Reads the
## provider's water table; a world with no standing water reports the sea
## line (so a sheet never fires above it).
func _water_surface_at(dir: Vector3) -> float:
	return provider.water_surface(dir)


## The world-space vertex for a tile corner at radius (radius + draw_lift +
## surface height). `h` is the surface lift above the base shell (NOT above
## the ground) -- the sheet rides the water table, the ground rides its own.
func _water_vertex(dir: Vector3, surf_h: float) -> Vector3:
	return dir * (radius + draw_lift + surf_h)


## Build the standing-water surface for the ring/cap triangle (three
## directions). Returns { "arrays": PackedVector3Array-committed or null,
## "tris": int }. The three corners are the tile's own dirs; the sheet is a
## flat-ish lens at the average table height, tinted by the tile's climate.
func _water_arrays_for(tri_dirs: Array, tri_ground: Array) -> Array:
	if not terrain_on:
		return [null, 0]
	var surf: Array = []
	var all_wet: bool = true
	for i in range(3):
		var s: float = _water_surface_at(tri_dirs[i])
		surf.append(s)
		if s <= -1.0e8 or s <= float(tri_ground[i]) + WATER_BEACH_MIN:
			all_wet = false
	if not all_wet:
		return [null, 0]
	var t_h: float = (float(surf[0]) + float(surf[1]) + float(surf[2])) / 3.0
	if t_h <= _sea + 0.05:
		return [null, 0]
	var d_mid: Vector3 = ((tri_dirs[0] + tri_dirs[1] + tri_dirs[2]) / 3.0).normalized()
	var g_mid: float = (float(tri_ground[0]) + float(tri_ground[1]) + float(tri_ground[2])) / 3.0
	var tint: Color = provider.water_tint(d_mid, t_h - g_mid)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: Vector3 = d_mid
	for i in range(3):
		st.set_normal(n)
		st.set_color(tint)
		st.add_vertex(_water_vertex(tri_dirs[i], t_h))
	return [st.commit_to_arrays(), 1]


## -- raised road deck (the streamer's surface 3) -----------------------

func _deck_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.95
	return m


## Build the raised cartway ribbon: a plank quad per road node, sitting at
## the bed/deck height the walk law already answers (so feet and planks
## agree). The deck is world-space (not tile-addressed), so it is rebuilt
## whole on each cold build. Returns an ArrayMesh or null.
func _build_deck() -> MeshInstance3D:
	if not terrain_on:
		return null
	var spec = provider.road_spec()
	if spec == null or not ("path" in spec):
		return null
	var path: PackedVector3Array = spec.path
	var beds: PackedFloat32Array = spec.beds
	var bridges: PackedFloat32Array = spec.bridges
	if path.size() < 2:
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quads: int = 0
	# The clipmap draws fine ground only out to the outermost ring; a deck
	# segment past that would float over the coarse horizon. Cull to the
	# covered reach (the streamer's per-face reach cull, made radial).
	var reach: float = INNER_R_FRAC * pow(2.0, float(N_LEVELS)) + 0.02
	var c: Vector3 = _center_dir if _center_dir != Vector3.ZERO else _spawn_dir()
	for i in range(path.size() - 1):
		var p0: Vector3 = path[i]
		var p1: Vector3 = path[i + 1]
		if p0.angle_to(c) > reach and p1.angle_to(c) > reach:
			continue
		var h0: float = beds[i]
		var h1: float = beds[i + 1]
		var is_bridge: bool = bridges[i] > 0.4 or bridges[i + 1] > 0.4
		var seg: Vector3 = p0.cross(p1).normalized()
		if seg.length() < 0.001:
			continue
		var half: float = DECK_RIBBON_HALF
		var a0: Vector3 = p0.rotated(seg, half).normalized()
		var b0: Vector3 = p0.rotated(seg, -half).normalized()
		var a1: Vector3 = p1.rotated(seg, half).normalized()
		var b1: Vector3 = p1.rotated(seg, -half).normalized()
		var va0: Vector3 = a0 * (radius + draw_lift + h0 + DECK_LIFT)
		var vb0: Vector3 = b0 * (radius + draw_lift + h0 + DECK_LIFT)
		var va1: Vector3 = a1 * (radius + draw_lift + h1 + DECK_LIFT)
		var vb1: Vector3 = b1 * (radius + draw_lift + h1 + DECK_LIFT)
		var mid: Vector3 = ((a0 + b0 + a1 + b1) * 0.25).normalized()
		var col: Color = DECK_PLANK_COLOR
		if is_bridge:
			col = col.lightened(0.25)
		var pts: Array = [va0, vb0, va1, vb0, vb1, va1]
		for p in pts:
			st.set_normal(mid)
			st.set_color(col)
			st.add_vertex(p)
		quads += 1
	if quads == 0:
		return null
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays())
	var mi := MeshInstance3D.new()
	mi.name = "ClipmapDeck"
	mi.mesh = mesh
	mi.set_surface_override_material(0, _deck_material())
	return mi


## Rebuild the world-space deck under the clipmap root (called after a cold
## build). Idempotent: replaces the previous deck node.
func _install_deck() -> void:
	if _deck_mesh != null and is_instance_valid(_deck_mesh):
		_deck_mesh.queue_free()
	_deck_mesh = null
	var mi: MeshInstance3D = _build_deck()
	if mi != null and _root != null:
		_root.add_child(mi)
		_deck_mesh = mi
