## WorldHazard - the one hazard vocabulary for gear-driven world mitigation.
##
## Tablets are not combat resist gear. Their `tablet_world_ward` and
## `tablet_domain_ward` answer authored environmental hazards (heat, cold,
## storm, miasma, deep, void). This helper owns the key list and the terminal
## arithmetic so every future source -- sea pressure, weather exposure, a
## trap -- reads the same lane instead of inventing a second resist table.
##
## `drowning` is an alias for `deep`: the sea's damage driver tags its
## pressure/drowning bite with that existing name, while a DEEP tablet's
## focus is authored as `deep`.
extends RefCounted
class_name WorldHazard

const StatId = preload("res://core/schemas/stat_id.gd")

const HAZARDS: Array = ["heat", "cold", "storm", "miasma", "deep", "void"]

const ALIASES: Dictionary = {
	"drowning": "deep",
	"pressure": "deep",
}

## Canonical key for an authored/legacy hazard name. Unknown names pass
## through lower-case so a caller cannot accidentally match every tablet.
static func normalize(hazard: String) -> String:
	var key := hazard.strip_edges().to_lower()
	return str(ALIASES.get(key, key))

## True only for the authored hazard vocabulary (alias forms included).
## Combat schools (fire, frost, ...) deliberately do NOT match: those ride
## `damage_resists`, not the tablet lane.
static func is_hazard(hazard: String) -> bool:
	return HAZARDS.has(normalize(hazard))

## The body's tablet ward for a hazard, clamped to the canonical resist cap.
static func ward_for(body, hazard: String) -> float:
	if body == null or not body.has_method("get_world_ward"):
		return 0.0
	return clampf(float(body.get_world_ward(normalize(hazard))), 0.0, StatId.MAX_RESIST)

## Apply a tablet ward to an incoming environmental amount. A landed hazard
## still costs at least 1 point, matching the combat lane's floor.
static func mitigate(body, amount: int, hazard: String) -> int:
	if amount <= 0 or not is_hazard(hazard):
		return maxi(amount, 0)
	var ward := ward_for(body, hazard)
	if ward <= 0.0:
		return amount
	return maxi(1, int(ceil(float(amount) * (1.0 - ward))))
