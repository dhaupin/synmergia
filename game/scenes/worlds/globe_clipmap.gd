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
const SectorCache = preload("res://core/frame/kv/sector_cache.gd")

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

## Per-vertex memo bound (L2).
const MEMO_MAX: int = 262144

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

## Lattice state: the snapped centre direction (L1).
var _center_dir: Vector3 = Vector3.ZERO
var _last_player_dir: Vector3 = Vector3.ZERO
## Incremental build jobs, near-first: each {kind, level, cursor, st, grid}.
var _jobs: Array = []
var _building: bool = false

## The per-quantized-direction memo (L2).
var _memo_h = SectorCache.new(MEMO_MAX)
var _memo_col = SectorCache.new(MEMO_MAX)

const _skin_shader = preload("res://assets/shaders/terrain_splat.gdshader")
var _skin_mat: ShaderMaterial = null


func configure(p_radius: float, _p_target_edge: float, p_parent: Node3D) -> void:
	radius = p_radius
	parent = p_parent
	world_seed = TerrainGen.world_seed_bytes()
	_root = Node3D.new()
	_root.name = "ClipmapRoot"
	parent.add_child(_root)
	for lvl in range(N_LEVELS):
		_ring_meshes.append(null)
		_ring_tris.append(0)
		_ring_built.append(false)


func terrain_on_flag() -> bool:
	return terrain_on


## Snap/re-centre + budgeted build tick. Returns the streamer-shaped dict.
func update(player_pos: Vector3) -> Dictionary:
	var t0: int = Time.get_ticks_msec()
	var pdir: Vector3 = player_pos.normalized() if player_pos.length() > 0.001 else TerrainGen.SPAWN_CENTER
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

	if old_face != current_face:
		face_changed.emit(old_face, current_face)
	return {"face": current_face, "loaded": built, "unloaded": [], "active": active_faces(), "ms": Time.get_ticks_msec() - t0}


## Build the centre cap + all rings synchronously (boot + probes). Returns
## the wall clock ms. This is the COLD build (~3 s); the tick path is the
## budgeted one.
func build_all() -> int:
	var t0: int = Time.get_ticks_msec()
	if _center_dir == Vector3.ZERO:
		var seed_dir: Vector3 = _last_player_dir if _last_player_dir != Vector3.ZERO else TerrainGen.SPAWN_CENTER
		_center_dir = _snap_dir(seed_dir)
	_queue_all()
	while _jobs.size() > 0:
		_advance_build(1000000.0)
	return Time.get_ticks_msec() - t0


## -- public reads (streamer parity) ------------------------------------

## The WALK LAW: unchanged (law + small-rock caps). Physics + props ride
## this, never the mesh.
func walk_surface_h(dir: Vector3) -> float:
	var d: Vector3 = dir.normalized()
	var base: float = TerrainGen.terrain_height(d, world_seed) if terrain_on else 0.0
	var face: int = FacePatches.face_for_direction(d)
	return base + TerrainGen.rock_top_height(d, world_seed, face, radius)


func terrain_h(dir: Vector3) -> float:
	return TerrainGen.terrain_height(dir.normalized(), world_seed) if terrain_on else 0.0


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
	return 0


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


## Snap the centre direction to a global arc lattice (L1). Tangential
## offsets are measured against a FIXED world frame (spawn east/north), so
## the lattice is global -- a player-relative lattice would slide.
func _snap_dir(pdir: Vector3) -> Vector3:
	var ref: Vector3 = TerrainGen.SPAWN_CENTER
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
	_jobs.append({"kind": "cap", "level": 0, "ri": 0, "ci": 0, "st": null, "grid": null})
	for lvl in range(N_LEVELS):
		_jobs.append({"kind": "ring", "level": lvl, "ri": 0, "ci": 0, "st": null, "grid": null})


## Advance the incremental builder until `budget_ms` elapse or the queue
## drains. Each call completes at most one grid row of work between time
## checks, so a cold frame stays bounded.
func _advance_build(budget_ms: float) -> Array:
	var done: Array = []
	var start: int = Time.get_ticks_msec()
	while _jobs.size() > 0:
		var job: Dictionary = _jobs[0]
		_step_job(job, done)
		if int(job["ri"]) >= _job_rows(job) and int(job["ci"]) == 0:
			_jobs.pop_front()
		if float(Time.get_ticks_msec() - start) >= budget_ms:
			break
	return done


func _job_rows(job: Dictionary) -> int:
	if job["kind"] == "cap":
		return 1
	return RSUB + 1


## One unit of job progress: the cap advances one angular cell per call;
## a ring advances one grid row per call (its verts are emitted when the
## row above arrives).
func _step_job(job: Dictionary, done: Array) -> void:
	if job["kind"] == "cap":
		_step_cap(job, done)
	else:
		_step_ring(job, done)


func _step_cap(job: Dictionary, done: Array) -> void:
	var r0: float = radius * INNER_R_FRAC
	var st_v = job["st"]
	var st: SurfaceTool
	if st_v == null:
		st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		job["st"] = st
	else:
		st = st_v
	var ci: int = int(job["ci"])
	var center_dir: Vector3 = _center_dir
	var center_p: Vector3 = center_dir * (radius + TILE_LIFT + _memo_height(center_dir))
	var cj: int = (ci + 1) % SEG
	var da: Vector3 = _ring_dir(TAU * float(ci) / float(SEG), r0)
	var db: Vector3 = _ring_dir(TAU * float(cj) / float(SEG), r0)
	var pa: Vector3 = da * (radius + TILE_LIFT + _memo_height(da))
	var pb: Vector3 = db * (radius + TILE_LIFT + _memo_height(db))
	_add_vert(st, center_p, center_dir)
	_add_vert(st, pa, da)
	_add_vert(st, pb, db)
	job["ci"] = ci + 1
	if int(job["ci"]) >= SEG:
		job["ri"] = 1
		job["ci"] = 0
		_commit_cap(st, done)


func _step_ring(job: Dictionary, done: Array) -> void:
	var level: int = int(job["level"])
	var st_v = job["st"]
	var st: SurfaceTool
	if st_v == null:
		st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		job["st"] = st
	else:
		st = st_v
	var grid_v = job["grid"]
	var grid: Array
	if grid_v == null:
		grid = []
		job["grid"] = grid
	else:
		grid = grid_v
	var ri: int = int(job["ri"])
	# Emit row ri's vertices (needed by the quad pass for rows ri-1..ri).
	grid.append(_ring_row(level, ri))
	# Quads between row ri-1 and row ri.
	if ri >= 1:
		var upper: Array = grid[ri - 1]
		var lower: Array = grid[ri]
		for ci in range(SEG):
			var cj: int = (ci + 1) % SEG
			var a: Dictionary = upper[ci]
			var b: Dictionary = upper[cj]
			var c: Dictionary = lower[cj]
			var d: Dictionary = lower[ci]
			_add_vert(st, a["p"], a["d"])
			_add_vert(st, b["p"], b["d"])
			_add_vert(st, c["p"], c["d"])
			_add_vert(st, a["p"], a["d"])
			_add_vert(st, c["p"], c["d"])
			_add_vert(st, d["p"], d["d"])
		grid[ri - 1] = null  # row consumed (keep memory flat)
	job["ri"] = ri + 1
	if int(job["ri"]) >= RSUB + 1:
		job["ri"] = RSUB + 1
		job["ci"] = 0
		_commit_ring(level, st, done)


func _ring_row(level: int, ri: int) -> Array:
	var r0: float = radius * INNER_R_FRAC
	var r_in: float = r0 * pow(2.0, float(level))
	var r_out: float = r_in * 2.0
	var rr: float = r_in + (r_out - r_in) * float(ri) / float(RSUB)
	var row: Array = []
	for ci in range(SEG):
		var dir: Vector3 = _ring_dir(TAU * float(ci) / float(SEG), rr)
		var h: float = _memo_height(dir)
		row.append({"p": dir * (radius + TILE_LIFT + h), "d": dir})
	return row


func _commit_cap(st: SurfaceTool, done: Array) -> void:
	var arrays: Array = st.commit_to_arrays()
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if _cap_mesh == null:
		_cap_mesh = MeshInstance3D.new()
		_cap_mesh.name = "ClipmapCap"
		_root.add_child(_cap_mesh)
	_cap_mesh.mesh = mesh
	_cap_mesh.set_surface_override_material(0, _skin_material())
	done.append("cap")


func _commit_ring(level: int, st: SurfaceTool, done: Array) -> void:
	var arrays: Array = st.commit_to_arrays()
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
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
	done.append(level)
	patch_loaded.emit(level)


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


func _add_vert(st: SurfaceTool, p: Vector3, dir: Vector3) -> void:
	st.set_normal(dir)
	var h: float = _memo_height(dir)
	var skin: Dictionary = _memo_color(dir, h)
	st.set_color(skin["splat"])
	st.set_uv2(skin["aux"])
	st.set_uv(Vector2(fposmod(p.x * 0.0015, 1.0), fposmod(p.z * 0.0015, 1.0)))
	st.add_vertex(p)


func _memo_height(dir: Vector3) -> float:
	var cached = _memo_h.get_value(dir, world_seed)
	if cached != null:
		return float(cached)
	var h: float = TerrainGen.terrain_height(dir, world_seed) if terrain_on else 0.0
	_memo_h.set_value(dir, world_seed, h)
	return h


func _memo_color(dir: Vector3, h: float) -> Dictionary:
	var cached = _memo_col.get_value(dir, world_seed)
	if cached != null:
		return cached
	var d: Dictionary
	if terrain_on:
		d = TerrainGen.splat_skin(dir, world_seed, h, 0.2)
	else:
		d = {"splat": Color(0.42, 0.55, 0.30), "aux": Vector2(0.0, 1.0)}
	_memo_col.set_value(dir, world_seed, d)
	return d
