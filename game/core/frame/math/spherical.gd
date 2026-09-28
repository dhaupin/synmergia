## Spherical world math (frame primitive)
## Haversine distance, geodesic bearing, great-circle interpolation,
## and spherical<->cartesian conversion for the planet (20 km radius v1).
## Degrees in, degrees out. Design refs:
##   labs/world-building-spherical.md sec 8 (formulas), sec 9 (constants)
##   labs/prd-spherical-mvp.md (execution record)
extends RefCounted

class_name Spherical

## v1 planet radius in meters (prd.md planet scale table).
const PLANET_RADIUS_METERS: float = 20000.0

## Earth mean radius, for known-answer tests and real-globe math.
const EARTH_RADIUS_METERS: float = 6371000.0


## Great-circle distance between two lat/lon points (degrees).
## Returns meters along the surface.
static func haversine(lat1: float, lon1: float, lat2: float, lon2: float, radius: float = PLANET_RADIUS_METERS) -> float:
	var phi1: float = deg_to_rad(lat1)
	var phi2: float = deg_to_rad(lat2)
	var dphi: float = deg_to_rad(lat2 - lat1)
	var dlmb: float = deg_to_rad(lon2 - lon1)
	var a: float = sin(dphi * 0.5) * sin(dphi * 0.5) \
		+ cos(phi1) * cos(phi2) * sin(dlmb * 0.5) * sin(dlmb * 0.5)
	# Guard: floating point can push a slightly above 1.0 for antipodes.
	var a_clamped: float = clampf(a, 0.0, 1.0)
	var c: float = 2.0 * atan2(sqrt(a_clamped), sqrt(1.0 - a_clamped))
	return radius * c


## Initial geodesic bearing (degrees, 0 = north, 90 = east) from point 1
## toward point 2. Undefined at coincident points; returns 0 there.
static func geodesic_bearing(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
	var phi1: float = deg_to_rad(lat1)
	var phi2: float = deg_to_rad(lat2)
	var dlmb: float = deg_to_rad(lon2 - lon1)
	var y: float = sin(dlmb) * cos(phi2)
	var x: float = cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(dlmb)
	var theta: float = atan2(y, x)
	# atan2 is (-pi, pi]; normalize to [0, 360).
	var deg: float = rad_to_deg(theta)
	if deg < 0.0:
		deg += 360.0
	return deg


## Point at fraction f (0..1) along the great circle from point 1 to
## point 2. Returns Vector2(lat, lon) in degrees. Antipodal paths are
## degenerate; f=0 or d~0 returns point 1.
static func great_circle_intermediate(lat1: float, lon1: float, lat2: float, lon2: float, f: float) -> Vector2:
	var phi1: float = deg_to_rad(lat1)
	var lmb1: float = deg_to_rad(lon1)
	var phi2: float = deg_to_rad(lat2)
	var lmb2: float = deg_to_rad(lon2)
	var d: float = haversine(lat1, lon1, lat2, lon2, 1.0)  # angular distance in radians
	if d < 0.0000001:
		return Vector2(lat1, lon1)
	var a: float = sin((1.0 - f) * d) / sin(d)
	var b: float = sin(f * d) / sin(d)
	var x: float = a * cos(phi1) * cos(lmb1) + b * cos(phi2) * cos(lmb2)
	var y: float = a * cos(phi1) * sin(lmb1) + b * cos(phi2) * sin(lmb2)
	var z: float = a * sin(phi1) + b * sin(phi2)
	var lat: float = rad_to_deg(atan2(z, sqrt(x * x + y * y)))
	var lon: float = rad_to_deg(atan2(y, x))
	return Vector2(lat, lon)


## Spherical (degrees + altitude above surface) to cartesian meters.
## Convention per world-building-spherical.md sec 2.5:
##   phi = 90 - lat (polar), theta = lon; +Y is the north pole axis.
static func spherical_to_cartesian(lat: float, lon: float, alt: float = 0.0, radius: float = PLANET_RADIUS_METERS) -> Vector3:
	var r: float = radius + alt
	var phi: float = deg_to_rad(90.0 - lat)
	var theta: float = deg_to_rad(lon)
	return Vector3(
		r * sin(phi) * cos(theta),
		r * cos(phi),
		r * sin(phi) * sin(theta)
	)


## Cartesian meters to lat/lon degrees (Vector2(lat, lon), same
## convention as Icosahedral.project). Altitude is ignored (projected
## onto the sphere of the given radius).
static func cartesian_to_spherical(pos: Vector3, radius: float = PLANET_RADIUS_METERS) -> Vector2:
	var r: float = pos.length()
	if r < 0.0000001:
		return Vector2.ZERO
	var lat: float = 90.0 - rad_to_deg(acos(clampf(pos.y / r, -1.0, 1.0)))
	var lon: float = rad_to_deg(atan2(pos.z, pos.x))
	return Vector2(lat, lon)
