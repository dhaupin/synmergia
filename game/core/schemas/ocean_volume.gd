## OceanVolume - data-driven water infrastructure (S14.1,
## labs/prd-ocean-depths.md sec 2: "water is data").
##
## Water is a first-class data resource exactly like ThermalUpdraft:
## the renderer paints it, the physics reads it, the anticheat reads
## it, and nobody hardcodes a coastline. Oceans are volumes with a
## surface you cross (thermals are volumes you pass through) -- the
## mirror of the sky's layering below the waterline.
##
## Layering (prd-ocean-depths sec 2): the vertical story mirrors the
## sky. Ground (S3-S8), thermals up (S12), ocean down (S14). Every
## layer below the surface is content, traversal, or economy on its
## own.
##
## The radial world note: the globe is a sphere, so a volume's
## "surface_height" is a WORLD-Y PLANE in the current scenes (the
## playable world and the moon crater are small enough that a plane
## is honest). sample_depth clamps to the radial floor so no one
## swims through rock -- the floor is read from the same
## distance-to-center geometry the globe walk uses, one collision
## truth (prd sec 2 "terrain respect").
##
## Schema: filename == id, "ocean_" prefix (naming conventions
## locked; water ids are data like thermals and hitboxes). Placed in
## data/oceans/ and resolved by OceanService.
extends Resource
class_name OceanVolume

## Depth bands (prd sec 3): swim -> squeeze -> crush. The ocean has
## teeth like the storm has teeth -- optional teeth: you choose to
## go deep.
enum DepthBand {
	DRY,       ## above the waterline (sample_depth < 0)
	WADING,    ## ankle-deep: walk slowdown, no swim yet
	SUBMERGED, ## full swim (the band the movement class owns)
	SQUEEZE,   ## below max_depth - grace: pressure ramps, vision closes
	CRUSH,     ## below max_depth: fast drain -- the ocean saying no
}

## The liquid's body: WATER is the standard swim law; LAVA is the
## underworld's own frame (the same sampler, the same bands -- a body
## in lava "swims" the way it swims, only the lake bites). Molten
## water is still water-as-data; the teeth live on the volume.
enum Liquid {
	WATER,
	LAVA,
}

@export var id: String = ""
@export var display_name: String = ""
## The waterline (world Y). The renderer paints up to here; physics
## reads the crossing; the sign discipline (negative above water)
## lives in OceanService.sample_depth.
@export var surface_height: float = 0.0
## THE FLOOR, two honest models (sample_depth picks per volume):
##
## WORLD-SHELL ocean (the shelf): the rock is a radial sphere --
## floor_center names the world center the shell wraps, floor_radius
## its radius (main world: center ZERO, radius 20000). Set
## floor_is_radial = true.
##
## LOCAL pool (a crater bowl, a flooded quarry): the rock is a
## PLANE at floor_y -- floor_center.y holds the rock's world Y and
## floor_is_radial = false. A dished pool near a globe's surface is
## LOCAL geometry: radial-from-planet-center would put "the rock"
## on the far side of the world.
@export var floor_is_radial: bool = true
@export var floor_center: Vector3 = Vector3.ZERO
@export var floor_radius: float = 0.0
@export var floor_y: float = 0.0
## THE WATERLINE, second model (S14.7): a RADIAL waterline. The
## plane waterline (surface_height, world Y) is only honest where a
## scene is small enough for a plane to lie -- it is NOT honest for
## the world sea on a 20 km globe, where the waterline is a SPHERE.
## A volume with waterline_is_radial = true reads its waterline at
## the world's own sea truth: radius == the shell radius plus
## TerrainGen.sea_level (the seed's sea -- OceanService resolves
## the number once; data stays pure and can never disagree with the
## terrain that paints the water). sample_depth then measures the
## body's radial column the same way the plane model does: negative
## above the line, meters-below below it, -1 inside the rock.
@export var waterline_is_radial: bool = false
## How deep the swimmable water goes before the SQUEEZE band starts
## (meters below the surface along the down axis).
@export var max_depth: float = 60.0
## Currents are weather for water (prd sec 2): drift vector in m/s.
@export var current_direction: Vector3 = Vector3.ZERO
@export var current_strength: float = 0.0
## THE TERRAIN CURRENTS (the river flow law): when on, this volume's
## current composes with terrain_gen's river flow and standing-water
## drift read at the body's planet direction (radial shells only --
## floor_center names the planet center the law maps from).
@export var terrain_currents: bool = false
## The depth tax (prd sec 4): pressure damage per second per meter
## in the SQUEEZE band. 0.0 = a tame pool (the moon crater starts
## tame -- it is a workshop test pool, not a monster).
@export var pressure_per_meter: float = 0.1
## Salinity 0..1: 0 = the dead lakes (swimmable, no currents,
## nothing lives there); future: buoyancy flavor.
@export var salinity: float = 1.0
## The liquid body (WATER default). LAVA volumes declare burn_dps:
## the underworld's rivers and lakes are water-frame truth, not a
## second sampler -- the bands read the same, and the lake BURNS.
@export var liquid: Liquid = Liquid.WATER
## Damage per second a body takes while standing or swimming in a
## LAVA volume (0.0 for WATER; a body at depth never touches fire).
@export var burn_dps: float = 0.0
## The look (renderer reads; physics ignores).
@export var ambient_fog_color: Color = Color(0.1, 0.3, 0.45)
@export var ambient_fog_density: float = 0.02
## AudioService names for the volume (muffled lapping, the deep).
@export var ambient_sounds: Array[String] = []
## Worldbuilding notes (what this water is FOR).
@export_multiline var lore: String = ""


## The natural pressure-free band (m): the SQUEEZE line sits this
## far above max_depth for an unbreathered body. Breathes (S14.4)
## push the line DEEPER -- grace extends the free swim toward the
## rock; crush never moves (gear extends the swim, not the stone's
## patience).
const NATURAL_PRESSURE_FREE_M: float = 10.0


## The band a sample depth belongs to. Pure function of the depth
## and this volume's declared bands -- the same mapping for physics,
## renderer, and anticheat (one sampler, three readers).
func band_for(depth_m: float, breather_grace_m: float = 0.0, crush_bonus_m: float = 0.0) -> DepthBand:
	if depth_m < 0.0:
		return DepthBand.DRY
	if depth_m <= 1.2:
		return DepthBand.WADING
	# CRUSH moves ONLY for a rated body (S14.6: the trench wyrm's
	# crush_depth_bonus_m is the body's rating). Gear grace -- breather
	# or mount squeeze_grace_m -- never moves it: the stone bends for
	# rated bodies, never for equipment.
	if depth_m >= max_depth + maxf(crush_bonus_m, 0.0):
		return DepthBand.CRUSH
	# SQUEEZE line = max_depth - natural_free + total gear grace: the
	# line DEEPENS as breathers and mount grace improve (50 m -> 58 m
	# with grace 8 on a 60 m volume). A big enough grace removes the
	# squeeze band entirely.
	if depth_m >= max_depth - NATURAL_PRESSURE_FREE_M + breather_grace_m:
		return DepthBand.SQUEEZE
	return DepthBand.SUBMERGED


## The current's push at full strength (currents push a swimmer;
## a ferry uses them -- prd sec 4 drag model).
func current_vector() -> Vector3:
	return current_direction.normalized() * current_strength if current_strength > 0.0 else Vector3.ZERO
