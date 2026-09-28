## IcosahedralFaces - the 20 spherical-triangle regions of the icosahedron
## (prd-spherical-mvp.md S5). The icosahedral tiling of the sphere is
## exactly the Voronoi tessellation of its 20 face-center directions,
## so point->face membership is an exact argmax of dot(d, center).
## Vertices come from Icosahedral.VERTICES (same file family, same
## convention: +Y lat via asin, lon via atan2(z, x)).
## Frame primitive: no autoload, no GameManager dependency.
extends RefCounted

class_name IcosahedralFaces

const PHI: float = 1.6180339887498949

## Unit face-center directions and the 3 vertex indices per face,
## built at load time from the vertex set via edge distance (every
## triangle of 3 mutually-closest vertices is a face; each edge is
## shared by exactly 2 faces). Deterministic and assertion-checked.
static var _face_centers: PackedVector3Array = PackedVector3Array()
static var _face_verts: Array = []  # Array[PackedInt32Array]
static var _face_neighbors: Array = []  # Array[PackedInt32Array]
static var _built: bool = false


static func _ensure_built() -> void:
	if _built:
		return
	var verts: Array[Vector3] = []
	for v in Icosahedral.VERTICES:
		verts.append(v.normalized())

	# Construction: (1) the 30 edges are the min-chord vertex pairs;
	# (2) each edge is completed by exactly 2 common edge-neighbors,
	# giving 30*2/3 = 20 faces. Robust against the golden-rectangle
	# set's non-edge chords (some form spurious equilateral triples
	# at larger chords; none touch the min chord).
	var d_min: float = INF
	for i in range(12):
		for j in range(i + 1, 12):
			d_min = minf(d_min, verts[i].distance_to(verts[j]))
	var chord_eps: float = d_min * 0.05

	var edge_pairs: Array = []  # Array[[int,int]] min-chord pairs
	for i in range(12):
		for j in range(i + 1, 12):
			if abs(verts[i].distance_to(verts[j]) - d_min) <= chord_eps:
				edge_pairs.append([i, j])
	assert(edge_pairs.size() == 30)

	# Edge-neighbors by vertex.
	var nbr_map := {}  # int -> PackedInt32Array
	for v in range(12):
		nbr_map[v] = PackedInt32Array()
	for e in edge_pairs:
		nbr_map[e[0]].append(e[1])
		nbr_map[e[1]].append(e[0])
	for v in range(12):
		assert(nbr_map[v].size() == 5)

	var seen := {}  # sorted-triple key -> face index
	var edges := {}  # "min-max" -> Array[int] of face indices
	for e in edge_pairs:
		for c in nbr_map[e[1]]:
			if not nbr_map[e[0]].has(c):
				continue
			var triple: Array[int] = [e[0], e[1], c]
			triple.sort()
			var key: String = "%d-%d-%d" % [triple[0], triple[1], triple[2]]
			if seen.has(key):
				continue
			var i: int = triple[0]
			var j: int = triple[1]
			var k: int = triple[2]
			var a: Vector3 = verts[i]
			var b: Vector3 = verts[j]
			var cc: Vector3 = verts[k]
			var center: Vector3 = (a + b + cc).normalized()
			if a.cross(b).dot(cc) < 0.0:
				var tmp: int = j
				j = k
				k = tmp
				b = verts[j]
				cc = verts[k]
			var fidx: int = _face_verts.size()
			_face_centers.append(center)
			_face_verts.append(PackedInt32Array([i, j, k]))
			seen[key] = fidx

			for pair in [[i, j], [j, k], [k, i]]:
				var pkey: String = "%d-%d" % [mini(pair[0], pair[1]), maxi(pair[0], pair[1])]
				if not edges.has(pkey):
					edges[pkey] = []
				edges[pkey].append(fidx)

	# Faces are neighbors iff they share an edge.
	_face_neighbors = []
	for f in range(_face_verts.size()):
		var nbrs: PackedInt32Array = PackedInt32Array()
		var fv: PackedInt32Array = _face_verts[f]
		for pair in [[fv[0], fv[1]], [fv[1], fv[2]], [fv[2], fv[0]]]:
			var key: String = "%d-%d" % [mini(pair[0], pair[1]), maxi(pair[0], pair[1])]
			for other in edges[key]:
				if other != f and not nbrs.has(other):
					nbrs.append(other)
		nbrs.sort()
		_face_neighbors.append(nbrs)
	_built = true


## Face count (always 20).
static func face_count() -> int:
	_ensure_built()
	return _face_centers.size()


## Unit center direction of a face.
static func face_center(face: int) -> Vector3:
	_ensure_built()
	return _face_centers[face]


## The 3 vertex indices of a face, outward-wound.
static func face_vertices(face: int) -> PackedInt32Array:
	_ensure_built()
	return _face_verts[face]


## Neighbor faces (share an edge); 3 per face.
static func neighbors(face: int) -> PackedInt32Array:
	_ensure_built()
	return _face_neighbors[face]


## Face whose region contains direction d (need not be normalized).
## Exact: the tiling is the Voronoi tessellation of the face centers.
static func face_for_direction(d: Vector3) -> int:
	_ensure_built()
	var dir: Vector3 = d.normalized()
	var best: int = 0
	var best_dot: float = -2.0
	for f in range(_face_centers.size()):
		var dot: float = dir.dot(_face_centers[f])
		if dot > best_dot:
			best_dot = dot
			best = f
	return best


## Face containing a world position on a planet of the given radius.
static func face_for_position(pos: Vector3, _planet_radius: float = 20000.0) -> int:
	return face_for_direction(pos)


## Great-circle arc length (radians) from a unit direction to the
## face's center; 0 means dead center.
static func angular_distance_to_center(d: Vector3, face: int) -> float:
	_ensure_built()
	var dir: Vector3 = d.normalized()
	return acos(clampf(dir.dot(_face_centers[face]), -1.0, 1.0))
