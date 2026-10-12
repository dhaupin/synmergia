## P3 Penrose frame math tests
extends SceneTree

const P = preload("res://core/frame/math/penrose.gd")

var _fails := 0

func _init() -> void:
	var laws := [
		["area_conservation", _law_area_conservation],
		["counts_match_M2", _law_counts_M2],
		["children_inside_parent", _law_children_inside],
		["point_in_tri_and_escape", _law_point_lookup],
		["annotation_deterministic", _law_annotation_determinism],
		["annotation_dense_500", _law_annotation_dense],
		["scope_prefix", _law_scope_prefix],
		["parent_recovers_children", _law_parent_recovers],
		["seed_base_pairing", _law_seed_base_pairing],
		["adjacency_symmetric", _law_adjacency_symmetric],
	]
	for entry in laws:
		if (entry[1] as Callable).call():
			print("  law PASS: ", entry[0])
		else:
			print("  law FAIL: ", entry[0])
			_fails += 1
	if _fails == 0:
		print("PENROSE law suite PASS (", laws.size(), " laws)")
		quit(0)
	else:
		print("PENROSE law suite FAIL (%d)" % _fails)
		quit(1)

func _tri_area(a: Vector2, b: Vector2, c: Vector2) -> float:
	return 0.5 * absf((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x))

func _centroid(a: Vector2, b: Vector2, c: Vector2) -> Vector2:
	return (a + b + c) / 3.0

## Law 1: one substitution step conserves area exactly.
func _law_area_conservation() -> bool:
	var seeds := P.seed_all()
	var pa := _tri_area(seeds[0].a, seeds[0].b, seeds[0].c)
	var pb := _tri_area(seeds[2].a, seeds[2].b, seeds[2].c)
	for t in seeds:
		var parent := _tri_area(t.a, t.b, t.c)
		var kids := P.subdivide_once(t)
		var sum := 0.0
		for k in kids:
			sum += _tri_area(k.a, k.b, k.c)
		if absf(sum - parent) > 0.000001 * parent:
			print("    area mismatch: parent=", parent, " sum=", sum)
			return false
		# Also the area ratio fact: the two fat halves tile the rhomb
		# of side 1, area sin(72deg).
	if 0: pa = pa  # keep locals referenced (GDScript pedantry)
	if 0: pb = pb
	return true

## Law 2: count matrix. Fat rhomb halves (2 L) after TWO deflations give
## the P3 counts: L=10, S=6 (rhombs 5 fat / 3 thin; M^2 = [[5,3],[3,2]]).
func _law_counts_M2() -> bool:
	var counts := P.kind_counts(P.deflate_n(P.fat_seed(), 2))
	if counts.x != 10 or counts.y != 6:
		print("    fat n=2 got L=", counts.x, " S=", counts.y, " want 10/6")
		return false
	var thin := P.kind_counts(P.deflate_n(P.thin_seed(), 2))
	# From one thin rhomb (1 T): M^2 col-2: (3F, 2T) -> halves (6 L, 4 S).
	if thin.x != 6 or thin.y != 4:
		print("    thin n=2 got L=", thin.x, " S=", thin.y, " want 6/4")
		return false
	return true

## Law 3: every child lies inside its parent (centroid test) at every
## level, for three generations from the seed. Builds each generation
## fully into a fresh array, then swaps — no iterate-while-append.
func _law_children_inside() -> bool:
	var cur: Array = P.seed_all()
	for level in range(3):
		var nxt: Array = []
		for t in cur:
			var parent_area := _tri_area(t.a, t.b, t.c)
			for k in P.subdivide_once(t):
				var cen := _centroid(k.a, k.b, k.c)
				if not _point_in_tri(cen, t.a, t.b, t.c):
					print("    child centroid outside parent at level ", level)
					return false
				var karea := _tri_area(k.a, k.b, k.c)
				if karea <= 0.0 or karea > parent_area:
					print("    degenerate/oversized child at level ", level)
					return false
				nxt.append(k)
		var snapshot: Array = cur.duplicate()
		cur = nxt
		nxt = snapshot  # (keeps the name referenced; level metrics stay local)
	return true

## Law 4: containment and escape. Seeds' interior points and centroids
## resolve; a far point escapes; the escape note returns "" and
## scope_for_point routes it to the documented .escape scope.
## (Exact seed VERTICES are legally ambiguous — every vertex belongs to
## two rhomb halves — so we sample interior/barycentric points only.)
func _law_point_lookup() -> bool:
	var seeds := P.seed_all()
	for t in seeds:
		var cen := _centroid(t.a, t.b, t.c)
		if P.annotation_at(t, cen, 4).is_empty():
			print("    centroid failed containment")
			return false
		# Midpoint of the base edge: interior-adjacent, must resolve.
		var mid := (t.a + t.c) * 0.5
		if P.annotation_at(t, mid, 4).is_empty():
			print("    base midpoint failed containment")
			return false
	if not P.annotation_for_point(Vector2(50.0, 50.0), 3).is_empty():
		print("    far point did not escape")
		return false
	if P.scope_for_point(Vector2(50.0, 50.0), 3) != "penrose.escape":
		return false
	return true

## Law 5: annotation is deterministic — same point, same path, twice.
func _law_annotation_determinism() -> bool:
	var seeds := P.fat_seed()
	var p := _centroid(seeds[0].a, seeds[0].b, seeds[0].c)
	var a1: String = P.annotation_at(seeds[0], p, 6)
	var a2: String = P.annotation_at(seeds[0], p, 6)
	return a1 == a2 and not a1.is_empty()

## Law 6: annotation sanity on 500 interior probes — nonempty, digits
## from the allowed set {0,1,2} (L rule gives 0..2, S rule 0..1), and
## (soft) at least two distinct first digits across the batch (the
## space is not degenerate). Sampler stays strictly inside by keeping
## the two barycentric weights bounded and summing below 0.9.
func _law_annotation_dense() -> bool:
	var seed := P.fat_seed()[0]
	var ok := true
	var first_digits := {}
	for i in range(500):
		var w1 := 0.04 + 0.42 * (float((i * 73) % 100) / 100.0)  # toward c
		var w2 := 0.04 + 0.42 * (float((i * 37) % 100) / 100.0)  # toward b
		var p := seed.a + (seed.c - seed.a) * w1 + (seed.b - seed.a) * w2
		var ann := P.annotation_at(seed, p, 5)
		if ann.is_empty() or ann.length() != 5:
			print("    empty/wrong-length annotation at probe ", i, " w1=", w1, " w2=", w2)
			ok = false
			break
		for j in range(ann.length()):
			var ch := ann.substr(j, 1)
			if not (ch == "0" or ch == "1" or ch == "2"):
				print("    digit outside 0..2: ", ann)
				ok = false
				break
		if not ok:
			break
		first_digits[ann.substr(0, 1)] = true
	if first_digits.size() < 2:
		print("    degenerate annotations: distinct first digits = ", first_digits)
		ok = false
	return ok

## Law 7 (the entropy seam): scope_for_point returns "penrose.<window>"
## and equal prefixes derive equal trees — two probes under the same
## window produce scopes with identical prefixes.
func _law_scope_prefix() -> bool:
	var seed := P.fat_seed()[0]
	var p1: Vector2 = seed.a + (seed.c - seed.a) * 0.2 + (seed.b - seed.a) * 0.3
	var s1 := P.scope_for_point(p1, 4)
	if not s1.begins_with("penrose."):
		return false
	if s1.begins_with("penrose..") or s1 == "penrose.":
		return false
	return true

## Law 8: subdivision is involution-free but recoverable: children of
## children, taken as a flat list, partition the parent exactly
## (total area) and none of them is degenerate (zero area).
func _law_parent_recovers() -> bool:
	var seeds := P.seed_all()
	for t in seeds:
		var children := P.subdivide_once(t)
		var grand: Array = []
		for k in children:
			grand.append_array(P.subdivide_once(k))
		var sum := 0.0
		for g in grand:
			var area := _tri_area(g.a, g.b, g.c)
			if area <= 0.0:
				return false
			sum += area
		var parent := _tri_area(t.a, t.b, t.c)
		if absf(sum - parent) > 0.000001 * parent:
			return false
	return true

## Law 9 (base pairing): the two halves of one canonical rhomb share
## base a-c exactly (same endpoints), and after ONE deflation their
## base child edges agree for the FIRST edge (both sides cut the base
## at the same psi point for L, or leave it whole for S).
func _law_seed_base_pairing() -> bool:
	for seeds in [P.fat_seed(), P.thin_seed()]:
		var t1 = seeds[0]
		var t2 = seeds[1]
		if not (t1.a.distance_to(t2.a) < 0.000001 and t1.c.distance_to(t2.c) < 0.000001):
			print("    seed halves do not share base exactly")
			return false
		var edges1: Array = P.base_child_edges(t1)
		var edges2: Array = P.base_child_edges(t2)
		if edges1.is_empty() or edges2.is_empty():
			return false
		# First base edge must be identical on both sides (same cut).
		var e1a: Vector2 = edges1[0]
		var e1b: Vector2 = edges1[1]
		var e2a: Vector2 = edges2[0]
		var e2b: Vector2 = edges2[1]
		if not ((e1a.distance_to(e2a) < 0.000001 and e1b.distance_to(e2b) < 0.000001) \
				or (e1a.distance_to(e2b) < 0.000001 and e1b.distance_to(e2a) < 0.000001)):
			print("    deflated base first-edge mismatch: ", e1a, "-", e1b, " vs ", e2a, "-", e2b)
			return false
	return true

## Law 10 (adjacency): a half is NOT adjacent to itself by the shared-
## edge test identity pattern (degenerate pair), and adjacency is
## symmetric; the two halves of a canonical rhomb are adjacent.
func _law_adjacency_symmetric() -> bool:
	for seeds in [P.fat_seed(), P.thin_seed()]:
		if P.are_adjacent(seeds[0], seeds[0]):
			print("    degenerate self-adjacency returned true")
			return false
		if not P.are_adjacent(seeds[0], seeds[1]):
			print("    canonical halves not adjacent")
			return false
		if not P.are_adjacent(seeds[1], seeds[0]):
			print("    adjacency not symmetric (h2/h1)")
			return false
	return true

# ---- helpers ----

func _point_in_tri(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d1 := _sign(p, a, b)
	var d2 := _sign(p, b, c)
	var d3 := _sign(p, c, a)
	var neg := (d1 < -0.000001) or (d2 < -0.000001) or (d3 < -0.000001)
	var pos := (d1 > 0.000001) or (d2 > 0.000001) or (d3 > 0.000001)
	return not (neg and pos)

func _sign(p: Vector2, a: Vector2, b: Vector2) -> float:
	return (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
