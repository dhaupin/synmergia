## BiomeBand - formal biome data for conjured worlds (S15.6: the Deep
## Wilds' law made data). The planet's own climate hides in
## TerrainGen's closed form; the underworld (and future planet-in-
## planet globes) can afford a smaller, honest truth: each biome is a
## BAND around the settlement seat declaring which scatter family
## walks there, how loud it is (count), where its skirt spans
## (radii), and how it paints (palette). Conjured builders read the
## declarations; nothing hardcodes flora.
##
## Schema: filename == id, "biome_" prefix. Placed in data/biomes/
## and resolved by the conjured globe's own scan (world_id filter).
extends Resource
class_name BiomeBand

## The scatter families a conjured builder knows how to place.
enum Family {
	CRAG,        ## big stone prisms (standable,fendered)
	DEAD_TREE,   ## charcoal trunk + bare forks (standable)
	MYCELIUM,    ## glow cap clumps (walk-over paint)
	STALAGMITE,  ## pale stone spikes (standable)
	GRASS,       ## luminous blade tufts (walk-over paint)
}

@export var id: String = ""
@export var display_name: String = "Deep Band"
## Which world owns the band (the biome book filters on this).
@export var world_id: String = "underworld"
## Which scatter family builds it.
@export var family: Family = Family.GRASS
## The band's geometry around the world's seat (m).
@export var radius_inner_m: float = 16.0
@export var radius_outer_m: float = 70.0
## Scatter phase (rad): keeps families off the same spokes honestly.
@export var angular_offset: float = 0.0
## How many seats the band holds (each seat may carry sub_count pieces).
@export var count: int = 10
@export var sub_count: int = 1
## "stone" pieces carry colliders (walk-over law's opposite); "paint"
## never blocks a foot.
@export_enum("stone", "paint") var collider_mode: String = "paint"
## The palette (the dusk-read law: a band carries its own glow).
@export var palette_dark: Color = Color(0.14, 0.12, 0.16)
@export var palette_accent: Color = Color(0.2, 0.18, 0.23)
@export var palette_emission: Color = Color(0.35, 0.8, 0.55)
@export var emission_energy: float = 0.6
## The apron (simple zone law): seats stay this far from the world's
## gates/landmark keeps so a crag never walls an arrival in (0 = no
## keep-clear).
@export var clearance_m: float = 0.0
## Worldbuilding notes (what this band is FOR).
@export_multiline var lore: String = ""


## The seat count for this band's placement loop (never below one).
func seat_count() -> int:
	return maxi(count, 1)
