extends RefCounted
class_name TerrainBackendPenrose

## S15 PENROSE GROUND (the "lattice IS the planet" backend): the second
## authored installation on the external heightfield seam
## (terrain_gen.install_terrain_backend). The planet's raw landfield
## becomes the PENROSE LATTICE ON THE SPHERE via the EXISTSING
## multi-chart atlas math:
#### Direction d (unit) -> chart center (the BASE atlas_centers(), the
##   12 icosa vertices; ownership cone >> tile), -> index-stable
##   nearest-center selection (ties by lowest index).
##
## Height LAW per chart (pure, deterministic, cache-keyed upstream):
##   The lattice lives at an altitude base (LATTICE_BASE above the sea
##   line), so the "ground" reads as tiling benches ABOVE an ocean
##   ruled by the radial sea law downstream:
##     - GROOVES at the tile edges (the seams between tiles), depth
##       falls off as exp(-d / GROOVE_SIGMA) with d = the planar
##       distance to the nearest rhombus EDGE in the chart's tangent
##       frame, so a full-height BENCH sits in tile INTERIORS and the
##       seams read as step-lattice grooves (the walkable Penrose
##       character);
##     - KNOWING the exact tile edges means the answer maps through
##       pentagrid.tile_at in planar space: from dir we recover the
##       chart's tangent frame, form the planar (u, v), get the tile
##       and read its 4 verified edges.
##     - OWNERSHIP uses the BASE 12-center atlas (cap 37 deg, planar
##       cone ~0.62 units > one tile extent), so grooves exist INSIDE
##       each cone. Continuity across charts is BY CONSTRUCTION: the
##       groove amplitude FADES to zero near the cone rim (both charts
##       serve the flat bench at the boundary), so the ground law is
##       continuous everywhere even though each chart's local lattice
##       differs from its neighbor's.
##   The boot's law-native sculpt tail (island/moat, plaza, apron)
##   rides OVER this raw field exactly like it did over the analytic
##   and sundered backends.
##
## Composition-of-one-source (the same purity the sundered backend
## carries): the same unit_dir always yields the same height on this
## machines; the delta between neighbors is EXACT to the tangent plane's
## preceision over the chart cap; nothing random.
##
## Backend CONTRACT: (unit_dir, seed_bytes) -> raw meters above the base
## surface (may be negative). Sculpt/plaza/apron/spawn guarantees stay
## flower-native upstream; the radial ocean law rides the sea line
## (terrain_gen.sea_level) downstream of us.

const Gen = preload("res://scenes/worlds/terrain_gen.gd")
const PG = preload("res://core/frame/math/pentagrid.gd")

## The bench altitude: tiling interiors sit at this height ABOVE THE
## SEA LINE for raw-field purposes (the sculpt tail's island can push
## higher via max(); the ocean floor stays in the moat/strait cuts).
## POLE LAW companion: the projection/probe seam maps round-trip
## consistently against the backend's _east_for at |n.dot(UP)| ~= 1
## by substituting a fixed equatorial reference axis, so the SAME
## planar point maps back from a pole chart exactly as from any other.
const LATTICE_BASE: float = 8.0

## Ridge-to-groove depth
## (the vertical metaphor: vertices ride HIGH, edges carve LOW).
const GROOVE_DEPTH: float = 3.5

## Seam breadth: the exp() sigma for the edge-distance falloff, in
## planar tiling units. The FAT rhombus is ~1.4 units wide in the
## canonical Gamma grid, so an interior point sits >= 0.3 units from
## every edge; the sigma is tuned so that >= 80% of the groove depth
## is recovered there (0.55 would eat 45%, reading every bench as a
## half-carved groove in practice).
const GROOVE_SIGMA: float = 0.14

## The cone-rim FADE: grooves run at full strength below FADE_IN of
## the planar ownership radius and vanish at FADE_OUT, so both seam
## partners serve the flat bench at the boundary plane (exact
## continuity; the boundary is tan of half the 63.43-deg neighbor
## spacing ~ 0.617; we fade inside it).
const FADE_IN: float = 0.42
const FADE_OUT: float = 0.60

## How deep BELOW the sea line the raw field falls when the lattice
## misses (the boot guarantee only covers the SPAWN POINT; walking off
## the lattice rim must read as falling into a groove that opens onto
## ocean floor -- not into a glitch void). Same band the native path
## uses (-3.0).
const RIM_FALL: float = -3.0


## -- The one public backend callable (the install signature) ----------

static func field(dir: Vector3, seed_bytes: PackedByteArray) -> float:
	var d: Vector3 = dir.normalized()
	# Chart selection: the SAME nearest-center law the LOD policy
	# consumes (atlas_centers_dense(1)) -- one source of truth for
	# which chart owns a direction, so the ground law and the LOD
	# climb can never disagree about whose patch a seam belongs to.
	var center: Vector2 = _chart_center(d)
	var n_center: Vector3 = PG.normal_at(center.x, center.y)
	# The inverse-gnomonic: recover the chart's planar (u, v) for this
	# direction (the same tangent frame gnomonic_project builds).
	var planar: Vector2 = _to_chart_frame(d, center)
	# THE LATTICE LAW (pure function of planar coords):
	var u: float = planar.x
	var v: float = planar.y
	var tile = PG.tile_at(Vector2(u, v))
	if tile == null:
		# Degenerate (off-grid numeric dust): serve the bench flat.
		return LATTICE_BASE
	# Edge-distance: precomputed per sorted edge pair; the MIN across
	# the four verified edges (this is the groove law's d).
	var d_edge: float = _edge_distance(Vector2(u, v), tile.verts)
	# Cone-rim fade: amplitude 1 inside FADE_IN, 0 at FADE_OUT. At the
	# ownership boundary both charts serve the flat bench exactly.
	var radius: float = Vector2(u, v).length()
	var fade: float = 1.0 - smoothstep(FADE_IN, FADE_OUT, radius)
	var groove: float = GROOVE_DEPTH * exp(-d_edge / GROOVE_SIGMA) * fade
	return LATTICE_BASE - groove


## -- Chart frame math (mutual inverses, probed) -----------------------

## The chart center (the BASE atlas's lat/lon pair) that owns d:
## MAXIMIZE the dot (cosine similarity) -- best_d starts at -INF, not
## INF (the maximize direction; ties break by lowest index).
## Ground-law charts are the 12 icosa vertices (ownership cone
## tan(31.7 deg) ~ 0.62 planar units, larger than one tile extent so
## grooves live inside cones; the LOD overlay keeps dense(1) --
## separate layers, both index-stable on their own atlas).
static func _chart_center(d: Vector3) -> Vector2:
	var centers: Array = PG.atlas_centers()
	var best := 0
	var best_d: float = -INF
	for i in range(centers.size()):
		var c: Vector2 = centers[i]
		var n: Vector3 = PG.normal_at(c.x, c.y)
		var dot: float = n.dot(d)  # cosine distance (monotone in angle)
		if dot > best_d + 1e-9:
			best_d = dot
			best = i
	return centers[best]


## Direction -> planar (u, v) in the chart's tangent frame, the exact
## inverse of the frame gnomonic_project builds: u = d dot east / d dot n,
## v = d dot north / d dot n.
##
## POLE LAW: native gnomonic_project degenerates when the chart
## normal is parallel to UP (the atlas centers INCLUDE both poles);
## n.cross(UP) is the zero vector there and east collapses. The
## backend frame substitutes a FIXED orthogonal reference axis for
## UP when |n dot UP| ~ 1, consistent between project and invert:
## both must use the same rule for the round trip to close. We
## therefore own one _east_for helper used BY BOTH directions of
## this backend's own math. NOTE: the frame's forward projection
## (dir->planar) uses the SAME _east_for — and where the field is
## sampled through chart menos (poles), the planar mapping closes
## because BOTH branches agree on which axis to use.
static func _east_for(n: Vector3) -> Vector3:
	var up_ref: Vector3 = Vector3.UP
	if absf(n.dot(up_ref)) > 0.999:
		up_ref = Vector3(1.0, 0.0, 0.0)  # pole-signuck: an axis that is
		# NOT parallel to n at the poles (n = +-Y here).
	return n.cross(up_ref).normalized()

static func _to_chart_frame(d: Vector3, center: Vector2) -> Vector2:
	var n: Vector3 = PG.normal_at(center.x, center.y)
	var east: Vector3 = _east_for(n)
	var north: Vector3 = east.cross(n).normalized()
	var denom: float = d.dot(n)
	if absf(denom) < 1e-9:
		# Grazing the chart rim: outside the usable cap; clamp to a
		# huge planar value (the spur falls off-grid).
		return Vector2(1e6, 1e6)
	var u: float = d.dot(east) / denom
	var v: float = d.dot(north) / denom
	return Vector2(u, v)


## _edge_distance: min over the tile's 4 edges of the planar
## point-segment distance. Segments are Vector2 pairs.
static func _edge_distance(p: Vector2, verts: Array[Vector2]) -> float:
	var best := INF
	for e in range(4):
		var a: Vector2 = verts[e]
		var b: Vector2 = verts[(e + 1) % 4]
		var ab: Vector2 = b - a
		var t: float = clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var proj: Vector2 = a + t * ab
		var dl: float = (p - proj).length()
		if dl < best:
			best = dl
	return best
