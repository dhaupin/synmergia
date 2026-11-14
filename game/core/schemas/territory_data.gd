## TerritoryData - an ownership overlay over one or more ZoneData ids.
##
## Geography stays in ZoneData (bounds, pvp_mode, entry gates). A territory
## groups zones into the thing factions and guilds actually fight over, so
## ownership has ONE home instead of a dead array on FactionData.
##
## A zone belongs to at most one territory. Overlapping CLAIMS are expressed
## through `claimants`, not through overlapping zone IDs.
extends Resource
class_name TerritoryData

enum Controller {
	NONE,
	FACTION,
	GUILD
}

## Stable id (terr_ prefix, filename == id).
@export var id: String = ""
@export var display_name: String = "Unnamed Territory"
@export var description: String = ""

## ZoneData ids grouped by this territory. Empty = not yet mapped.
@export var zone_ids: Array[String] = []

## Who currently holds the territory. `claimants` is the contest record;
## this pair is the resolved controller the UI and combat rules read.
@export var controller: Controller = Controller.NONE
@export var controller_id: String = ""

## Every live claim, strongest first is NOT guaranteed: entries are
## {kind: Controller, id: String, influence: int, since: int}.
@export var claimants: Array[Dictionary] = []

## Set while a faction war is being fought over this territory.
@export var active_war_id: String = ""

## Capture verb: SIEGE, PVP_KILL, BOSS, EVENT. Content chooses the verb;
## TerritoryService does not invent mechanics for it.
@export var capture_rule: StringName = &"SIEGE"

## Optional content links. These are validated against their catalogs but
## never duplicate zone ownership; a horde/boss/event still anchors to a
## zone and resolves its territory through TerritoryService.
@export var horde_ids: Array[String] = []
@export var boss_ids: Array[String] = []
@export var event_ids: Array[String] = []

## -1 inherits the zone's PvP mode. A valid ZoneData.PvPZoneMode value
## overrides it for every zone in this territory.
@export var pvp_mode_override: int = -1


## A territory is contested when a war is live or more than one claim exists.
func is_contested() -> bool:
	return active_war_id != "" or claimants.size() > 1


## The resolved controller id, or "" for unclaimed.
func controller_key() -> String:
	return controller_id if controller != Controller.NONE else ""


## Context consumed by UI and service hooks.
func to_context() -> Dictionary:
	return {
		"territory_id": id,
		"display_name": display_name,
		"zone_ids": zone_ids.duplicate(),
		"controller": controller,
		"controller_id": controller_key(),
		"contested": is_contested(),
		"active_war_id": active_war_id,
		"capture_rule": String(capture_rule),
		"claimant_count": claimants.size()
	}
