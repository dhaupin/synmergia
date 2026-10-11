extends RefCounted
class_name StraitChart

## THE STRAIT CHART (content side): the single script that owns the
## backend_sundered site geometry for CONTENT placement. Backend and
## probes already ask backend_sundered's statics directly; world DATA
## (.tres files) cannot preload a probe-only script, so placement
## resolves through this seam: from_chart(x, y) -> Vector3 direction,
## and anchor(radius_m) -> the world position to author in a .tres.
##
## WHY (the honesty law the terrain backend set): a chart position
## that does not sit on the authored corridor is an invented position.
## The two SHIP gateways + the strait NPCs sit at Vector3(0,0,0)
## today, meaning "the zone bind point" -- a spot inside the moat
## ring, nowhere near the channel the barque sails. This resolver
## turns the SAME constants the backend shapes the terrain with into
## positions on that terrain. ONE derivation, two readers (backend
## field + content anchors): if content and terrain ever disagreed,
## the bug could only live in backend_sundered's constants.

const Backend = preload("res://scenes/worlds/backend_sundered.gd")
const WorldDataScript = preload("res://core/schemas/world_data.gd")

## The home world's planet radius (world_main declares 20000.0; the
## read is data truth, the fallback is the same default).
static func planet_radius_m(world_id: String = "main") -> float:
	var path := "res://data/worlds/world_%s.tres" % world_id
	var wd: Resource = load(path)
	if wd != null and "radius_m" in wd:
		return float(wd.radius_m)
	return 20000.0


## World-chart -> world position: the backend's exact tangent-frame
## construction, scaled by the planet radius. positions[surface] sits
## ON the sphere at that direction; height is what the radial snap
## law settles (never bake terrain height here).
static func dir_from_chart(x: float, y: float) -> Vector3:
	return Backend.from_chart(x, y)


## The authored world position for a chart anchor (moor, shoal,
## seaward). x = along-run (0.02 moat start -> 0.32 sea), y = across.
static func anchor_from_chart(x: float, y: float, world_id: String = "main") -> Vector3:
	return dir_from_chart(x, y) * planet_radius_m(world_id)
