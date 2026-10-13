extends Resource
class_name RoadData

## Data-driven cart roads, trails, and bridges (the road law slice).
## terrain_gen owns the geometry laws (path, bed, bridge deck); this
## resource owns the data-driven travel + material story: what a road
## is made of, how fast you cross it, and whether beasts keep off it.
## The law's built-in palettes stay the fallback; a loaded RoadData
## can re-tint via the data service.

enum RoadSurface {
	DIRT,        ## packed earth trail
	GRAVEL,      ## crushed stone
	COBBLE,      ## cobblestone highway
	PLANK,       ## timber deck (the bridge law's surface)
	STONE_SLAB,  ## capitol-grade flagstone
}

@export var id: String = ""
@export var display_name: String = "Road"
@export var description: String = ""

@export var surface: RoadSurface = RoadSurface.DIRT

## Walk/ride speed multiplier ON this surface (1.0 = no benefit).
## Cobble outranks dirt; trails stay honest. Above 1.3 is late-game.
@export var speed_multiplier: float = 1.05

## Beasts keep this far off the cartway (meters) - spawn placement and
## the aggro gate both read it (the road respect law, terrain_gen's
## ROAD_CLEAR_ANG is the built-in default belt ~600 m).
@export var clearance_m: float = 600.0

## Banded tint the vertex law can blend to (surface fallback paint).
@export var tint: Color = Color(0.5, 0.38, 0.26, 1.0)

## Bridges on this road class: deck law + deck visual id (the mesh
## builder owns shapes later; v1 decks are walk law + plank tint).
@export var allow_bridges: bool = true
@export var deck_visual_id: String = "plank_simple"

## Quest tie-in hooks (the pathing quests can follow a road id).
@export var quest_followable: bool = true
