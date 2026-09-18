## Ported from vant axolotl geometry/icosahedral.js
## Icosahedral projection: maps 3D sphere positions to icosahedral cells.
extends RefCounted

class_name Icosahedral

const PHI: float = 1.6180339887498949

## The 12 vertices of a unit icosahedron.
const VERTICES: PackedVector3Array = [
	Vector3(0, 1, PHI),
	Vector3(0, -1, PHI),
	Vector3(0, 1, -PHI),
	Vector3(0, -1, -PHI),
	Vector3(1, PHI, 0),
	Vector3(-1, PHI, 0),
	Vector3(1, -PHI, 0),
	Vector3(-1, -PHI, 0),
	Vector3(PHI, 0, 1),
	Vector3(-PHI, 0, 1),
	Vector3(PHI, 0, -1),
	Vector3(-PHI, 0, -1),
]

## Precompute normalized vertices at class init time.
var _normalized: PackedVector3Array = []

func _init() -> void:
	for i in range(VERTICES.size()):
		_normalized.append(VERTICES[i].normalized())

## Project a 3D position on a sphere to (latitude, longitude) in degrees.
## Input vector3 is assumed to be on the sphere surface (or will be normalized).
func project(position: Vector3, planet_radius: float = 20000.0) -> Vector2:
	var normalized = position.normalized()
	var lat = rad_to_deg(asin(clampf(normalized.y, -1.0, 1.0)))
	var lon = rad_to_deg(atan2(normalized.z, normalized.x))
	return Vector2(lat, lon)

## Map a lat/lon to the nearest icosahedral vertex index (0-11).
func to_cell(lat: float, lon: float, resolution: int = 0) -> int:
	var phi = deg_to_rad(lat)
	var theta = deg_to_rad(lon)
	var x = cos(phi) * cos(theta)
	var y = sin(phi)
	var z = cos(phi) * sin(theta)
	var direction = Vector3(x, y, z)
	var best = 0
	var best_dot = -999.0
	for i in range(_normalized.size()):
		var dot = direction.dot(_normalized[i])
		if dot > best_dot:
			best_dot = dot
			best = i
	return best

## Map a 3D position directly to an icosahedral vertex cell.
func position_to_cell(position: Vector3, planet_radius: float = 20000.0, resolution: int = 0) -> int:
	var latlon = project(position, planet_radius)
	return to_cell(latlon.x, latlon.y, resolution)

## Compute the 3D position at the center of an icosahedral vertex cell.
func cell_center(cell_id: int, resolution: int = 0) -> Vector3:
	if cell_id < 0 or cell_id >= VERTICES.size():
		return Vector3.ZERO
	return VERTICES[cell_id]

## Return the neighboring vertex indices for a given cell.
## On a regular icosahedron, each vertex connects to 5 others.
## We compute neighbors by shared-edge adjacency.
func neighbors(cell_id: int, resolution: int = 0) -> PackedInt32Array:
	if cell_id < 0 or cell_id >= VERTICES.size():
		return PackedInt32Array()
	var result: PackedInt32Array = []
	var v = _normalized[cell_id]
	for i in range(_normalized.size()):
		if i == cell_id:
			continue
		var dot = v.dot(_normalized[i])
		## Adjacent vertices have dot product near cos(63.43 degrees) ~ 0.4472
		## Vertices connected by an edge share an edge, their dot is 1/sqrt(5)
		if dot > 0.44:
			result.append(i)
	result.sort()
	return result

## Get all 12 vertex positions (normalized).
func get_vertices() -> PackedVector3Array:
	return VERTICES

## Get the vertex index closest to a direction vector.
func nearest_vertex(direction: Vector3) -> int:
	var normalized = direction.normalized()
	var best = 0
	var best_dot = -999.0
	for i in range(_normalized.size()):
		var dot = normalized.dot(_normalized[i])
		if dot > best_dot:
			best_dot = dot
			best = i
	return best
