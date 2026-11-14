## PropChunk -- stable, player-independent addressing for the prop layer.
##
## THE PROBLEM IT SOLVES (labs/prd-clipmap.md section 9): props must not be
## addressed by the terrain RENDERER. The retired streamer addressed them by icosa
## FACE (coarse, 4 live, whole-face rebuilds); the clipmap is RING-addressed
## and its rings RE-CENTRE on the player -- a prop addressed by a ring would
## change identity as the player walks. Both are wrong for props.
##
## A prop chunk is a PURE FUNCTION of a direction and a fixed subdivision
## depth: the terrain face (0..19, `IcosahedralFaces`) + a barycentric cell
## of that face at `depth`. The chunk grid NEVER moves. The same direction
## yields the same chunk key on every machine, every boot, for every viewer
## -- so a chunk's content (derived elsewhere from the seed) is stable,
## cacheable, and shared. This module is PURE ADDRESSING ONLY: no meshes,
## no seeds, no scene tree. (Frame primitive: no autoload, no class_name.)
##
## NAMESPACE NOTE (the same trap SpatialFragmenter documents): "face" names
## TWO things in the spatial layer. This module uses the 0..19 TERRAIN face
## (`IcosahedralFaces`), NOT the 0..11 icosa VERTEX. Do not mix them.
extends RefCounted

const Faces = preload("res://core/frame/math/icosahedral_faces.gd")
const Icosa = preload("res://core/frame/math/icosahedral.gd")

## Chunk keys pack (face: 5 bits) | (i: 10 bits) | (j: 10 bits).
const BITS_CELL: int = 10
const MASK_CELL: int = (1 << BITS_CELL) - 1
const SHIFT_J: int = 0
const SHIFT_I: int = BITS_CELL
const SHIFT_FACE: int = 2 * BITS_CELL

## The maximum subdivision depth (i, j fit in 10 bits => n = 2^depth <= 1024).
const MAX_DEPTH: int = 10

## The default prop chunk depth. Face edge chord is ~1.0515 * radius; at
## depth 6 a cell edge is ~1.0515 * radius / 64 (328 m at the 20 km canon),
## a sane prop-streaming unit. Depth is always passed explicitly by callers
## so a world may choose its own.
const DEFAULT_DEPTH: int = 6

## Per-depth cache of cell-center directions, keyed "face:i:j".
static var _center_cache: Dictionary = {}


## Cells per face edge at this depth (n = 2^depth).
static func cells_per_edge(depth: int) -> int:
	return 1 << clampi(depth, 0, MAX_DEPTH)


## Pack a chunk key from its parts.
static func make_key(face: int, i: int, j: int) -> int:
	return (face << SHIFT_FACE) | (i << SHIFT_I) | j


static func face_of(key: int) -> int:
	return (key >> SHIFT_FACE) & 0x1F


static func cell_of(key: int) -> Vector2i:
	return Vector2i((key >> SHIFT_I) & MASK_CELL, key & MASK_CELL)


## The barycentric (u, v) coordinates of a unit direction inside its face,
## via the exact linear solve d = u*a + v*b + w*c (a, b, c the face verts),
## normalized so u + v + w = 1. Returns Vector3(u, v, w). The face's verts
## are linearly independent, so the solve always exists.
static func _barycentric(dir: Vector3, face: int) -> Vector3:
	var verts: PackedInt32Array = Faces.face_vertices(face)
	var a: Vector3 = Icosa.VERTICES[verts[0]]
	var b: Vector3 = Icosa.VERTICES[verts[1]]
	var c: Vector3 = Icosa.VERTICES[verts[2]]
	# Cramer's rule on [a b c] x = d.
	var det: float = a.dot(b.cross(c))
	if absf(det) < 1e-9:
		return Vector3(1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0)
	var u: float = dir.dot(b.cross(c)) / det
	var v: float = a.dot(dir.cross(c)) / det
	var w: float = a.dot(b.cross(dir)) / det
	var s: float = u + v + w
	if absf(s) < 1e-9:
		return Vector3(1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0)
	return Vector3(u / s, v / s, w / s)


## The face TRIANGLE containing a direction (all-non-negative barycentric).
## NB this is the triangular tiling, NOT `Faces.face_for_direction` (which is
## the nearest-face-center / Voronoi partition). The prop grid needs the
## triangular partition because it tiles the sphere EXACTLY with no gaps or
## overlaps, so a chunk cell round-trips to itself by construction.
static func face_containing(dir: Vector3) -> int:
	var d: Vector3 = dir.normalized()
	var seed_face: int = Faces.face_for_direction(d)
	var bc: Vector3 = _barycentric(d, seed_face)
	if bc.x >= 0.0 and bc.y >= 0.0 and bc.z >= 0.0:
		return seed_face
	var best_face: int = seed_face
	var best_min: float = -2.0
	for f in range(Faces.face_count()):
		var c: Vector3 = _barycentric(d, f)
		var mn: float = minf(c.x, minf(c.y, c.z))
		if mn > best_min:
			best_min = mn
			best_face = f
	return best_face


## The chunk key containing a direction at this depth.
static func chunk_for_dir(dir: Vector3, depth: int = DEFAULT_DEPTH) -> int:
	var d: Vector3 = dir.normalized()
	var face: int = face_containing(d)
	var n: int = cells_per_edge(depth)
	var bc: Vector3 = _barycentric(d, face)
	var i: int = clampi(int(floor(bc.x * float(n))), 0, n - 1)
	var j: int = clampi(int(floor(bc.y * float(n))), 0, n - 1)
	if i + j > n - 1:
		j = n - 1 - i
	return make_key(face, i, j)


## The representative (centroid) direction of a chunk. Cached per (depth, key).
## The centroid is strictly interior to the cell (u, v, w all > 0), so it
## round-trips through `chunk_for_dir` back to the same key.
static func chunk_center_dir(key: int, depth: int = DEFAULT_DEPTH) -> Vector3:
	var ck: String = "%d:%d" % [depth, key]
	var hit = _center_cache.get(ck)
	if hit != null:
		return hit
	var face: int = face_of(key)
	var cell: Vector2i = cell_of(key)
	var n: int = cells_per_edge(depth)
	var verts: PackedInt32Array = Faces.face_vertices(face)
	var a: Vector3 = Icosa.VERTICES[verts[0]]
	var b: Vector3 = Icosa.VERTICES[verts[1]]
	var c: Vector3 = Icosa.VERTICES[verts[2]]
	var u: float = (float(cell.x) + 1.0 / 3.0) / float(n)
	var v: float = (float(cell.y) + 1.0 / 3.0) / float(n)
	var w: float = maxf(1e-6, 1.0 - u - v)
	var dir: Vector3 = (a * u + b * v + c * w).normalized()
	_center_cache[ck] = dir
	return dir


## The angular radius of a chunk cell (radians): the max great-circle
## distance from the cell center to its corners. Used by radius queries.
static func chunk_angular_radius(depth: int = DEFAULT_DEPTH) -> float:
	# A cell spans ~1/n of the face edge; the face's angular reach is its
	# circumradius, so a safe upper bound is (face_reach_max) / n * sqrt(2).
	var n: float = float(cells_per_edge(depth))
	return (1.0 / n) * 1.5


## The angular reach of a face (max vertex angle from center), cached.
static func face_reach(face: int) -> float:
	var best: float = 0.0
	var center: Vector3 = Faces.face_center(face)
	for vi in Faces.face_vertices(face):
		best = maxf(best, center.angle_to(Icosa.VERTICES[vi]))
	return best


## A direction inside a chunk cell from local barycentric coords (u, v) in
## [0, 1). The cell is the sub-triangle [i, i+1] x [j, j+1] (clipped by the
## face diagonal); `u`/`v` are fractions WITHIN the cell, mapped into the
## face's barycentric frame. Pure: same (key, u, v) -> same direction.
static func cell_point(key: int, u: float, v: float, depth: int = DEFAULT_DEPTH) -> Vector3:
	var face: int = face_of(key)
	var cell: Vector2i = cell_of(key)
	var n: int = cells_per_edge(depth)
	var verts: PackedInt32Array = Faces.face_vertices(face)
	var a: Vector3 = Icosa.VERTICES[verts[0]]
	var b: Vector3 = Icosa.VERTICES[verts[1]]
	var c: Vector3 = Icosa.VERTICES[verts[2]]
	var bu: float = (float(cell.x) + clampf(u, 0.0, 1.0)) / float(n)
	var bv: float = (float(cell.y) + clampf(v, 0.0, 1.0)) / float(n)
	if bu + bv > 1.0:
		var over: float = bu + bv - 1.0
		bu -= over * 0.5
		bv -= over * 0.5
	var bw: float = maxf(1e-6, 1.0 - bu - bv)
	return (a * bu + b * bv + c * bw).normalized()


## The approximate area of one chunk cell in square kilometres on a sphere
## of `radius_m` (planar approximation; cells are small).
static func chunk_area_km2(radius_m: float, depth: int = DEFAULT_DEPTH) -> float:
	var edge_m: float = (1.0515 * radius_m) / float(cells_per_edge(depth))
	var area_m2: float = 0.5 * edge_m * edge_m
	return area_m2 / 1.0e6


## Every chunk whose cell could lie within `ang_radius` of `center_dir`.
## Faces farther than (ang_radius + max face reach) are skipped; within a
## candidate face, only a barycentric window around the center is scanned
## (a full n^2 scan per face is wasteful at depth 6+). Deterministic order.
static func chunks_in_radius(center_dir: Vector3, ang_radius: float, depth: int = DEFAULT_DEPTH) -> Array:
	var out: Array = []
	var cd: Vector3 = center_dir.normalized()
	var n: int = cells_per_edge(depth)
	var cell_r: float = chunk_angular_radius(depth)
	for face in range(Faces.face_count()):
		var fc: Vector3 = Faces.face_center(face)
		if cd.angle_to(fc) > ang_radius + face_reach(face):
			continue
		# Window in (i, j): the cell holding the query center's barycentric
		# coords, padded by the angular radius expressed in cells. The pad is
		# generous (edge angle = min face edge), so the window always covers
		# the true hit set; each cell still gets the exact angle test below.
		var bc: Vector3 = _barycentric(cd, face)
		var edge_ang: float = _face_min_edge_ang(face)
		var pad: int = int(ceil((ang_radius + cell_r) / (edge_ang / float(n)))) + 2
		var ci: int = clampi(int(floor(bc.x * float(n))), 0, n - 1)
		var cj: int = clampi(int(floor(bc.y * float(n))), 0, n - 1)
		var i0: int = maxi(0, ci - pad)
		var i1: int = mini(n - 1, ci + pad)
		var j0: int = maxi(0, cj - pad)
		var j1: int = mini(n - 1, cj + pad)
		for i in range(i0, i1 + 1):
			for j in range(j0, j1 + 1):
				if i + j > n - 1:
					continue
				var key: int = make_key(face, i, j)
				var cc: Vector3 = chunk_center_dir(key, depth)
				if cd.angle_to(cc) <= ang_radius + cell_r:
					out.append(key)
	return out


## The smallest edge angular length of a face (the tightest window scale).
static func _face_min_edge_ang(face: int) -> float:
	var verts: PackedInt32Array = Faces.face_vertices(face)
	var a: Vector3 = Icosa.VERTICES[verts[0]].normalized()
	var b: Vector3 = Icosa.VERTICES[verts[1]].normalized()
	var c: Vector3 = Icosa.VERTICES[verts[2]].normalized()
	return minf(a.angle_to(b), minf(b.angle_to(c), c.angle_to(a)))
