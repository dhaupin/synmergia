## RecipeData - one crafting recipe (S16.9, prd-crafting.md).
## Third leg of the economy loop beside gathering (inputs) and the
## blacksmith (upgrade). A recipe is DATA TRUTH like every catalog
## here: inputs, station, output, byproducts, and the failure
## posture. The service invents nothing; the ITEM ids are DataService
## truth and the world delta carries the bill as provenance.
##
## Data-id conventions: filename == id, recipe_ prefix
## (data/recipes/recipe_iron_ingot.tres).
extends Resource
class_name RecipeData

enum Station {
	NONE,        ## hand-craft (anywhere)
	FORGE,       ## the blacksmith's forge
	WORKBENCH,   ## carpentry / tinkering
	ALCHEMY,     ## the cauldron
}

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""

@export var station: Station = Station.NONE

## The bill of materials: [{item_id, qty}]. All-or-nothing (the purse
## is checked for ALL inputs before anything is consumed -- no
## partial consumes, the forge does not eat what you did not bring).
@export var inputs: Array[Dictionary] = []

## The lawful output: {item_id, qty}.
@export var output: Dictionary = {}

## Byproducts granted on FAILURE (slag, scraps -- the economy sink:
## a failed forge still feeds the loop). Empty = the forge eats all.
@export var byproducts: Array[Dictionary] = []

## 0.0 = instant craft; >0.0 = a timed forge, v2 (start/finish world
## deltas -- a craft you can walk away from is a craft you can lose).
@export var craft_time_sec: float = 0.0

@export var required_level: int = 1

## Failure posture (fraction 0..1). On failure byproducts drop and the
## inputs are GONE. Data truth, so a designer reads the gamble.
@export var failure_rate: float = 0.0
