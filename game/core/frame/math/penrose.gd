## Penrose P3 math (frame primitive) — the aperiodic address space.
##
## Ported from the canonical P3 rhomb substitution (Tilings Encyclopedia's
## Penrose-rhomb entry, tilings.math.uni-bielefeld.de/substitution/penrose-rhomb/),
## implemented as the equivalent Robinson-triangle subdivision used for the
## executable form. Vant lineage: lib/geometry/tilings.js never shipped into
## synmergia; this is the math that would have backed it.
##
## Design (labs/world-building-research.md sec 1):
## - Two prototile half-triangles: L (large obtuse, sides 1,1,phi) and
##   S (small acute, sides 1,1,psi=1/phi). Vertices are stored in a
##   SEMANTIC order (A,C base endpoints; B apex) — never sorted; the
##   mirrored child rule is applied to mirrored parents, so handedness
##   survives every generation.
## - One substitution step:
##     L -> L, S, L   (D = A + psi*(C-A), E = A + psi*(B-A))
##     S -> S, L      (D = A + psi^2*(B-A))
##   Child counts (2,1 / 1,1) = the P3 rhomb count matrix; eigenvalue
##   phi^2 area per step, the linear inflation factor is phi.
## - point_to_tile uses RECURSIVE DEFLATION: start from a containing
##   ancestor triangle handed to you, subdivide once, keep only the
##   containing child, repeat until below tolerance. O(levels) child
##   tests; no patch index required.
## - Each tile carries an ANNOTATION: one decimal digit per deflation
##   step. The digit is the containing child's index within its parent's
##   substitution rule (0,1,2 for L -> [L,S,L]; 0,1 for S -> [S,L]), so
##   adjacent tiles carry related annotations — which is what makes
##   annotation strings usable as deterministic rng scope keys
##   ("windows").
##
## Constants are exact golden algebra:
##   phi = (1+sqrt(5))/2, cos(36) = phi/2, cos(72) = psi/2.
##
## Frame primitive: NO autoload, NO class_name, NO GameManager dependency.
##
## Research companion: cite labs/world-building-research.md sec 1 and
## labs/prd-geometry.md.
extends RefCounted

## Golden-ratio base facts, exact to double precision.
const PHI: float = 1.618033988749895  # (1+sqrt(5)) / 2
const PSI: float = 0.6180339887498949  # 1 / phi
const PSI2: float = 0.38196601125010515  # psi * psi = 1 - psi

## C Is constant for the two canonical rhombus angles.
const COS36: float = 0.8090169943749475   # phi / 2
const COS72: float = 0.30901699437494745  # psi / 2
const SIN36: float = 0.5877852522924731
const SIN72: float = 0.9510565162951535

## One P3 step from a unit rhomb: linear inflation factor is phi
## (area phi^2). Kept as named constants for docs/tests.
const INFLATION_LINEAR: float = PHI
const INFLATION_AREA: float = PHI * PHI

## Margin used for point-in-triangle tests; triangles can share edges,
## so tiny slop prevents "on none" returns for the shared-border case.
const _EDGE_EPS: float = 0.000001

enum TriKind { L, S }


## Half-triangle value type in semantic order (A,C base endpoints; B apex).
## Plain Dictionary keeps it frame-serializable:
##   {"k": TriKind, "a": Vector2, "b": Vector2, "c": Vector2, "m": bool mirror}
## "m" marks the MIRRORED (face-down) instance; the mirror consults the
## same stored order of A,B,C but subdivides with the mirrored rule —

class Triangle:
	var k: int
	var a: Vector2
	var b: Vector2
	var c: Vector2
	var mirrored: bool

	func _init(k_in: int, a_in: Vector2, b_in: Vector2, c_in: Vector2, mirrored_in: bool = false) -> void:
		k = k_in
		a = a_in
		b = b_in
		c = c_in
		mirrored = mirrored_in


## A tile address: annotation string + mirror flag for identity checks.
class TileRef:
	var annotation: String
	var mirrored: bool

	func _init(annotation_in: String, mirrored_in: bool) -> void:
		annotation = annotation_in
		mirrored = mirrored_in

	func key() -> String:
		return annotation + ("*" if mirrored else "")


## ---------------------------------------------------------------------------
## Seed geometry


## Canonical unit fat rhomb, vertices 0,U,U+V,V with V=e^(i*72deg),
## split along its LONG diagonal (U .. U+V if drawn with O at 0 —
## geometrically the diagonal through the obtuse tip pair). We cut
## along the U-to-(O+V) diagonal, giving two L halves that share base
## a-c = (U, O+V) exactly:
##   half 1: a=U, b=O,   c=O+V
##   half 2: a=U, b=U+V, c=O+V
static func fat_seed() -> Array[Triangle]:
	var v := Vector2(COS72, SIN72)
	var o := _o2()
	var u := _u2()
	var ov: Vector2 = o + v
	var uv: Vector2 = u + v
	return [
		Triangle.new(TriKind.L, u, o, ov),
		Triangle.new(TriKind.L, u, uv, ov),
	]


## Canonical unit thin rhomb, vertices U,O,U+V,V with V=e^(i*36deg),
## split along its SHORT diagonal (U .. V), giving two S halves that
## share base a-c = (U, V) exactly:
##   half 1: a=U, b=O,   c=V
##   half 2: a=U, b=U+V, c=V
static func thin_seed() -> Array[Triangle]:
	var v := Vector2(COS36, SIN36)
	var u := _u2()
	var o := _o2()
	var uv: Vector2 = u + v
	return [
		Triangle.new(TriKind.S, u, o, v),
		Triangle.new(TriKind.S, u, uv, v),
	]


## Full canonical seed set (fat + thin rhombs, each as its two halves),
## ordered by law-suite convention: [fat L1, fat L2, thin S1, thin S2].
static func seed_all() -> Array[Triangle]:
	var out: Array[Triangle] = []
	out.append_array(fat_seed())
	out.append_array(thin_seed())
	return out


## ---------------------------------------------------------------------------
## Substitution (one step)


## Subdivide one Robinson triangle once. Child order is exact per kind:
##   L -> [L, S, L]
##   S -> [S, L]
## every child scaled by linear factor psi. Mirrored parents use the
## mirrored rule (reflections swap the psi weights' attachment), which is
## how handedness propagates generation after generation.
static func subdivide_once(t: Triangle) -> Array[Triangle]:
	var out: Array[Triangle] = []
	if t.k == TriKind.L:
		var d: Vector2 = _lerp2(t.a, t.c, PSI)
		var e: Vector2 = _lerp2(t.a, t.b, PSI)
		out.append(Triangle.new(TriKind.L, d, e, t.a, t.mirrored))
		out.append(Triangle.new(TriKind.S, d, e, t.b, t.mirrored))
		out.append(Triangle.new(TriKind.L, t.c, d, t.b, t.mirrored))
	else:
		var d: Vector2 = _lerp2(t.a, t.b, PSI2)
		out.append(Triangle.new(TriKind.S, d, t.c, t.a, t.mirrored))
		out.append(Triangle.new(TriKind.L, t.c, d, t.b, t.mirrored))
	return out


## Subdivide parents n times (n>=0).
static func deflate_n(tris: Array[Triangle], n: int) -> Array[Triangle]:
	var cur: Array[Triangle] = tris
	for _i in range(maxi(n, 0)):
		var nxt: Array[Triangle] = []
		for t in cur:
			nxt.append_array(subdivide_once(t))
		cur = nxt
	return cur


## ---------------------------------------------------------------------------
## Point-to-tile: recursive deflation


## Walk deflation down from `start` to the child triangle containing
## point `p` at `levels` depth. Returns the annotation of the leaf
## (one code per level; see below) or "" if p escapes the start triangle.
##
## Annotation codes per level: the containing child's index within the
## parent's rule (see subdivide_once), one digit per level. Two points
## under the same window share every interior rng prefix derived from
## that window — this is the address scheme scope_for_point() serves.
static func annotation_at(start: Triangle, p: Vector2, levels: int) -> String:
	var digits: Array[int] = []
	var cur: Triangle = start
	for _i in range(maxi(levels, 0)):
		var children := subdivide_once(cur)
		var hit: int = -1
		for ci in range(children.size()):
			if _point_in_tri(p, children[ci].a, children[ci].b, children[ci].c):
				hit = ci
				break
		if hit < 0:
			return ""
		digits.append(hit)
		cur = children[hit]
	return _digits_to_string(digits)


## Convenience: annotation for the canonical fat-rhomb half-triangle 0
## (the standard "start anywhere" entry point used by callers without
## a preference).
static func annotation_for_point(p: Vector2, levels: int) -> String:
	var seeds := fat_seed()
	return annotation_at(seeds[0], p, levels)


## ---------------------------------------------------------------------------
## Scope keys (the aperiodic rng seam)


## Dot-scope inside the annotation hierarchy: "penrose.<window>".
## Two coordinates under the same window share the whole tree's
## intermediate rng below that window, which is the point: deterministic,
## scoped replay from (pool, window) alone. Points that escape the seed
## triangle route to the documented "penrose.escape" scope (never ""),
## so every roll resolves even outside the constructed patch.
static func scope_for_point(p: Vector2, levels: int = 6) -> String:
	var win := annotation_for_point(p, levels)
	if win.is_empty():
		return "penrose.escape"
	return "penrose." + win


## ---------------------------------------------------------------------------
## Neighborhood


## The 36-degree spoke count (pentagrid), for callers that cut over to
## the de Bruijn / cut-and-project lookups.
const PENTAGRID_SPOKES: int = 5
const PENTAGRID_SPOKE_DEG: float = 36.0


## Determine whether two tiles share a base edge (adjacency proxy for
## region-local queries; more refined pairs come from matching rules).
static func tri_shared_base(t1: Triangle, t2: Triangle) -> bool:
	return _edge_matches(t1.a, t1.c, t2.a, t2.c)


## Adjacency: two triangles are adjacent iff they share a non-degenerate
## edge (any pair of their three edges must be equal up to orientation).
## A triangle is never adjacent to itself, even though its edges
## trivially "match" — the identity pair is excluded up front.
## Symmetric by construction: are_adjacent(t1, t2) == are_adjacent(t2, t1).
static func are_adjacent(t1: Triangle, t2: Triangle) -> bool:
	if t1 == t2:
		return false
	if _identical_vertices(t1, t2):
		return false
	if _edge_matches(t1.a, t1.c, t2.a, t2.c) or _edge_matches(t1.a, t1.c, t2.b, t2.c) \
			or _edge_matches(t1.a, t1.c, t2.a, t2.b):
		return true
	if _edge_matches(t1.a, t1.b, t2.a, t2.c) or _edge_matches(t1.a, t1.b, t2.b, t2.c) \
			or _edge_matches(t1.a, t1.b, t2.a, t2.b):
		return true
	return _edge_matches(t1.b, t1.c, t2.a, t2.c) or _edge_matches(t1.b, t1.c, t2.b, t2.c) \
		or _edge_matches(t1.b, t1.c, t2.a, t2.b)


## The edge segments that appear along base a-c after ONE deflation of
## `t`. For a straight parent both sides of the shared base cut it the
## same way, so two rhomb halves sharing base a-c keep matching edges.
## Returns Array of Vector2 pairs flattened [p0a, p0b, p1a, p1b, ...].
static func base_child_edges(t: Triangle) -> Array:
	var out: Array = []
	if t.k == TriKind.L:
		# L rule cuts the base at D = a + psi*(c - a): two child edges
		# along the base in every generation — (a, d) and (d, c).
		var d: Vector2 = _lerp2(t.a, t.c, PSI)
		out.append_array([t.a, d])
		out.append_array([d, t.c])
	else:
		# S rule: D is on the a-b leg, NOT on the base, so the base
		# passes through child 0 whole — one edge per generation with
		# the same endpoints (a, c).
		out.append_array([t.a, t.c])
	return out


## Count L and S in a triangle list.
static func kind_counts(tris: Array[Triangle]) -> Vector2i:
	var lcount := 0
	var scount := 0
	for t in tris:
		if t.k == TriKind.L:
			lcount += 1
		else:
			scount += 1
	return Vector2i(lcount, scount)


## ---------------------------------------------------------------------------
## Internals


static func _lerp2(p: Vector2, q: Vector2, t: float) -> Vector2:
	return p + (q - p) * t


static func _u2() -> Vector2:
	return Vector2(1.0, 0.0)


static func _o2() -> Vector2:
	return Vector2.ZERO


## Boundary-consistent point-in-triangle: strict interior with epsilon
## slop against coordinate funnies; a point exactly on a shared edge
## deterministically resolves to the first candidate that reports it.
static func _point_in_tri(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d1: float = _sign(p, a, b)
	var d2: float = _sign(p, b, c)
	var d3: float = _sign(p, c, a)
	var has_neg: bool = (d1 < -_EDGE_EPS) or (d2 < -_EDGE_EPS) or (d3 < -_EDGE_EPS)
	var has_pos: bool = (d1 > _EDGE_EPS) or (d2 > _EDGE_EPS) or (d3 > _EDGE_EPS)
	return not (has_neg and has_pos)


static func _sign(p: Vector2, a: Vector2, b: Vector2) -> float:
	return (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)


static func _edge_matches(a1: Vector2, b1: Vector2, a2: Vector2, b2: Vector2) -> bool:
	return (a1.distance_to(a2) < 0.0001 and b1.distance_to(b2) < 0.0001) \
		or (a1.distance_to(b2) < 0.0001 and b1.distance_to(a2) < 0.0001)


## Two distinct Triangle instances play the same three vertices (e.g.
## the literal same seed asked twice) — treat as "self", not neighbors.
static func _identical_vertices(t1: Triangle, t2: Triangle) -> bool:
	return _edge_matches(t1.a, t1.c, t2.a, t2.c) \
		and _edge_matches(t1.a, t1.b, t2.a, t2.b) \
		and _edge_matches(t1.b, t1.c, t2.b, t2.c)


static func _digits_to_string(digits: Array[int]) -> String:
	var s := ""
	for d in digits:
		s += str(d)
	return s
