extends RefCounted
class_name TerrainBackendSundered

## S14.7 SUNDERED SEA (the authored content backend, backend-seam-first
## policy): the first authored installation on the external heightfield
## seam. Composes over TerrainGen._natural_raw -- the home world's
## geology stays the world's geology -- and carves the SUNDERED STRAIT:
## a navigable channel from the ferry moat ring out to open water,
## flanked by two headlands, with a wreck shoal ford mid-channel.
##
## CHART LAW: the site uses a LOCAL TANGENT-PLANE chart at the strait
## center. Coordinates (x, y) in radians: x = along the run (outward,
## toward the sea), y = across the run. The chart is exact to
## <0.2% over the site extent (~0.3 rad = 6 km at planet scale) and
## ORTHOGONAL by construction, so the corridor (x-band x y-band),
## headlands (y-band) and shoal (x-position at lane y-approx-0) never
## contaminate each other. d(x, y) chart->direction and _chart(d)
## direction->chart are mutual inverses (probed).
##
## Backend CONTRACT (terrain_gen.gd): (unit_dir, seed_bytes) -> raw
## meters. Sculpt/guarantee laws (island, moat, plaza, apron, ceiling)
## stay law-native and ride on top; this backend only shapes the RAW
## field under them. PURE: same seed, same strait.

const Gen = preload("res://scenes/worlds/terrain_gen.gd")

## -- Authored site layout ---------------------------------------------

## The strait's center direction (unit after normalize in code).
const STRAIT_CENTER: Vector3 = Vector3(-0.24, 0.72, 0.56)
## Run direction (tangent): outward, island -> open sea.
const RUN_DIR: Vector3 = Vector3(-0.24, 0.72, 0.56) - Vector3(0.0, 0.866, 0.5)

## Corridor: |y| < W inside the run band x in [RUN_LO, RUN_HI].
const RUN_LO: float = 0.020     # starts past the moat ring (0.03 moat end)
const RUN_LEN: float = 0.30     # corridor length (radians)
const STRAIT_HALF_ANG: float = 0.010   # half-width across (W)
const HEADLAND_HALF_ANG: float = 0.0045 # headland flank width
const STRAIT_DEPTH: float = 6.0 # strait floor depth below sea
## Wreck shoal: spine across the channel (a wet ford).
const SHOAL_RAISE: float = 4.5  # floor rise toward the ford crest
const SHOAL_AT: float = 0.55    # along-run position (fraction)
const SHOAL_WIDTH: float = 0.006  # Gaussian half-width along the run

## -- Frame helpers -----------------------------------------------------


## The site frame: cached static pair (T = run tangent, P = across).
## T and P are unit and orthogonal to the center; the chart is exact.
static var _frame_cache: Array = []
static func _frame() -> Array:
	if _frame_cache.is_empty():
		var c: Vector3 = STRAIT_CENTER.normalized()
		var t: Vector3 = RUN_DIR.normalized()
		# Re-orthogonalize T against c (a small correction; keeps T a
		# true tangent at the site).
		t = (t - c * t.dot(c)).normalized()
		var p: Vector3 = c.cross(t).normalized()
		var fr: Array = [c, t, p]
		_frame_cache = fr
	return _frame_cache


## Chart coords of a direction: (x = along-run, y = across), radians.
## EXACT inversion of from_chart: with d = c cos r + u sin r
## (u unit in the tangent plane u.(x,y) direction), the frame reads
## give sin(r) * (x/r) and sin(r) * (y/r) -- so scale by (r / sin r).
## Near r -> 0 the sinc correction is 1 (Taylor), so the chart is
## smooth and exact everywhere on the site.
static func _chart(d: Vector3) -> Vector2:
	var fr: Array = _frame()
	var dn: Vector3 = d.normalized()
	var cos_r: float = clampf(dn.dot(fr[0]), -1.0, 1.0)
	var r: float = acos(cos_r)
	var sinc: float = 1.0
	if r > 1e-6:
		sinc = sin(r) / r
	if absf(sinc) < 1e-9:
		return Vector2.ZERO
	var sx: float = dn.dot(fr[1]) / sinc
	var sy: float = dn.dot(fr[2]) / sinc
	return Vector2(sx, sy)


## Direction from chart coords: the exact radial construction
## (d = c cos r + u sin r where u is the unit tangent-plane direction,
## r = |(x, y)|). Inverse of _chart to first order; probe-verified.
static func from_chart(x: float, y: float) -> Vector3:
	var fr: Array = _frame()
	var u: Vector3 = fr[1] * x + fr[2] * y
	var r: float = u.length()
	if r < 1e-9:
		return fr[0]
	u = u / r
	return (fr[0] * cos(r) + u * sin(r)).normalized()


## -- Backend body -------------------------------------------------------


## The composed raw field: natural geology, then the authored strait.
static func field(dir: Vector3, world_seed: PackedByteArray) -> float:
	var d: Vector3 = dir.normalized()
	var sea: float = Gen.sea_level(world_seed)
	var h: float = Gen._natural_raw(d, world_seed)
	var ch: Vector2 = _chart(d)
	var run_hi: float = RUN_LO + RUN_LEN
	# Only the corridor rectangle is authored; everything else stays
	# the natural field (cheap early-out too: chart coords only when
	# inside the run band).
	if ch.x < RUN_LO or ch.x > run_hi:
		return minf(h, Gen.TERRAIN_MAX)
	var y_abs: float = absf(ch.y)
	var w: float = STRAIT_HALF_ANG
	var flank: float = HEADLAND_HALF_ANG
	# --- Headland mounds: flank bands, always land over the field. ---
	var band: float = smoothstep(w, w + 0.0008, y_abs) \
		* (1.0 - smoothstep(w + flank, w + flank + 0.0008, y_abs))
	if band > 0.0:
		h = maxf(h, sea + 3.0 + 2.5 * band)
	# --- The channel cut: W-band, bed below sea, shoal spine. ---
	var cut: float = 1.0 - smoothstep(w - 0.0015, w, y_abs)
	if cut > 0.0:
		var bed: float = sea - STRAIT_DEPTH
		var x_shoal: float = lerpf(RUN_LO, run_hi, SHOAL_AT)
		var shoal: float = exp(-pow((ch.x - x_shoal) / SHOAL_WIDTH, 2.0)) \
			* exp(-pow(y_abs / (w + 0.004), 2.0))
		var bed_local: float = lerpf(bed, sea - 0.4, \
			minf(SHOAL_RAISE / STRAIT_DEPTH, 1.0) * shoal)
		h = lerpf(h, bed_local, cut)
	return minf(h, Gen.TERRAIN_MAX)


## -- Install/uninstall convenience (the seam API in terrain_gen) -----


static func install() -> void:
	Gen.install_terrain_backend(field)


static func uninstall() -> void:
	Gen.uninstall_terrain_backend()
