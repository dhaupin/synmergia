## HouseData - the STRUCTURE a player raises on an owned plot.
##
## Three tiers on one plot (labs/prompts/gemini_housing.md sec. 1):
##   CLAIM    - a timber-frame salvage-canvas tent; the cheapest roof.
##   COTTAGE  - a one-room timber cottage with a moss sedum roof.
##   HALL     - a two-story home built against a half-buried machine hull.
##
## The tier is DATA, not code: HousingService.build_house reads a
## HouseData and stamps the plot's house_id from it. Cost, footprint, wall
## height, door width and roof pitch all live here so a new tier ships as
## a .tres, never a service edit. Geometry is still built procedurally
## (no per-tier scene yet) -- model_path is the seam for authored meshes.
extends Resource
class_name HouseData

enum Tier {
	CLAIM,    # tent: canvas over a timber frame
	COTTAGE,  # one-room timber, sedum roof
	HALL,     # two-story, machine-leech, stable bay + bell tower
}

@export var id: String = ""
@export var display_name: String = "House"
@export var description: String = ""

# Tier + economics. cost is the gold the plot owner pays to raise it.
@export var tier: Tier = Tier.COTTAGE
@export var cost: int = 750000

# Geometry (metres). footprint is the exterior floor size (x = width,
# z = depth); wall_height is floor-to-eaves; door_width is the front gap;
# roof_pitch is the gable slab rotation in radians.
@export var footprint: Vector3 = Vector3(6.0, 0.2, 6.0)
@export var wall_height: float = 3.0
@export var door_width: float = 1.4
@export var roof_pitch: float = 0.5

# Presentation
@export var icon_path: String = ""
@export var model_path: String = ""
@export var wall_color: Color = Color(0.55, 0.38, 0.22)
@export var roof_color: Color = Color(0.35, 0.2, 0.14)

# Structural features a tier advertises (stable bay, bell tower, finial).
@export var features: Array[String] = []


func has_feature(feature: String) -> bool:
	return features.has(feature)


func get_info() -> Dictionary:
	return {
		"id": id,
		"name": display_name,
		"tier": Tier.keys()[tier],
		"cost": cost,
		"footprint": footprint,
		"features": features,
	}
