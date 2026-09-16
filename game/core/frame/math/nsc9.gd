## Ported from dhaupin/vant axolotl geometry/nsc9.js
## NSC-9 encoding: reserved GS1/GTIN-14 space for multi-iso axis codes.
## 9-AAA-BBB-CCCCCC: prefix=9 (GS1 non-product), facility=AAA (000-999),
## axis=BBB (000-999), sequence=CCCCCC (0-16M).
##
## Axis reservation (see game/core/frame/prototype/iso_math.py):
##   001-099: spatial axis (icosahedral vertices 1-12)
##   100-199: factional axes (100 factions)
##   200-299: temporal sub-axes (year, season, month, hour...)
##   300-399: social axes (per-player, per-guild)
##   400-499: game-specific axes
##   500-999: free
extends RefCounted

class_name Nsc9

const PHI: float = 1.6180339887498949

## The 12 vertices of a unit icosahedron (cyclic permutations of (0, ±1, ±phi)).
const ICOSAHEDRAL_VERTICES: PackedVector3Array = [
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

## Axis reservation constants.
const AXIS_SPATIAL_BASE: int = 1
const AXIS_SPATIAL_MAX: int = 12
const AXIS_FACTION_BASE: int = 100
const AXIS_FACTION_MAX: int = 199
const AXIS_TEMPORAL_YEAR: int = 200
const AXIS_TEMPORAL_SEASON: int = 201
const AXIS_TEMPORAL_MONTH: int = 202
const AXIS_TEMPORAL_HOUR: int = 203
const AXIS_SOCIAL_BASE: int = 300
const AXIS_SOCIAL_MAX: int = 399
const AXIS_GAME_BASE: int = 400
const AXIS_GAME_MAX: int = 499

## Encode a facility/axis/sequence into a 14-digit NSC-9 integer.
## Returns an int: 9AAA BBB CCCCCC (concatenated digits).
## Example: encode_int(7, 42, 123456) = 90070420123456
func encode_int(facility: int, axis: int, sequence: int) -> int:
	return 9_000_000_000_000 + facility * 1_000_000_000 + axis * 1_000_000 + sequence

## Encode as a string: "9-AAA-BBB-CCCCCC"
func encode_str(facility: int, axis: int, sequence: int) -> String:
	return "9-%03d-%03d-%06d" % [facility, axis, sequence]

## Parse an NSC-9 string code into {prefix, facility, axis, sequence}.
func parse_str(code: str) -> Dictionary:
	var parts = code.split("-")
	if parts.size() != 4:
		return {}
	return {
		"prefix" = int(parts[0]),
		"facility" = int(parts[1]),
		"axis" = int(parts[2]),
		"sequence" = int(parts[3]),
	}

## Spatial axis for icosahedral vertex index (0-11 → axis 1-12).
func spatial_axis(vertex: int) -> int:
	return AXIS_SPATIAL_BASE + vertex

## Factional axis for faction id (0-99 → axis 100-199).
func faction_axis(faction_id: int) -> int:
	return AXIS_FACTION_BASE + faction_id

## Social axis for group id (0-99 → axis 300-399).
func social_axis(group: int) -> int:
	return AXIS_SOCIAL_BASE + group

## Game-specific axis for class id (0-99 → axis 400-499).
func game_axis(game_class: int) -> int:
	return AXIS_GAME_BASE + game_class

## Encode the year as a sequence on the temporal-year axis (200).
func encode_year(year: int) -> int:
	return year

## Decode the year from a temporal-year sequence.
func decode_year(sequence: int) -> int:
	return sequence

## Project a 3D position on a sphere to (latitude, longitude).
## Input vector3 is assumed to be on the sphere surface (or will be normalized).
func project_to_latlon(position: Vector3, planet_radius: float = 20000.0) -> Vector2:
	var normalized = position.normalized()
	var lat = rad2deg(asin(clampf(normalized.y, -1.0, 1.0)))
	var lon = rad2deg(atan2(normalized.z, normalized.x))
	return Vector2(lat, lon)

## Map a lat/lon to the nearest icosahedral vertex index (0-11).
## Uses dot product against the 12 unit vertices.
func nearest_vertex(lat: float, lon: float) -> int:
	var phi = deg2rad(lat)
	var theta = deg2rad(lon)
	var x = cos(phi) * cos(theta)
	var y = sin(phi)
	var z = cos(phi) * sin(theta)
	var direction = Vector3(x, y, z)
	var best = 0
	var best_dot = -999.0
	for i in range(ICOSAHEDRAL_VERTICES.size()):
		var dot = direction.dot(ICOSAHEDRAL_VERTICES[i])
		if dot > best_dot:
			best_dot = dot
			best = i
	return best

## Full entity encoding: returns an NSC-9 integer code for the spatial axis.
func encode_entity_spatial(facility: int, vertex: int) -> int:
	return encode_int(facility, spatial_axis(vertex), 0)

## Full entity encoding for faction axis.
func encode_entity_faction(facility: int, faction_id: int, sequence: int = 0) -> int:
	return encode_int(facility, faction_axis(faction_id), sequence)

## Full entity encoding for social axis.
func encode_entity_social(facility: int, group: int, sequence: int = 0) -> int:
	return encode_int(facility, social_axis(group), sequence)

## Full entity encoding for game class axis.
func encode_entity_game(facility: int, game_class: int, sequence: int = 0) -> int:
	return encode_int(facility, game_axis(game_class), sequence)

## Full entity encoding for temporal year axis.
func encode_entity_temporal_year(facility: int, year: int) -> int:
	return encode_int(facility, AXIS_TEMPORAL_YEAR, encode_year(year))

## Full entity encoding for temporal season axis (0-3).
func encode_entity_temporal_season(facility: int, season: int) -> int:
	return encode_int(facility, AXIS_TEMPORAL_SEASON, season)

## Build a cell key string for hash lookups.
## Returns "nsc9:{facility}:{axis}:{sequence}" style key.
func cell_key(facility: int, axis: int, sequence: int) -> String:
	return "nsc9:%03d:%03d:%06d" % [facility, axis, sequence]

## Build a cell key from an encoded int.
func cell_key_from_int(code: int) -> String:
	var facility = (code % 1_000_000_000_000 / 1_000_000_000) % 1000
	var axis = (code % 1_000_000_000 / 1_000_000) % 1000
	var sequence = code % 1_000_000
	return cell_key(facility, axis, sequence)

## Extract components from an NSC-9 integer code.
func decode_int(code: int) -> Dictionary:
	var prefix = code / 1_000_000_000_000
	var facility = (code % 1_000_000_000_000) / 1_000_000_000
	var axis = (code % 1_000_000_000) / 1_000_000
	var sequence = code % 1_000_000
	return {
		"prefix" = prefix,
		"facility" = facility,
		"axis" = axis,
		"sequence" = sequence,
	}

## Deterministic sequence from an entity id + tag (for stable NSC-9 sequences).
func deterministic_seq(entity_id: String, tag: String) -> int:
	var input = entity_id + ":" + tag
	var hash_val = 5381
	for i in range(input.length()):
		hash_val = ((hash_val << 5) + hash_val + ord(input[i])) & 0xFFFFFF
	return hash_val % 1_000_000
