## GlobeClipmap - the player-centred polar clipmap terrain renderer.
##
## Replaces globe_terrain_streamer's RENDERING (the icosa face-patch LOD
## with skirts + async derive + hot-reload graft) with a geometric ring
## ladder that draws the SAME ground law (TerrainGen.terrain_height +
## splat_skin). Addressing stays icosahedral; only the drawn mesh changes.
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

## Mirrors the streamer's TILE_LIFT (globe_world.STREAMER_TILE_LIFT): the
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


## `p_provider` (optional): the world's GroundProvider. Omitted -> the main
## world's TerrainProvider (so existing callers keep working unchanged).
func configure(p_radius: float, _p_target_edge: float, p_parent: Node3D, p_provider = null, p_draw_lift: float = TILE_LIFT) -> void:
	radius = p_radius
	parent = p_parent
	provider = p_provider if p_provider != null else TerrainProvider.new()
	draw_lift = p_draw_lift
	world_seed = provider.seed_bytes() if provider.has_method("seed_bytes") else TerrainGen.world_seed_bytes()
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
		_install_mesh(str(jobs[i]["kind"]), int(jobs[i]["level"]), derived[i])
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
	else:
		var upper: Array = _ring_row(level, 0)
		for ri in range(1, RSUB + 1):
			var lower: Array = _ring_row(level, ri)
			for ci in range(SEG):
				_emit_quad(st, upper, lower, ci)
			upper = lower
	return st.commit_to_arrays()


## Install a derived job's arrays as a mesh on the MAIN thread (the
## MeshInstance3D + material live in the scene tree). Shared by the
## parallel build and the incremental commit.
func _install_mesh(kind: String, level: int, arrays: Array) -> void:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if kind == "cap":
		if _cap_mesh == null:
			_cap_mesh = MeshInstance3D.new()
			_cap_mesh.name = "ClipmapCap"
			_root.add_child(_cap_mesh)
		_cap_mesh.mesh = mesh
		_cap_mesh.set_surface_override_material(0, _skin_material())
		return
	var mi: MeshInstance3D = _ring_meshes[level]
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = "ClipmapRing%d" % level
		_root.add_child(mi)
		_ring_meshes[level] = mi
	mi.mesh = mesh
	mi.set_surface_override_material(0, _skin_material())
	_ring_tris[level] = RSUB * SEG * 2
	_ring_built[level] = true
	patch_loaded.emit(level)


## -- public reads (streamer parity) ------------------------------------

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


func pending_derive() -> int:
	return _jobs.size()


## Streamer-compat shims: probes/tests drain by waiting for the streamer's
## async mesh lanes. The clipmap builds incrementally through _jobs, so the
## same drain-wait reads the job queue.
func _mesh_pending() -> int:
	return _jobs.size()


func _prop_pending() -> int:
	if _prop_layer == null:
		return 0
	return _prop_layer.pending_build()


## The built flora node count (probe/census surface).
func prop_count() -> int:
	if _prop_layer == null:
		return 0
	return _prop_layer.built_count()


func mesh_lane_stats() -> Dictionary:
	return {"pending": _jobs.size(), "lanes": 0}


func async_shutdown() -> void:
	_jobs.clear()


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
		"st": null, "grid": [], "row": [], "center": null, "rim": []}


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
	if st_v == null:
		st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		job["st"] = st
	else:
		st = st_v
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
	while ci < SEG:
		var cj: int = (ci + 1) % SEG
		_add_vert(st, center)
		_add_vert(st, rim[ci])
		_add_vert(st, rim[cj])
		ci += 1
		if ci < SEG and Time.get_ticks_msec() >= deadline:
			job["ci"] = ci
			return
	job["ri"] = 1
	job["ci"] = 0
	_commit_cap(st, done)


## A ring: build each grid row, then emit the quads joining it to the row
## above. Both loops are chunked against `deadline`; `phase` (row|quads)
## keeps a mid-row / mid-quad return resumable.
func _step_ring(job: Dictionary, done: Array, deadline: int) -> void:
	var level: int = int(job["level"])
	var st_v = job["st"]
	var st: SurfaceTool
	if st_v == null:
		st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		job["st"] = st
	else:
		st = st_v
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
	if ri >= 1:
		var upper: Array = grid[ri - 1]
		var lower: Array = grid[ri]
		var ci: int = int(job["qci"])
		while ci < SEG:
			_emit_quad(st, upper, lower, ci)
			ci += 1
			if ci < SEG and Time.get_ticks_msec() >= deadline:
				job["qci"] = ci
				return
		grid[ri - 1] = null  # row consumed (keep memory flat)
	job["ri"] = ri + 1
	job["qci"] = 0
	job["phase"] = "row"
	if int(job["ri"]) >= RSUB + 1:
		job["ri"] = RSUB + 1
		job["ci"] = 0
		_commit_ring(level, st, done)


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


func _commit_cap(st: SurfaceTool, done: Array) -> void:
	_install_mesh("cap", 0, st.commit_to_arrays())
	done.append("cap")


func _commit_ring(level: int, st: SurfaceTool, done: Array) -> void:
	_install_mesh("ring", level, st.commit_to_arrays())
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


## One fused ground_sample per vertex (TerrainGen memoizes it), feeding
## both the height and the colour -- no parallel clipmap caches. Called
## ONCE per distinct vertex; the quad pass reuses the result.
func _vertex_of(dir: Vector3) -> Dictionary:
	if not terrain_on:
		return {"p": dir * (radius + draw_lift), "d": dir, "splat": Color(0.42, 0.55, 0.30), "aux": Vector2(0.0, 1.0)}
	var ss: Dictionary = provider.surface_sample(dir)
	return {"p": dir * (radius + draw_lift + float(ss["height"])), "d": dir, "splat": ss["splat"], "aux": ss["aux"]}
