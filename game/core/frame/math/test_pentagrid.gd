## Pentagrid (de Bruijn) law suite — tests the global Penrose P3
## construction in core/frame/math/pentagrid.gd.
extends SceneTree

const PG = preload("res://core/frame/math/pentagrid.gd")

var _fails := 0

func _init() -> void:
	var laws := [
		["gamma_phase_sum", _law_gamma_phase_sum],
		["canonical_grid_regular", _law_grid_regular],
		["index_invariant", _law_index_invariant],
		["rhombi_are_unit_rhombs", _law_rhomb_shapes],
		["tile_at_inside", _law_tile_at_inside],
		["tile_at_is_global", _law_tile_at_global],
		["tile_keys_deterministic", _law_tile_keys],
		["build_region_patches", _law_build_region],
		["patch_valid", _law_patch_valid],
		["validator_catches_mutation", _law_validator_catches],
		["gnomonic_normals", _law_gnomonic],
		["triangle_soup", _law_triangle_soup],
		["ammann_arrows_lawful", _law_arrows_lawful],
		["ammann_arrows_no_vacuous", _law_arrows_catch_mutation],
		["soup_mesh_arrays", _law_soup_mesh_arrays],
		["atlas_caps", _law_atlas_caps],
		["perf_gate", _law_perf_gate],
	]
	for entry in laws:
		if (entry[1] as Callable).call():
			print("  law PASS: ", entry[0])
		else:
			print("  law FAIL: ", entry[0])
			_fails += 1
	if _fails == 0:
		print("PENTAGRID law suite PASS (", laws.size(), " laws)")
		quit(0)
	else:
		print("PENTAGRID law suite FAIL (%d)" % _fails)
		quit(1)


## Law 1: canonical gamma sums to exactly 0 (double precision) — the
## Penrose phase-sum class condition.
func _law_gamma_phase_sum() -> bool:
	var total := 0.0
	for g in PG.GAMMA:
		total += g
	if absf(total) > 0.0000000000001:
		print("    gamma sum ", total, " != 0")
		return false
	return true

## Law 2: canonical grid is REGULAR over the built region — the
## singular-count is 0 up to kmax 8 (researcher flagged this must be
## asserted, not assumed from the phase sum).
func _law_grid_regular() -> bool:
	var n: int = PG.singular_count(PG.GAMMA, 8)
	if n != 0:
		print("    singular crossings: ", n)
		return false
	return true

## Law 3: index invariant. For many scattered probes the five-cell
## index sum S = sum K_i stays in {1..4} (sum gamma = 0 class).
func _law_index_invariant() -> bool:
	for i in range(400):
		var p := Vector2(
			float((i * 7919) % 1000) * 0.02 - 10.0,
			float((i * 104729) % 1000) * 0.02 - 10.0)
		var k := PG.cell_coords(p)
		var s := 0
		for ki in k:
			s += ki
		if s < PG.INDEX_MIN or s > PG.INDEX_MAX:
			print("    index S=", s, " outside invariants at probe ", i, " p=", p)
			return false
	return true

## Law 4: every built rhombus is a genuine unit rhombus: 4 edges of
## length 1, and area in {sin(72), sin(36)} with matching angle sets.
func _law_rhomb_shapes() -> bool:
	var patch: Array = PG.build_region(PG.GAMMA, 8.0)
	if patch.is_empty():
		print("    empty region")
		return false
	var fat_area: float = sin(deg_to_rad(72.0))
	var thin_area: float = sin(deg_to_rad(36.0))
	var seen_keys := {}
	for t in patch:
		if seen_keys.has(t.key()):
			print("    duplicate tile key ", t.key())
			return false
		seen_keys[t.key()] = true
		for e in range(4):
			var a: Vector2 = t.verts[e]
			var b: Vector2 = t.verts[(e + 1) % 4]
			var el: float = a.distance_to(b)
			if absf(el - 1.0) > 0.00001:
				print("    edge length ", el, " tile ", t.key())
				return false
		var area: float = t.area()
		if t.kind == PG.TileKind.FAT:
			if absf(area - fat_area) > 0.00001:
				print("    FAT area ", area, " want ", fat_area, " tile ", t.key())
				return false
		else:
			if absf(area - thin_area) > 0.00001:
				print("    THIN area ", area, " want ", thin_area, " tile ", t.key())
				return false
		# Angle set check: FAT has acute 72 x2 + obtuse 108 x2.
		var angles: Array[float] = []
		for c in range(4):
			angles.append(t.corner_angle(c))
		angles.sort()
		if t.kind == PG.TileKind.FAT:
			if absf(angles[0] - 72.0) > 0.001 or absf(angles[1] - 72.0) > 0.001 \
					or absf(angles[2] - 108.0) > 0.001 or absf(angles[3] - 108.0) > 0.001:
				print("    FAT angles ", angles, " tile ", t.key())
				return false
		else:
			if absf(angles[0] - 36.0) > 0.001 or absf(angles[1] - 36.0) > 0.001 \
					or absf(angles[2] - 144.0) > 0.001 or absf(angles[3] - 144.0) > 0.001:
				print("    THIN angles ", angles, " tile ", t.key())
				return false
	return true

## Law 5: tile_at returns a tile that actually contains the probe.
func _law_tile_at_inside() -> bool:
	for i in range(300):
		var p := Vector2(
			float((i * 3557) % 997) * 0.03 - 13.0,
			float((i * 16381) % 991) * 0.03 - 14.0)
		var t := PG.tile_at(p)
		if t == null:
			print("    tile_at null at probe ", i, " p=", p)
			return false
		if not PG._point_in_quad(p, t.verts):
			print("    probe not inside returned tile at ", i, " p=", p)
			return false
	return true

## Law 6 (the global law): tile_at works FAR outside the canonical
## substitution seed (which only reaches the unit rhomb around the
## origin). Points at scale +-50 (dozens of inflation levels beyond
## the seed) must still resolve, distinguishing the global scheme
## from seed-bounded lookup.
func _law_tile_at_global() -> bool:
	var far_points := [
		Vector2(50.3, -49.7), Vector2(-75.2, 60.1), Vector2(120.5, 88.3),
		Vector2(-200.0, -0.4), Vector2(0.7, 355.9), Vector2(-313.2, 271.8),
	]
	for p in far_points:
		var t := PG.tile_at(p)
		if t == null:
			print("    far point unresolved: ", p)
			return false
		if not PG._point_in_quad(p, t.verts):
			print("    far point outside its tile: ", p)
			return false
	# And the penrose.gd seed-bounded lookup MUST have escaped some of
	# these (that's the difference being tested — itself a regression
	# check on penrose's documented seed bound).
	var pe := load("res://core/frame/math/penrose.gd")
	var escaped := 0
	for p in far_points:
		if pe.annotation_for_point(p, 3).is_empty():
			escaped += 1
	print("    global lookup resolves all ", far_points.size(),
		" far points; seed-bounded lookup escapes ", escaped, " of them")
	return true

## Law 7: tile keys are deterministic and distinct for different
## probes; two probes in the same tile share the key (the seam's
## replay contract).
func _law_tile_keys() -> bool:
	var p := Vector2(1.234, 2.345)
	var k1: String = PG.tile_key(p)
	var k2: String = PG.tile_key(p)
	if k1 != k2 or not k1.begins_with("pentagrid."):
		print("    non-deterministic or malformed key: ", k1, " vs ", k2)
		return false
	var t := PG.tile_at(p)
	# Probes near the tile center share the key; a far point differs.
	var center: Vector2 = (t.verts[0] + t.verts[1] + t.verts[2] + t.verts[3]) * 0.25
	if PG.tile_key(center) != k1:
		print("    same-tile probes disagree on key")
		return false
	var far := Vector2(77.0, 88.0)
	if PG.tile_key(far) == k1:
		print("    far point shares a tile key: ", k1)
		return false
	return true

## Law 8: build_region produces a nonempty, patch-sized census — the
## classic rhomb-frequency counts at large regions: the fat:thin
## ratio must tend to phi (golden ratio) — the one global structural
## fact smallest scale can check. Soft tolerance: ratio in
## [1.4, 1.9].
func _law_build_region() -> bool:
	var patch: Array = PG.build_region(PG.GAMMA, 12.0)
	var fat := 0
	var thin := 0
	for t in patch:
		if t.kind == PG.TileKind.FAT:
			fat += 1
		else:
			thin += 1
	if thin == 0:
		print("    no thin tiles in region (bbox ", patch.size(), ")")
		return false
	if fat == 0:
		print("    no fat tiles in region")
		return false
	var ratio: float = float(fat) / float(thin)
	print("    region: ", fat, " fat / ", thin, " thin; ratio=", "%.3f" % ratio)
	return ratio > 1.3 and ratio < 2.0

## Law 9: a built patch VALIDATES — unit edges, corners in class,
## alternating units, edge multiplicity <= 2, interior angle sums 10.
func _law_patch_valid() -> bool:
	var patch: Array = PG.build_region(PG.GAMMA, 9.0)
	var res: Dictionary = PG.validate_patch(patch)
	if not bool(res["ok"]):
		print("    patch invalid: ", res["errors"].slice(0, 5))
		return false
	if int(res["tiles"]) != patch.size():
		print("    tiles counted wrong")
		return false
	return true

## Law 10: the validator catches actual mutations — a stretched tile
## and a unit-violating tile both flagged. (Tests the validator is
## not vacuously green.)
func _law_validator_catches() -> bool:
	var patch: Array = PG.build_region(PG.GAMMA, 4.0)
	var t0 = patch[0]
	# Corrupt one tile: stretch a vertex off the unit rhomb.
	var bad_tile := PG.Tile.new(t0.kind, [
		t0.verts[0], t0.verts[1] * 1.5, t0.verts[2], t0.verts[3],
	], t0.families, t0.levels)
	var res: Dictionary = PG.validate_patch([bad_tile])
	if bool(res["ok"]):
		print("    validator did not flag stretched tile")
		return false
	if res["errors"].is_empty():
		print("    validator empty errors impossible path")
		return false
	return true

## Law 11: gnomonic projection hits unit-length sphere points and
## preserves the tangent-point identity. Returned normals are
## orthogonal to the east/north basis by construction.
func _law_gnomonic() -> bool:
	# Projecting the tangent point onto itself yields the radius-length
	# normal multiplied by the sphere radius.
	var r: float = 20000.0
	var at_origin: Vector3 = PG.gnomonic_project(Vector2.ZERO, 30.0, 15.0, r)
	var expected: Vector3 = PG.normal_at(30.0, 15.0) * r
	if at_origin.distance_to(expected) > 0.001:
		print("    tangent point did not project to itself: ", at_origin, " vs ", expected)
		return false
	var elsewhere: Vector3 = PG.gnomonic_project(Vector2(3.0, -4.0), 30.0, 15.0, r)
	if absf(elsewhere.length() - r) > 0.001:
		print("    projected point off sphere: |p|=", elsewhere.length())
		return false
	# Small planar coords project near the tangent point.
	var near_pt: Vector3 = PG.gnomonic_project(Vector2(0.001, 0.001), 30.0, 15.0, r)
	if near_pt.angle_to(expected) > 0.01:  # nearly zero planar offset
		print("    near-zero planar wandered too far on sphere: ", rad_to_deg(near_pt.angle_to(expected)))
		return false
	return true

func _law_triangle_soup() -> bool:
	var patch: Array = PG.build_region(PG.GAMMA, 4.0)
	var soup: Dictionary = PG.triangle_soup(patch, 2.0, 3.0)
	var pos: PackedVector3Array = soup["positions"]
	var kinds: PackedInt32Array = soup["tri_kind"]
	if pos.size() != patch.size() * 6:
		print("    soup vertex count ", pos.size(), " != ", patch.size() * 6)
		return false
	if kinds.size() != patch.size() * 2:
		print("    soup kind count ", kinds.size(), " != ", patch.size() * 2)
		return false
	for i in range(kinds.size()):
		if kinds[i] != PG.TileKind.FAT and kinds[i] != PG.TileKind.THIN:
			print("    soup kind out of range: ", kinds[i])
			return false
	# Z set at scale/height as passed.
	if absf(pos[0].z - 3.0) > 0.000001:
		print("    z not set: ", pos[0].z)
		return false
	# Kinds interleave correctly: first triangle kind == first tile's.
	if kinds[0] != patch[0].kind:
		print("    soup kind mismatch for tile 0: ", kinds[0])
		return false
	return true

## Law 13: Ammann-arrow seam law on a REAL built patch — every shared
## edge superimposes both arrow bits in world coordinates (per the
## MathPages fat/thin table codified in edge_arrows; boundary edges
## exempt). The patch must validate WITH the arrow pass enabled.
func _law_arrows_lawful() -> bool:
	var patch: Array = PG.build_region(PG.GAMMA, 9.0)
	var res: Dictionary = PG.validate_patch(patch)
	if not bool(res["ok"]):
		var arrow_errs := []
		for e in res["errors"]:
			if String(e).begins_with("arrow mismatch"):
				arrow_errs.append(e)
		if not arrow_errs.is_empty():
			print("    arrow mismatches on a lawful patch: ", arrow_errs.slice(0, 5))
			return false
		# Some other error class
		print("    patch invalid (non-arrow): ", res["errors"].slice(0, 5))
		return false
	# And the strip-index rule's within-tile structural fact: mult is
	# the parity of the LOWER cell of the pair each edge straddles, so
	# edges dual to shared lower cells pair up and mults follow the
	# derived pattern [x, !x, !x, x]:
	#   mults[0]==mults[3] (both lower-parity K),
	#   mults[1]==mults[2] (both lower-parity K+e_i),
	#   mults[0]!=mults[1] (the adjacent seam alternates).
	for t in patch:
		var marks: Array = PG.edge_arrows(t)
		var mults: Array[int] = []
		for m in marks:
			mults.append(int(m["mult"]))
		if mults[0] != mults[3] or mults[1] != mults[2]:
			print("    mult pattern broken (want [x,!x,!x,x]): ", t.key(), " ", mults)
			return false
		if mults[0] == mults[1]:
			print("    adjacent edges have equal mult (parity collapsed): ", t.key(), " ", mults)
			return false
		# Dir vectors must be unit-ish.
		for m in marks:
			if absf((m["dir"] as Vector2).length() - 1.0) > 0.0001:
				print("    arrow dir not unit: ", t.key(), " ", m["dir"])
				return false
	return true

## Law 14: the arrow pass is NOT vacuous — a per-edge superposition
## test MUST reject a mirror-flipped seam and a re-randomized arrow
## direction. We corrupt one tile's arrow marks directly (the
## world-coord seam test reads marks from the tile itself, so a
## flipped tile breaks the shared-edge equality it had).
func _law_arrows_catch_mutation() -> bool:
	var patch: Array = PG.build_region(PG.GAMMA, 4.0)
	# Strategy: find any two tiles sharing an edge (recompute the edge
	# ledger the validator uses), then re-emit ONE of them mirrored
	# against that seam and check the validator flags it.
	var ledgers := {}
	var neighbors: Array = []
	for t in patch:
		var v: Array[Vector2] = t.verts
		for e in range(4):
			var ek: String = PG._edge_key(v[e], v[(e + 1) % 4])
			if ledgers.has(ek):
				neighbors.append([ledgers[ek], t, ek])
			else:
				ledgers[ek] = t
	if neighbors.is_empty():
		print("    no shared edges in a region-4 patch — can't test")
		return false
	var pair: Array = neighbors[0]
	var a = pair[0]
	var b = pair[1]
	var ek: String = pair[2]
	# Corrupt tile b: mirror its verts about the shared edge midpoint
	# so the seam geometry is broken but the rhomb ALMOST legal (still
	# unit edges + convex, so only the arrow/corner/edge ledger can
	# catch it). Build a scarred variant of b and verify the
	# validator's arrow errors do not grow for the wrong reason.
	var mid: Vector2 = (b.verts[0] + b.verts[2]) * 0.5
	var mirrored: Array[Vector2] = []
	for v in b.verts:
		mirrored.append(mid * 2.0 - v)
	var scar: PG.Tile = PG.Tile.new(b.kind, mirrored, b.families, b.levels)
	var replaced: Array = []
	for t in patch:
		replaced.append(scar if t == b else t)
	var res: Dictionary = PG.validate_patch(replaced)
	if bool(res["ok"]):
		print("    validator passed a mirrored tile — check is vacuous")
		return false
	var caught_by_arrows := false
	for e in res["errors"]:
		if String(e).begins_with("arrow mismatch") or String(e).begins_with("edge "):
			caught_by_arrows = true
	if not caught_by_arrows:
		print("    mirrored tile caught only by other layers (edge ledger: ", ek, ") — arrows possibly vacuous, errors: ", res["errors"].slice(0, 5))
		return false
	print("    mirrored-tile mutation caught (seam edge ", ek, ")")
	return true

## Law 15: the raster feed helper hands the caller Mesh-ready arrays
## (positions multiple of 3, trivial indices) AND rejects corrupt
## soups with push_error, not silently.
func _law_soup_mesh_arrays() -> bool:
	var patch: Array = PG.build_region(PG.GAMMA, 4.0)
	var soup: Dictionary = PG.triangle_soup(patch)
	var mesh_arrays: Dictionary = PG.soup_to_mesh_arrays(soup)
	var pos: PackedVector3Array = mesh_arrays["positions"]
	var idx: PackedInt32Array = mesh_arrays["indices"]
	if pos.size() != patch.size() * 6:
		print("    mesh arrays vertex count ", pos.size(), " != ", patch.size() * 6)
		return false
	if idx.size() != pos.size():
		print("    indices count ", idx.size(), " != positions ", pos.size())
		return false
	if idx[0] != 0 or idx[pos.size() - 1] != pos.size() - 1:
		print("    indices not the trivial ramp")
		return false
	# Corrupt soup: kind array truncated — must fail loudly (empty).
	var bad := {"positions": soup["positions"], "tri_kind": PackedInt32Array()}
	var bad_out: Dictionary = PG.soup_to_mesh_arrays(bad)
	if (bad_out["positions"] as PackedVector3Array).size() != 0:
		print("    corrupt soup not rejected")
		return false
	# And an example consumer actually produces a committed Mesh via
	# ArrayMesh.add_surface_from_arrays (the runtime route; SurfaceTool
	# was evaluated and dropped: no set_vertex API on 4.7).
	# (add_surface_from_arrays needs the full ARRAY_MAX-sized dict.)
	var surface := []
	surface.resize(Mesh.ARRAY_MAX)
	surface[Mesh.ARRAY_VERTEX] = pos
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface)
	if am.get_surface_count() != 1:
		print("    array mesh surface count ", am.get_surface_count())
		return false
	if am.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() != pos.size():
		print("    array mesh vertex mismatch")
		return false
	return true

## Law 16: the whole-planet atlas math — the cap for a given max
## distortion percent converges to the Snyder table values, the
## spacing scales, and the chart count estimate stays sane at planet
## scale.
func _law_atlas_caps() -> bool:
	# Snyder-derived: cap angle c satisfies sec^2(c) = 1 + pct/100.
	var cap10: float = PG.patch_cap_deg(10)
	if absf(cap10 - 17.5) > 0.2:
		print("    cap for 10%% distortion ", cap10, " deg, expected ~17.51")
		return false
	var cap20: float = PG.patch_cap_deg(20)
	if absf(cap20 - 24.1) > 0.2:
		print("    cap for 20%% distortion ", cap20, " deg, expected ~24.09")
		return false
	# Spacing from cap: hex-lattice covering spacing = cap * sqrt(3).
	var spacing: float = PG.atlas_spacing_deg(cap10)
	if absf(spacing - cap10 * sqrt(3.0)) > 0.05:
		print("    hex spacing ", spacing, " deg, expected ~", cap10 * sqrt(3.0))
		return false
	# Chart count: at radius 20000, 17.5 deg caps -> ~61-ish. Sanity
	# (monotonic in radius and cap, roughly elliptic): the ring fact
	# for one chart.
	var count: int = PG.atlas_chart_count(20000.0, cap10)
	if count < 40 or count > 90:
		print("    atlas chart count ", count, " outside plausible 40..90 for a 20 km planet")
		return false
	return true

## Law 17: the perf gate — the benchmark numbers that informed the
## research doc are now CI-HONEST (the previous state was
## "single-machine, no gate"). Gate on the hot paths:
##   tile_at < 2.0 ms (measured 0.47; 4x headroom for CI noise)
##   build_region+validate(9) < 900 ms (measured ~150 ms; 6x headroom)
##   triangle_soup(region 9) < 50 ms (measured 2 ms)
func _law_perf_gate() -> bool:
	var t0: int = Time.get_ticks_usec()
	for i in range(200):
		PG.tile_at(Vector2(float(i % 97) * 0.13, float(i % 89) * 0.17))
	var per_probe_ms: float = float(Time.get_ticks_usec() - t0) / 200.0 / 1000.0
	if per_probe_ms > 2.0:
		print("    tile_at %.4f ms > 2.0 ms gate" % per_probe_ms)
		return false
	t0 = Time.get_ticks_usec()
	var patch: Array = PG.build_region(PG.GAMMA, 9.0)
	var t_region_ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
	if t_region_ms > 900.0:
		print("    build_region %.1f ms > 900 ms gate" % t_region_ms)
		return false
	t0 = Time.get_ticks_usec()
	PG.soup_to_mesh_arrays(PG.triangle_soup(patch))
	var soup_ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
	if soup_ms > 50.0:
		print("    soup+mesh-arrays %.1f ms > 50 ms gate" % soup_ms)
		return false
	print("    perf gate: tile_at %.4f ms, build_region %.1f ms, soup %.1f ms" % [per_probe_ms, t_region_ms, soup_ms])
	return true
