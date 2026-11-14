## LandmarkData -- the atlas entry for a named place.
##
## A landmark is IDENTITY, not travel and not a pin:
##   - what the place is CALLED (display_name, description)
##   - where it STANDS (dir, on a named world)
##   - how the map KNOWS it (kind, map_icon, discover)
##   - which zone it BELONGS to (zone_id)
##
## The three neighbouring systems keep their own law and are never merged:
##   GatewayData    -- travel: activation requirements + a destination.
##   WaypointService-- the player's own pins (capped, per-player, editable).
##   LandmarkData   -- this file: shared, authored, never player-owned.
##
## A landmark that is ALSO a travel point names its gateway in `gateway_id`.
## The gateway still decides who may use it; the landmark only says what the
## place is. The reverse reference never exists: a landmark never names a
## player or a pin.
##
## Placement: `dir` is the canonical direction on the world's sphere (the
## same space terrain_gen's anchors use), so a name cannot drift from the
## geometry. A zero `dir` is legal and means "no single point" -- a band
## (The Home Ring) or a whole world (The Deep Root). `has_position()` is the
## read for callers that need a point.
extends Resource
class_name LandmarkData

enum Kind {
	SETTLEMENT,  # village, city, camp
	PEAK,        # mountain, ridge, range
	LAKE,        # tarn, basin, inland water
	STRAIT,      # channel, passage, sea gate
	MONOLITH,    # the Capitol monolith and its kin
	GATE,        # a built threshold (moon gate, ascent gate)
	ANKH,        # a bound shrine
	RUIN,        # dead-place site
	SITE,        # any other named place
}

## How the map learns about it.
enum Discover {
	VISIBLE,  # labelled from the start
	HIDDEN,   # exists, but unnamed until found
	VISITED,  # labelled once the player has stood there
}

@export var id: String = ""
@export var display_name: String = "Landmark"
@export var description: String = ""
@export var kind: Kind = Kind.SITE

## Canonical direction on the world sphere. Zero = no single point.
@export var dir: Vector3 = Vector3.ZERO
## Which declared world this landmark belongs to.
@export var world_id: String = "main"

## Owning zone (empty for a band or a world-level landmark).
@export var zone_id: String = ""
## Map glyph family ("settlement", "peak", "lake", ...). Presentation only.
@export var map_icon: String = "site"
@export var discover: Discover = Discover.VISIBLE

## Set when this landmark IS also a travel point; the gateway keeps the law.
@export var gateway_id: String = ""

## Optional pointer into the Chronicle/codex.
@export var codex_ref: String = ""


func _init() -> void:
	if id == "":
		id = display_name.to_lower().replace(" ", "_")


func has_position() -> bool:
	return dir.length_squared() > 0.000001


func dir_normalized() -> Vector3:
	return dir.normalized() if has_position() else Vector3.ZERO


## A landmark is travel-relevant only by naming a real gateway.
func is_travel_point() -> bool:
	return gateway_id != ""


func kind_name() -> String:
	match kind:
		Kind.SETTLEMENT: return "settlement"
		Kind.PEAK: return "peak"
		Kind.LAKE: return "lake"
		Kind.STRAIT: return "strait"
		Kind.MONOLITH: return "monolith"
		Kind.GATE: return "gate"
		Kind.ANKH: return "ankh"
		Kind.RUIN: return "ruin"
		_: return "site"
