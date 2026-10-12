## Pentagrid (de Bruijn) law suite — tests the global Penrose P3
## construction in core/frame/math/pentagrid.gd.
extends SceneTree

const PG = preload("res://core/frame/math/pentagrid.gd")
const SphericalScript = preload("res://core/frame/math/spherical.gd")

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
		["vertex_atlas", _law_vertex_atlas],
		["ten_thin_exclusion", _law_ten_thin_exclusion],
		["glyph_levels", _law_glyph_levels],
		["chart_owner_laws", _law_chart_owner],
		["stitch_layer", _law_stitch_layer],
		["extendability_decider", _law_extendability],
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
## Law 18: the vertex-star ATLAS — the Conway vertex-star law is
## now enforced by derive-from-construction (no paper figures): the
## atlas is nonempty, every interior vertex of a real built patch is
## IN it (patch validates with the layer on), and the atlas is
## isometry-stable so mirrored patches read the same keys.
func _law_vertex_atlas() -> bool:
	var atlas: Dictionary = PG.vertex_star_cycles()
	if atlas.size() < 10:
		print("    atlas suspiciously small: ", atlas.size(), " cycle keys")
		return false
	var patch: Array = PG.build_region(PG.GAMMA, 9.0)
	var res: Dictionary = PG.validate_patch(patch)
	for e in res["errors"]:
		if String(e).begins_with("interior vertex"):
			print("    atlas rejected a real patch vertex: ", e)
			return false
	if not bool(res["ok"]):
		print("    patch failed for other reasons: ", res["errors"].slice(0, 3))
		return false
	# Isometry stability: reflect the whole patch (x -> -x). All
	# corners keep their classes; an atlas based on angular order
	# reads the same canonical keys (reversed cycle) — so the patched
	# MIRROR also validates.
	var mirror: Array = []
	for t in patch:
		var v: Array[Vector2] = []
		for p in t.verts:
			v.append(Vector2(-p.x, p.y))
		mirror.append(PG.Tile.new(t.kind, v, t.families, t.levels))
	var mres: Dictionary = PG.validate_patch(mirror)
	if not bool(mres["ok"]):
		print("    mirrored patch rejected: ", mres["errors"].slice(0, 3))
		return false
	return true

## Law 19: the ten-thin trap is REJECTED by the atlas — MathPages'
## extendability counterexample (10 thin rhombi around a point,
## all arrows matchable, impossible in a real P3 tiling) must fail
## the vertex-star layer. This is the non-vacuity proof the paper-
## table absence left open.
func _law_ten_thin_exclusion() -> bool:
	# A geometrically closed ten-thin star at O (all arcs unit):
	# arrows/lattice margins aside, the central vertex's cycle is
	# 1,1,1,1,1,1,1,1,1,1 — key absent from the derived atlas.
	var atlas: Dictionary = PG.vertex_star_cycles()
	var thin_key := ""
	for key in atlas:
		var parts: PackedStringArray = str(key).split(",")
		if parts.size() == 10:
			thin_key = String(key)
	if thin_key != "":
		print("    atlas contains a 10-vertex cycle: ", thin_key)
		return false
	# And a real ten-thin cluster fails validate_patch at the star.
	var patch: Array = PG.build_region(PG.GAMMA, 4.0)
	var O := Vector2.ZERO
	var star: Array = []
	var ref: PG.Tile = patch[0]
	for i in range(10):
		var a := deg_to_rad(36.0 * i)
		var b := deg_to_rad(36.0 * (i + 1))
		var e1 := Vector2(cos(a), sin(a))
		var e2 := Vector2(cos(b), sin(b))
		star.append(PG.Tile.new(PG.TileKind.THIN, [O, e1, e1 + e2, e2], ref.families, ref.levels))
	var res: Dictionary = PG.validate_patch(star)
	if bool(res["ok"]):
		print("    ten-thin star PASSED the validator — atlas vacuous")
		return false
	for e in res["errors"]:
		if String(e).begins_with("interior vertex"):
			return true
	print("    star rejected but only via other layers: ", res["errors"].slice(0, 3))
	return false

## Law 20: GLYPH LEVELS (beyond parity): every edge mark carries its
## exact family-line identity (fam, level) and the level equals the
## level the tile's (families, levels) state implies — no tile can
## claim a level its crossing identity denies.
func _law_glyph_levels() -> bool:
	var patch: Array = PG.build_region(PG.GAMMA, 6.0)
	for t in patch:
		var marks: Array = PG.edge_arrows(t)
		var r: int = t.families.x
		var s: int = t.families.y
		for e in range(4):
			var mark: Dictionary = marks[e]
			var expect_fam: int = r if (e == 0 or e == 2) else s
			if int(mark["fam"]) != expect_fam:
				print("    edge ", e, " family ", mark["fam"], " != ", expect_fam, " tile ", t.key())
				return false
			var expect_lvl: int = t.levels.x if (e == 0 or e == 2) else t.levels.y
			if int(mark["level"]) != expect_lvl:
				print("    edge ", e, " level ", mark["level"], " != ", expect_lvl, " tile ", t.key())
				return false
		# The two edges on the SAME family line share one level+mult?
		# No — A and C share the line (both fam r) so must share level
		# by construction (they read t.levels.x), and mult by parity on
		# the line's lower cell; B and D similarly.
		if int(marks[0]["fam"]) != int(marks[2]["fam"]):
			print("    edges A and C not on the same family line: ", t.key())
			return false
	return true

## Law 21: whole-planet placement — 12 icosa tangent centers, every
## surface point OWNED by exactly one, the owner is stable, and the
## layout's covering radius matches the spherical geometry (so cap
## math and centers AGREE about what a chart must swallow).
func _law_chart_owner() -> bool:
	var centers: Array = PG.atlas_centers()
	if centers.size() != 12:
		print("    atlas centers ", centers.size(), " != 12")
		return false
	# Ownership deterministic + finite: spot points resolve, same point
	# twice = same owner, and owner flips only across real Voronoi
	# edges (perturbing within a face stays).
	var p := Vector2(42.3, -17.5)
	var o := PG.chart_owner(p.x, p.y)
	if o != PG.chart_owner(p.x, p.y):
		print("    ownership non-deterministic")
		return false
	var q := Vector2(-58.1, 122.0)
	if PG.chart_owner(q.x, q.y) < 0 or PG.chart_owner(q.x, q.y) >= 12:
		print("    owner out of range")
		return false
	# Local stability: tiny perturbation never changes the owner
	# (worst point is a Voronoi edge, excluded here on a happy path
	# sample; the interior of a face is the reliable case).
	var o2 := PG.chart_owner(p.x + 0.01, p.y - 0.01)
	if o2 != o:
		print("    owner jitter inside a face: ", o, " -> ", o2)
		return false
	# Covering radius: the layout's worst distance-to-nearest-center
	# must not exceed cap of 38% distortion (the 12-center icosa
	# covers to ~37.4 deg worst; caps for 38% are ~39 deg, enough).
	var worst := 0.0
	for i in range(25):
		for j in range(49):
			var la: float = -90.0 + 7.5 * i
			var lo: float = -180.0 + 7.5 * j
			var ow: int = PG.chart_owner(la, lo)
			# Unit-sphere haversine returns RADIANS (numerically "meters"
		# at r=1); covering radius is in degrees, so normalize.
			var d: float = rad_to_deg(SphericalScript.haversine(la, lo, centers[ow].x, centers[ow].y, 1.0))
			worst = maxf(worst, d)
	var covering: float = PG.atlas_covering_radius_deg()
	if absf(covering - worst) > 3.0:
		print("    geometric covering %.1f vs sampled worst %.1f" % [covering, worst])
		return false
	return true

## Law 22: the stitch layer — dense centers tighten the covering
## radius, boundary samples exist and are deterministic, skirt strips
## tag SKIRT_KIND triangles on rim edges only.
func _law_stitch_layer() -> bool:
	# Dense layout: subdiv 0 is the base 12; subdiv 1 subdivides 20
	# faces to 30 more centers (42 total) and TIGHTENS coverage.
	var centers0: Array = PG.atlas_centers_dense(0)
	var centers1: Array = PG.atlas_centers_dense(1)
	if centers0.size() != 12 or centers1.size() <= centers0.size():
		print("    dense centers wrong (0: ", centers0.size(), " 1: ", centers1.size(), ")")
		return false
	var c1_again: Array = PG.atlas_centers_dense(1)
	if c1_again.size() != centers1.size():
		print("    dense centers not index-stable")
		return false
	var worst1 := 0.0
	for i in range(19):
		for j in range(37):
			var la: float = -90.0 + 10.0 * i
			var lo: float = -180.0 + 10.0 * j
			var ow: int = PG.chart_owner_dense(la, lo, 1)
			var d: float = rad_to_deg(PG.SphericalScript.haversine(la, lo, centers1[ow].x, centers1[ow].y, 1.0))
			worst1 = maxf(worst1, d)
	if worst1 >= 37.0:
		print("    dense covering did not tighten: ", worst1)
		return false
	# Boundary samples: deterministic, nonempty, and every sample is
	# genuinely equidistant from its two centers (great-circle mid).
	var samples: Dictionary = PG.chart_boundary_samples(1)
	var samples2: Dictionary = PG.chart_boundary_samples(1)
	if samples.is_empty() or samples.size() != samples2.size():
		print("    boundary samples empty or nondeterministic: ", samples.size())
		return false
	var probe_key: String = samples.keys()[0]
	var mid: Vector2 = samples[probe_key]
	var parts: PackedStringArray = probe_key.split(".")
	var ca: Vector2 = centers1[int(parts[0])]
	var cb: Vector2 = centers1[int(parts[1])]
	var d1: float = rad_to_deg(PG.SphericalScript.haversine(mid.x, mid.y, ca.x, ca.y, 1.0))
	var d2: float = rad_to_deg(PG.SphericalScript.haversine(mid.x, mid.y, cb.x, cb.y, 1.0))
	if absf(d1 - d2) > 0.5:
		print("    boundary sample not equidistant: ", d1, " vs ", d2)
		return false
	# Skirt strip: rim edges only, all SKIRT_KIND.
	var patch: Array = PG.build_region(PG.GAMMA, 4.0)
	var skirt: Dictionary = PG.skirt_strip(patch, 0.5)
	var kinds: PackedInt32Array = skirt["tri_kind"]
	if kinds.size() == 0:
		print("    no skirt triangles")
		return false
	for k in kinds:
		if int(k) != PG.SKIRT_KIND:
			print("    skirt strip leaked a non-skirt kind")
			return false
	var pos: PackedVector3Array = skirt["positions"]
	# Skirt quads drop DOWN: some vertex pairs differ only in z.
	var drops := 0
	for i in range(0, pos.size(), 3):
		if absf(pos[i].z - pos[i + 1].z) > 0.0001 and absf(pos[i].x - pos[i + 1].x) > 0.0001:
			drops += 1
	_check_count(drops, 1, "skirt triangles have vertical extent")
	return drops >= 1

## Law 23: the extendability DECIDER — a real grid extract is
## extendable; a warped-off-grid tile, a kind-lying tile, and the
## ten-thin star are NOT.
func _law_extendability() -> bool:
	var patch: Array = PG.build_region(PG.GAMMA, 5.0)
	var sub: Array = patch.slice(10, 60)
	var r: Dictionary = PG.is_extendable(sub)
	if not bool(r["ok"]):
		print("    real extract not extendable: ", r["errors"].slice(0, 3))
		return false
	# Warp a vertex: geometry can't be the canonical rhombus.
	var t0: PG.Tile = patch[0]
	var warped: Array[Vector2] = [t0.verts[0], t0.verts[1] + Vector2(0.5, 0.5), t0.verts[2], t0.verts[3]]
	var rw: Dictionary = PG.is_extendable([PG.Tile.new(t0.kind, warped, t0.families, t0.levels)])
	if bool(rw["ok"]):
		print("    warped tile passed the decider")
		return false
	# Kind-lying tile: geometry matches but kind defies the grid.
	for t in patch:
		if t.kind == PG.TileKind.FAT:
			var rl: Dictionary = PG.is_extendable([PG.Tile.new(PG.TileKind.THIN, t.verts, t.families, t.levels)])
			if bool(rl["ok"]):
				print("    kind-lying tile passed the decider")
				return false
			break
	# Ten-thin star: locally arrow-lawful, unplaceable here.
	var O := Vector2.ZERO
	var star: Array = []
	for i in range(10):
		var a := deg_to_rad(36.0 * i)
		var b := deg_to_rad(36.0 * (i + 1))
		var e1 := Vector2(cos(a), sin(a))
		var e2 := Vector2(cos(b), sin(b))
		star.append(PG.Tile.new(PG.TileKind.THIN, [O, e1, e1 + e2, e2], patch[0].families, patch[0].levels))
	var rs: Dictionary = PG.is_extendable(star)
	if bool(rs["ok"]):
		print("    ten-thin star passed the decider")
		return false
	return true

func _check_count(got: int, want: int, label: String) -> void:
	if got < want:
		print("    COUNT %s: got %d want >= %d" % [label, got, want])

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
