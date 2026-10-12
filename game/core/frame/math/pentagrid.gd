## Pentagrid — de Bruijn's five-grid construction of the Penrose P3
## rhomb tiling (the GLOBAL counterpart to penrose.gd's substitution
## family).
##
## While penrose.gd builds the canonical tiling by deflation from a
## seed and addresses the plane only inside the handed seed triangle,
## pentagrid.gd covers the WHOLE plane: every point resolves to its
## rhombus via the dual construction (de Bruijn 1981, "Algebraic
## theory of Penrose's non-periodic tilings of the plane").
##
## Design (labs/world-building-research.md sec 1.5-1.9):
## - Five families of parallel lines with unit spacing, normals
##   v_i = (cos(2*pi*i/5), sin(2*pi*i/5)) — 72-degree spacing (NOT
##   36): v_i are the normals, the grid lines run perpendicular.
##   Lines: L_{i,k} = { x : x.v_i + gamma_i = k }, k integer.
## - Shift conditions, verified via the reference construction
##   (mdickinson/pentagrid) and Lutfalla (arXiv:2004.10128):
##     * Penrose class:  sum_i gamma_i in Z  (canonical: sums to 0)
##     * regularity: no point lies on 3+ lines of distinct families
##       (dual of a singular crossing would be a hexagon, not a
##       rhombus). singular_count()enables the law check; the
##       canonical gamma is triple-free over the built region.
## - Duality (the whole construction in three rules):
##     grid cell      -> one tiling vertex  F(K) = sum_i K_i v_i
##     line crossing  -> one rhombus tile (the 4 surrounding cells'
##                       duals are its corners, edge directions v_r,v_s)
##     grid line      -> one ribbon of rhombi
##   Cell coordinates: K_i(x) = ceil(x.v_i + gamma_i). With
##   sum gamma_i = 0 the index S = sum K_i is invariant in {1,2,3,4}
##   over the plane — the standard pentagrid sanity invariant.
## - Tile kinds by family separation: |s - r| (cyclic) 1 -> FAT
##   (acute 72), 2 -> THIN (acute 36). Edge directions v_r, v_s;
##   interior angle between them = 72*(s-r) (deg) for s > r.
## - tile_at(p): compute the cell K(p); the preimage of the star of
##   F(K) (all rhombi incident to the dual vertex) is exactly the
##   closure of cell K, so every p lands in one of the (<= 40)
##   candidate rhombi having K as a corner cell. Probes that sit on
##   tile edges resolve deterministically to the first candidate,
##   same convention as penrose.gd's boundary-consistent containment.
## - Validator: geometric closure (unit-edge + corner-class +
##   alternation, edge multiplicity <= 2, interior-vertex angle
##   sums = 10 units of 36 degrees) PLUS the Ammann-arrow decoration
##   check — per-edge (arrow_type, direction) must superimpose
##   exactly across a seam, computed WORLD-COORDINATE from each
##   side's own tile so a flipped tile cannot fake a match.
##   Necessary-not-sufficient: MathPages kmath621 shows arrow-matched
##   clusters that cannot complete (ten thin rhombi around a point);
##   Fernique-Lutfalla (arXiv:2211.08239) shows the 0-atlas alone
##   admits periodic counterexamples. The arrow layer is still the
##   strongest LOCAL table available in code form here a 1-atlas
##   port would be the next rung up.
## - Gnomonic projection seam: tangent-plane coordinates at
##   (center_lat, center_lon) map onto the planet sphere (spherical.gd
##   convention: +Y north pole axis, degrees in). Near the tangent
##   point rhombi stay near-congruent; far tiles distort (sec²) —
##   per-patch construction, not a whole-planet map.
## - Raster seam: triangle_soup() turns a patch into drawable data
##   (PackedVector3Array positions, per-triangle kind id) ready for an
##   ArrayMesh/ImmediateMesh feed. No Node is created here — frame
##   primitive stays pure data.
##
## Frame primitive: NO autoload, NO class_name, NO GameManager
## dependency.
##
## Ammann-arrow model v1 (the honest scope, see the research doc):
## every tiling edge is dual to one pentagrid segment; its mark is
## the de Bruijn STRIP-INDEX LABEL of the two cells it separates:
##   mult(edge of family f, base cell K) = 2 if S(K) is odd else 1
##   dir = the unit chord F(K) -> F(K+e_f)  (= family direction v_f)
## S(K) = sum K_i is the quasilattice index — in the 5D cut-and-project
## picture this parity IS the edge label the Ammann glyph decoration
## encodes. Because both tiles incident to a shared edge contain the
## same two corner cells, both sides compute the SAME mark in world
## coordinates: superposition holds BY CONSTRUCTION (no perimeter
## convention, no winding dependence).
##
## Known algebraic fact recorded here (why the naive per-tile-kind
## glyph table cannot be ported directly): "fat = one mult class on
## all four edges" + "thin = one of each" forces family-adjacent
## mults equal and family-sep-2 mults different, which is globally
## inconsistent — the real glyph mult varies PER SEGMENT along a
## line, exactly what the parity label provides. The full 10-class
## glyph table stays documented as deferred (figure-level data); the
## parity label is its provably seam-consistent core, adequate for
## local legality + mutation detection, necessary-not-sufficient for
## global extendability (MathPages kmath621).
##
## Research companion: labs/world-building-research.md sec 1; primary
## sources: N.G. de Bruijn (1981); Lutfalla arXiv:2004.10128;
## mdickinson/pentagrid (sample shift reused as canonical);
## neverendingbooks "de Bruijn's pentagrids"; MathPages kmath621.
extends RefCounted

## Number of grid families (the pentagrid; PENTAGRID_SPOKES in
## penrose.gd documents the 36-degree vocabulary of the tiles).
const PENTAGRID_FAMILIES: int = 5

## Angle between consecutive normals (72 deg), in radians per family.
const ANGLE_STEP: float = 1.2566370614359172  # TAU / 5

## Canonical shift: the worked sample of the reference construction
## (mdickinson/pentagrid). Sums to EXACTLY 0 in double arithmetic
## within 1e-16 — the Penrose phase-sum class. Different shifts in
## the class give different (local-isomorphic) P3 tilings.
const GAMMA: Array[float] = [0.3, 0.2, -0.1, -0.4, 0.0]

## Vertex invariant: with sum gamma_i = 0, sum_i K_i(x) stays in
## {1..4} over the plane (INDEX_MIN..INDEX_MAX).
const INDEX_MIN: int = 1
const INDEX_MAX: int = 4

## Tolerances: grid arithmetic is exact to ~1e-12; containment slop
## matches penrose.gd's edge-eps convention.
const EPS: float = 0.000001

enum TileKind { FAT, THIN }

## A rhombus tile of the dual tiling: perimeter-ordered vertices
## (convex quad), families (r, s) r < s and their line levels
## (kr, ks) — which together are the tile's GLOBAL identity.
class Tile:
	var kind: int
	var verts: Array[Vector2]
	var families: Vector2i
	var levels: Vector2i

	func _init(kind_in: int, verts_in: Array[Vector2], fams: Vector2i, lvls: Vector2i) -> void:
		kind = kind_in
		verts = verts_in
		families = fams
		levels = lvls

	## Global deterministic address: "pentagrid.<r>.<s>.<kr>.<ks>".
	## Stable for a fixed gamma; uniquely names the rhombus in the
	## whole plane (unlike annotation windows, which are seed-local).
	func key() -> String:
		return "pentagrid.%d.%d.%d.%d" % [families.x, families.y, levels.x, levels.y]

	func area() -> float:
		var edge1: Vector2 = verts[1] - verts[0]
		var edge2: Vector2 = verts[3] - verts[0]
		return absf(edge1.cross(edge2))

	## Interior angle (degrees) at corner `c` of the perimeter quad.
	func corner_angle(c: int) -> float:
		var prev: Vector2 = verts[(c + 3) % 4] - verts[c]
		var nxt: Vector2 = verts[(c + 1) % 4] - verts[c]
		return absf(rad_to_deg(prev.angle_to(nxt)))


## ---------------------------------------------------------------------------
## Grid facts


## Unit normal of family i (72-degree spacing). Computed per call —
## symmetric pairs cancel exactly in float, keeping the sum-zero
## invariants honest.
static func normal(i: int) -> Vector2:
	var a: float = float(i) * ANGLE_STEP
	return Vector2(cos(a), sin(a))


## Cell coordinates of a point: K_i = ceil(x.v_i + gamma_i).
static func cell_coords(p: Vector2, gamma: Array = GAMMA) -> Array[int]:
	var out: Array[int] = []
	for i in range(PENTAGRID_FAMILIES):
		out.append(int(ceilf(p.dot(normal(i)) + gamma[i])))
	return out


## The dual of a cell: one tiling vertex.
static func dual_vertex(k: Array[int], gamma: Array = GAMMA) -> Vector2:
	var v := Vector2.ZERO
	for i in range(PENTAGRID_FAMILIES):
		v += float(k[i]) * normal(i)
	return v


## Crossing point of family-r line level kr with family-s line level
## ks: solves x.v_r = kr - gamma_r, x.v_s = ks - gamma_s (2x2 Cramer).
static func line_crossing(r: int, s: int, kr: int, ks: int, gamma: Array = GAMMA) -> Vector2:
	var vr := normal(r)
	var vs := normal(s)
	var a: float = float(kr) - gamma[r]
	var b: float = float(ks) - gamma[s]
	var det: float = vr.x * vs.y - vr.y * vs.x
	return Vector2((a * vs.y - b * vr.y) / det, (b * vr.x - a * vs.x) / det)


## Cyclic family separation min((s-r) mod 5, 5 - that): 1 = fat, 2 = thin.
static func family_separation(r: int, s: int) -> int:
	var d: int = (s - r) % PENTAGRID_FAMILIES
	if d < 0:
		d += PENTAGRID_FAMILIES
	return mini(d, PENTAGRID_FAMILIES - d)


## ---------------------------------------------------------------------------
## Rhombus from one crossing


## The rhombus dual to the crossing of L_{r,kr} and L_{s,ks}: the
## four surrounding cells' duals in perimeter order. Assumes (and
## region laws verify) the grid is regular at this crossing.
static func rhombus_at(r: int, s: int, kr: int, ks: int, gamma: Array = GAMMA) -> Tile:
	var x0 := line_crossing(r, s, kr, ks, gamma)
	var k: Array[int] = []
	for i in range(PENTAGRID_FAMILIES):
		if i == r:
			k.append(kr)
		elif i == s:
			k.append(ks)
		else:
			k.append(int(ceilf(x0.dot(normal(i)) + gamma[i])))
	var verts: Array[Vector2] = []
	for combo in [[0, 0], [1, 0], [1, 1], [0, 1]]:
		var q: Array[int] = k.duplicate()
		q[r] += combo[0]
		q[s] += combo[1]
		verts.append(dual_vertex(q, gamma))
	var kind: int = TileKind.FAT if family_separation(r, s) == 1 else TileKind.THIN
	return Tile.new(kind, verts, Vector2i(r, s), Vector2i(kr, ks))


## ---------------------------------------------------------------------------
## Global point lookup


## The rhombus containing point p, or null when no candidate
## resolves. Method (derived and verified empirically):
## F(cell) = 2.5*x + C where C = sum(gamma_i + beta_i)*v_i is a
## bounded window offset (|C| <= phi + |gamma-offset| ~ 2.5), so the
## cells whose dual vertex is one of the containing tile's corners
## cluster in a small disk around x0_hat = (p - gamma_offset) / 2.5.
## Enumerate cells on a grid over that disk, keep those whose dual
## vertex lands within reach of p, then test all rhombi having the
## candidate as a corner cell (10 family pairs x 4 level combos =
## 40 candidates each) by genuine containment. Probes on tile edges
## resolve to the first candidate, same convention as penrose.gd.
static func tile_at(p: Vector2, gamma: Array = GAMMA) -> Tile:
	for k in _corner_candidates(p, gamma):
		for r in range(PENTAGRID_FAMILIES):
			for s in range(r + 1, PENTAGRID_FAMILIES):
				for kr in [k[r], k[r] - 1]:
					for ks in [k[s], k[s] - 1]:
						var t := rhombus_at(r, s, kr, ks, gamma)
						if _point_in_quad(p, t.verts):
							return t
	return null


## Dual-vertex window offset contributed by the fixed shifts:
## C_gamma = sum gamma_i v_i. The beta part (per-cell phases in
## (0,1]) adds the acceptance window (circumradius phi); together
## C is bounded, which is what makes the disk centered at
## (p - C_gamma)/2.5 a complete candidate source.
static func _gamma_offset(gamma: Array) -> Vector2:
	var c := Vector2.ZERO
	for i in range(PENTAGRID_FAMILIES):
		c += gamma[i] * normal(i)
	return c


## Cells whose dual vertex is near p (within the acceptance-window
## reach), found by sampling cell_coords on a grid over the disk
## where any such cell must live.
static func _corner_candidates(p: Vector2, gamma: Array) -> Array:
	var center: Vector2 = (p - _gamma_offset(gamma)) * 0.4  # x ~ p / 2.5
	var reach: float = 1.05
	var out: Array = []
	var seen: Dictionary = {}
	for gx in range(-3, 4):
		for gy in range(-3, 4):
			var x := center + Vector2(float(gx) * 0.45, float(gy) * 0.45)
			if x.distance_to(center) > reach:
				continue
			var k := cell_coords(x, gamma)
			# Cheap prefilter: the dual vertex must land near p.
			if dual_vertex(k, gamma).distance_to(p) > 2.3:
				continue
			var key: String = str(k)
			if not seen.has(key):
				seen[key] = true
				out.append(k)
	return out


## Global deterministic scope key for a point (seam for CosmicRng):
## the tile's global identity, or the documented escape scope.
static func tile_key(p: Vector2, gamma: Array = GAMMA) -> String:
	var t := tile_at(p, gamma)
	if t == null:
		return "pentagrid.escape"
	return t.key()


## ---------------------------------------------------------------------------
## Region construction (raster/domain input)


## Every rhombus whose dual crossing lies within [-half_extent,
## half_extent]^2 (plus the ~5-cell reach of the dual map). Tile
## count grows ~ O(half_extent^2) per family pair.
static func build_region(gamma: Array = GAMMA, half_extent: float = 10.0) -> Array[Tile]:
	var out: Array[Tile] = []
	var kmax: int = int(ceilf(half_extent)) + 2
	for r in range(PENTAGRID_FAMILIES):
		for s in range(r + 1, PENTAGRID_FAMILIES):
			for kr in range(-kmax, kmax + 1):
				for ks in range(-kmax, kmax + 1):
					var t := rhombus_at(r, s, kr, ks, gamma)
					if _tile_within(t, half_extent):
						out.append(t)
	return out


## Count singular crossings (3+ concurrent lines) reachable in the
## region: the crossing x0 sits on an integer level of any third
## family. Laws assert ZERO for the canonical gamma.
static func singular_count(gamma: Array = GAMMA, kmax: int = 8) -> int:
	var count := 0
	for r in range(PENTAGRID_FAMILIES):
		for s in range(r + 1, PENTAGRID_FAMILIES):
			for kr in range(-kmax, kmax + 1):
				for ks in range(-kmax, kmax + 1):
					var x0 := line_crossing(r, s, kr, ks, gamma)
					for l in range(PENTAGRID_FAMILIES):
						if l == r or l == s:
							continue
						var w: float = x0.dot(normal(l)) + gamma[l]
						if absf(w - roundf(w)) < EPS:
							count += 1
	return count


## ---------------------------------------------------------------------------
## Matching-rule validator (v1: geometric closure)


## Validate a patch (Array of Tile). Errors (any => not ok):
##   1. unit-edge violation (edge length != 1)
##   2. corner-class violation (angle outside {36,72,108,144} deg,
##      or classes not alternating abab for the tile's kind)
##   3. edge multiplicity > 2 (3+ rhombi on one segment — impossible
##      in a legal P3 patch)
##   4. interior-vertex angle sum != 10 units of 36 deg (closure).
##      Vertices touched by a count-1 edge are patch BOUNDARY and are
##      exempt (an open patch legitimately ends mid-plane).
## Known v1 limits (documented, by design): boundary-vs-hole
## ambiguity and the Ammann-arrow cyclic-order table are deferred —
## necessary-not-sufficient per MathPages kmath621.
static func validate_patch(patch: Array) -> Dictionary:
	var errors: Array[String] = []
	# edge key -> {count, endpoints}
	var edges: Dictionary = {}
	# vertex key -> Array of {units: int}
	var vertex_corners: Dictionary = {}

	for t in patch:
		var verts: Array[Vector2] = t.verts
		for e in range(4):
			var a: Vector2 = verts[e]
			var b: Vector2 = verts[(e + 1) % 4]
			var el: float = a.distance_to(b)
			if absf(el - 1.0) > 0.001:
				errors.append("tile %s edge %d length %.6f" % [t.key(), e, el])
			var ek := _edge_key(a, b)
			if not edges.has(ek):
				edges[ek] = {"count": 0, "ends": [a, b]}
			edges[ek]["count"] = int(edges[ek]["count"]) + 1
		var units: Array[int] = []
		for c in range(4):
			var ang: float = t.corner_angle(c)
			var u := int(roundf(ang / 36.0))
			units.append(u)
			var ok_cls: bool = (ang > 35.9 and ang < 36.1) or (ang > 71.9 and ang < 72.1) \
				or (ang > 107.9 and ang < 108.1) or (ang > 143.9 and ang < 144.1)
			if not ok_cls:
				errors.append("tile %s corner %d angle %.6f" % [t.key(), c, ang])
				continue
			var fat_class := (u == 2 or u == 3)
			var thin_class := (u == 1 or u == 4)
			if t.kind == TileKind.FAT and not fat_class:
				errors.append("tile %s corner %d unit %d on FAT" % [t.key(), c, u])
			if t.kind == TileKind.THIN and not thin_class:
				errors.append("tile %s corner %d unit %d on THIN" % [t.key(), c, u])
		# Alternation abab around the perimeter (opposite corners equal,
		# adjacent different).
		if not (units[0] == units[2] and units[1] == units[3] and units[0] != units[1]):
			errors.append("tile %s corner units not alternating %s" % [t.key(), units])
		for c in range(4):
			var vk := _qkey(verts[c])
			if not vertex_corners.has(vk):
				vertex_corners[vk] = []
			vertex_corners[vk].append({"units": units[c]})

	for ek in edges:
		var cnt: int = edges[ek]["count"]
		if cnt > 2:
			errors.append("edge %s shared by %d tiles" % [ek, cnt])

	# Ammann-arrow seam law (see _validate_arrows): shared edges must
	# superimpose both arrow bits in world coordinates.
	_validate_arrows(patch, errors)

	# Boundary = endpoints of count-1 edges (and count-0 cannot happen).
	var boundary: Dictionary = {}
	for ek in edges:
		if edges[ek]["count"] == 1:
			for end_pt in edges[ek]["ends"]:
				boundary[_qkey(end_pt)] = true

	for vk in vertex_corners:
		if boundary.has(vk):
			continue
		var corners: Array = vertex_corners[vk]
		if corners.size() < 3:
			continue
		var total := 0
		for corner in corners:
			total += int(corner["units"])
		if total != 10:
			errors.append("interior vertex %s angle sum %d != 10" % [vk, total])

	return {"ok": errors.is_empty(), "errors": errors, "tiles": patch.size()}


## ---------------------------------------------------------------------------
## Ammann-arrow decoration (v1: the strongest local table)


## Arrow marks for the four perimeter edges `e` (0..3) of tile `t`,
## in WORLD coordinates, per the strip-index rule. Recovers the
## corner cells K from (families, levels) exactly as rhombus_at builds
## them, so marks need no extra stored state.
## Constructor-order contract: verts are in rhombus_at's perimeter
## order (vert0 = dual(K), vert1 = dual(K+e_r), vert2 =
## dual(K+e_r+e_s), vert3 = dual(K+e_s)).
## Returns {"mult": 1 or 2, "dir": Vector2 (unit, sign matters)} per edge.
static func edge_arrows(t: Tile) -> Array:
	var verts: Array[Vector2] = t.verts
	var r: int = t.families.x
	var s: int = t.families.y
	# Rebuild the base corner cell K the same way rhombus_at does.
	var x0 := line_crossing(r, s, t.levels.x, t.levels.y, GAMMA)
	var k: Array[int] = []
	for i in range(PENTAGRID_FAMILIES):
		if i == r:
			k.append(t.levels.x)
		elif i == s:
			k.append(t.levels.y)
		else:
			k.append(int(ceilf(x0.dot(normal(i)) + GAMMA[i])))
	var ssum := func(c: Array[int]) -> int:
		var tot := 0
		for ci in c:
			tot += ci
		return tot
	var k_r: Array[int] = k.duplicate()
	k_r[r] += 1
	var k_s: Array[int] = k.duplicate()
	k_s[s] += 1
	var base_parity: bool = (ssum.call(k) % 2) == 1
	var plus_r_parity: bool = (ssum.call(k_r) % 2) == 1
	var plus_s_parity: bool = (ssum.call(k_s) % 2) == 1
	# THE edge rule (derived, then verified): every edge of T is dual
	# to a grid segment on ONE family line L_{f,m} separating the cell
	# pair (strip-index m, strip-index m+1). The mark's mult = parity
	# of the LOWER cell (index m) of that pair — both incident tiles
	# share the same lower cell (it is determined by the segment, not
	# by the tile), so the label superimposes BY CONSTRUCTION on any
	# seam, with NO freedom left per tile. Perimeter mapping:
	#   A: K|K+e_r   lower K        -> base_parity
	#   B: +e_r|+e_r+e_s lower K+e_r -> plus_r_parity (= !base)
	#   C: +e_s|+e_r+e_s lower K+e_s -> plus_s_parity (= !base)
	#   D: K|K+e_s   lower K        -> base_parity
	# (An earlier v1 labeled D with plus_s; the seam check correctly
	# rejected it and the law suite pinned the derived form above.)
	var mult_low: int = 2 if base_parity else 1
	var mult_up: int = 2 if not base_parity else 1
	return [
		{"mult": mult_low, "dir": (verts[1] - verts[0]).normalized()},  # A
		{"mult": mult_up,  "dir": (verts[2] - verts[1]).normalized()},  # B
		{"mult": mult_up,  "dir": (verts[2] - verts[3]).normalized()},  # C
		{"mult": mult_low, "dir": (verts[3] - verts[0]).normalized()},  # D
	]


## Orientation-independent STRING of an arrow edge in world
## coordinates: the undirected segment key plus mult plus a signed
## direction. Two tiles matching across an edge produce the SAME
## string here (dir measured from the SAME endpoints), so the check
## is "strings equal" — superposition, exactly.
static func _arrow_key(a: Vector2, b: Vector2, mult: int, dir: Vector2) -> String:
	var chord: Vector2 = (b - a).normalized()
	# Canonical (a<b) orientation so both sides name the edge alike.
	if (_qkey(a) < _qkey(b)):
		return "%s|%s|%d|%+d" % [_qkey(a), _qkey(b), mult, 1 if chord.dot(dir) >= 0.0 else -1]
	# b<a: re-express dir against the flipped chord.
	return "%s|%s|%d|%+d" % [_qkey(b), _qkey(a), mult, 1 if (-chord).dot(dir) >= 0.0 else -1]

## Arrow constraint pass for validate_patch: every SHARED edge must
## have matching (mult, dir) computed from each side's own tile.
## Boundary edges (count-1) are exempt — an open patch's rim is
## unconstrained. Necessary-not-sufficient per MathPages: arrow-lawful
## clusters can still be uncompletable; validate_patch's "ok" stays a
## legality certificate for LOCAL law, not an extension oracle.
static func _validate_arrows(patch: Array, errors: Array[String]) -> void:
	var arrows: Dictionary = {}
	var edges: Dictionary = {}
	for t in patch:
		var marks: Array = edge_arrows(t)
		var verts: Array[Vector2] = t.verts
		for e in range(4):
			var ek := _edge_key(verts[e], verts[(e + 1) % 4])
			edges[ek] = true
			var mk := _arrow_key(verts[e], verts[(e + 1) % 4], int(marks[e]["mult"]), marks[e]["dir"])
			if not arrows.has(ek):
				arrows[ek] = []
			arrows[ek].append(mk)

	for ek in arrows:
		var marks: Array = arrows[ek]
		if marks.size() < 2:
			continue  # boundary edge — no constraint by design
		var first: String = marks[0]
		for m in marks:
			if m != first:
				errors.append("arrow mismatch on edge %s: %s vs %s" % [ek, first, m])


## ---------------------------------------------------------------------------
## Spherical projection seam (gnomonic)


## Planar tiling coordinates -> planet-sphere point. The plane is the
## tangent plane at (center_lat, center_lon); planar w=(u,v) maps to
## normalize(n + u.east + v.north) * radius, with east/north an
## ORTHONORMAL tangent basis (north = UP projected onto the tangent
## plane — UP itself is only tangent at the equator). Gnomonic:
## straight planar lines stay great-circle arcs — rhombus EDGES map
## to geodesics. Use per-patch (near the tangent point distortion
## stays small).
static func gnomonic_project(planar: Vector2, center_lat: float, center_lon: float, radius: float) -> Vector3:
	var n := normal_at(center_lat, center_lon)
	var east: Vector3 = n.cross(Vector3.UP).normalized()
	var north: Vector3 = east.cross(n).normalized()
	var d: Vector3 = (n + planar.x * east + planar.y * north).normalized()
	return d * radius


## Unit direction for lat/lon in spherical.gd's convention
## (+Y north pole axis, phi = 90 - lat, theta = lon).
static func normal_at(lat: float, lon: float) -> Vector3:
	var phi: float = deg_to_rad(90.0 - lat)
	var theta: float = deg_to_rad(lon)
	return Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))


## Project a whole patch: per-tile PackedVector3Array of the 4 sphere
## corners (perimeter order preserved).
static func project_patch(patch: Array, center_lat: float, center_lon: float, radius: float) -> Array:
	var out: Array = []
	for t in patch:
		var pts := PackedVector3Array()
		for v in t.verts:
			pts.append(gnomonic_project(v, center_lat, center_lon, radius))
		out.append(pts)
	return out


## ---- Whole-planet chart atlas (multi-patch tangent centers) ----
##
## Planar one-chart-per-point is fine near the tangent center but
## the sec^2 radial distortion grows with angular distance (Snyder):
##   17.5 deg -> ~10%, 24 deg -> ~20%. A whole-planet surface is
## therefore served by SEVERAL charts, each centered on its own
## tangent center. This is NOT a global spherical Penrose tiling
## (research: no verified construction exists; Hamish Todd's T-K
## "spherical Penrose-like" work is related prior art but not P3).
## Seams BETWEEN charts need explicit stitching (shared edge
## polygons per Ralith's planetary-terrain practice); see
## disto.chart_atlas in labs/world-building-research.md.


## Max angular radius (deg) of a chart's usable cap for a given
## acceptable worst-direction (radial sec^2) scale error, as percent.
## 10 -> ~17.5 deg, 20 -> ~24 deg (tan(c) = sqrt((100+pct)/100 - 1)).
static func patch_cap_deg(percent: int) -> float:
	var s: float = 1.0 + float(percent) / 100.0
	return rad_to_deg(acos(1.0 / sqrt(s)))


## Idealized spacing (deg) between tangent centers for a covering of
## the sphere by equal caps of angular radius `cap_deg`: centers on an
## ideal hex lattice cover to cap/sqrt(3)? No — hex covering radius is
## spacing/sqrt(3); solve spacing = cap_deg * sqrt(3).
static func atlas_spacing_deg(cap_deg: float) -> float:
	return cap_deg * sqrt(3.0) * (1.0 - 1e-9)


## Number of charts an ICHOSPHERE-granular atlas needs for a planet
## (area of sphere / area of one cap), ceiling. Pure estimate for a
## hex-lattice-equivalent packing; real atlases should measure their
## own covering via each sphere point's distance to nearest center.
static func atlas_chart_count(radius: float, cap_deg: float) -> int:
	var sphere_area: float = 4.0 * PI * radius * radius
	var c: float = deg_to_rad(cap_deg)
	var cap_area: float = 2.0 * PI * radius * radius * (1.0 - cos(c))
	return int(ceilf(sphere_area / cap_area))


## ---------------------------------------------------------------------------
## Raster seam (drawable triangle soup — no Node created)


## Perimeter-ordered convex quad -> two CCW-ish planar triangles at
## height z, scaled. Returns:
##   { "positions": PackedVector3Array (2 tris per tile, 18 floats),
##     "tri_kind":  PackedInt32Array  (0=fat, 1=thin per triangle) }
## Feed directly to SurfaceTool/ArrayMesh vertices; tri_kind drives
## fat/thin coloring per renderer taste.
static func triangle_soup(patch: Array, scale: float = 1.0, z: float = 0.0) -> Dictionary:
	var pos := PackedVector3Array()
	var kinds := PackedInt32Array()
	for t in patch:
		var v: Array[Vector2] = t.verts
		for tri in [[0, 1, 2], [0, 2, 3]]:
			for idx in tri:
				pos.append(Vector3(v[idx].x * scale, v[idx].y * scale, z))
			kinds.append(t.kind)
	return {"positions": pos, "tri_kind": kinds}


## Close the raster seam: turn a triangle_soup dict into Mesh-ready
## arrays. The frame primitive still creates no Node and owns no scene
## tree — the CALLER decides whether these feed an ArrayMesh (runtime),
## an ImmediateMesh (debug) or something else. This helper passes the
## "positions" array through in the exact form Mesh.ARRAY_VERTEX wants
## and returns the matching trivial index list, with sanity checks on
## soup shape (so a corrupt soup fails LOUDLY here, not in the GPU).
##
## Example (caller side, canonical):
##   var out := Pentagrid.soup_to_mesh_arrays(Pentagrid.triangle_soup(patch))
##   var arrays := []
##   arrays.resize(Mesh.ARRAY_MAX)
##   arrays[Mesh.ARRAY_VERTEX] = out["positions"]
##   var am := ArrayMesh.new()
##   am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
##   # (add_surface_from_arrays needs the full ARRAY_MAX-sized dict.)
## For fat/thin coloring: split by soup["tri_kind"] into two surfaces
## BEFORE commit, or pack kind as a custom attribute per renderer taste.
static func soup_to_mesh_arrays(soup: Dictionary) -> Dictionary:
	var positions: PackedVector3Array = soup.get("positions", PackedVector3Array())
	var tri_kinds: PackedInt32Array = soup.get("tri_kind", PackedInt32Array())
	var n: int = positions.size()
	var bad := PackedVector3Array()
	if n % 3 != 0:
		push_error("soup_to_mesh_arrays: positions count %d is not a multiple of 3; corrupt soup" % n)
		return {"positions": bad, "indices": PackedInt32Array()}
	if tri_kinds.size() != n / 3:
		push_error("soup_to_mesh_arrays: tri_kind count %d != triangle count %d" % [tri_kinds.size(), n / 3])
		return {"positions": bad, "indices": PackedInt32Array()}
	var indices := PackedInt32Array()
	indices.resize(n)
	for i in range(n):
		indices[i] = i
	return {"positions": positions, "indices": indices}


## ---------------------------------------------------------------------------
## Internals


## Convex-quad containment with penrose.gd's boundary convention
## (boundary counts as inside; first candidate wins on shared edges).
static func _point_in_quad(p: Vector2, verts: Array[Vector2]) -> bool:
	var has_neg := false
	var has_pos := false
	for i in range(4):
		var a: Vector2 = verts[i]
		var b: Vector2 = verts[(i + 1) % 4]
		var d: float = (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
		if d < -EPS:
			has_neg = true
		elif d > EPS:
			has_pos = true
	return not (has_neg and has_pos)


static func _tile_within(t: Tile, half_extent: float) -> bool:
	var pad: float = half_extent + 6.0  # dual reach: cells lie within ~5 + edge of their crossing
	for v in t.verts:
		if absf(v.x) > pad or absf(v.y) > pad:
			return false
	return true


## Deterministic quantized vertex key (1e-4 grid).
static func _qkey(v: Vector2) -> String:
	return "%d:%d" % [roundi(v.x / 0.0001), roundi(v.y / 0.0001)]


## Orientation-independent edge key.
static func _edge_key(a: Vector2, b: Vector2) -> String:
	var ka := _qkey(a)
	var kb := _qkey(b)
	if ka < kb:
		return ka + "|" + kb
	return kb + "|" + ka
