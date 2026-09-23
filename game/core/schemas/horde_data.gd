## HordeData - Data-driven horde/wave event configuration.
##
## Turns HordeEventService.start_horde(zone_id, config: Dictionary) into
## a content pipeline: designers author .tres files under
## data/hordes/ and trigger them by name (/horde <config_id>), instead
## of services hard-coding wave compositions in dictionaries.
##
## Wave composition is MIXED-TEMPLATE: each wave carries its own enemy
## template ids (and optional per-wave reward override), so a horde can
## open with trash, escalate to elites, and finish on the boss without
## any code change.
##
## Wave shape (plain Dictionary -- inner classes do not survive .tres
## sub_resource serialization, so waves are data, not typed resources):
##   {
##     "spawns": [{"template_id": "slime", "count": 8}, ...],
##     "reward_gold": -1,   # -1 = inherit horde-level reward
##     "reward_xp": -1,
##   }
##
## Consumption: HordeEventService.start_horde_from_config(config_id)
## loads the .tres via HordeDataResolver (convention path -> DataService)
## and applies it over the runtime config dictionary. Storage follows
## the loot-table resolver convention (data/loot_tables pattern).
extends Resource
class_name HordeData

## Stable id (== file stem convention: horde_<id>.tres in data/hordes/).
@export var id: String = ""
## Display name for notifications ("A Trollmoot approaches...").
@export var display_name: String = ""
## Waves in order, each a Dictionary per the shape above. Empty = fall
## back to waves/mobs_per_wave runtime config (the plain-horde path
## stays fully functional).
@export var waves: Array = []

## Boss finale: template id (DataService.get_enemy) + display name.
## Empty template_id = finish after the last wave (no boss).
@export var boss_template_id: String = ""
@export var boss_name: String = ""

## Completion payout distributed proportionally by participation.
@export var reward_gold: int = 0
@export var reward_xp: int = 0

## Wave N spawns at level + N-1 (the runtime scale_levels lever).
@export var scale_levels: bool = false
## Seconds between waves.
@export var inter_wave_delay: float = 5.0

## Instance scoping: "" = zone-scoped (default, open world). Otherwise
## the horde projects under /world/instances/<instance_scope>/ instead
## of /world/zones/<zone>/ (dungeon/arena hordes keep their state out
## of overworld zone snapshots). Values match instance-type names in
## data/roots/world/instance_types/ (dungeon, raid, arena).
@export var instance_scope: String = ""

## Flatten to the runtime config Dictionary start_horde() consumes.
## wave_defs, when present, replaces the flat waves/mobs_per_wave pair.
func to_config() -> Dictionary:
	var cfg: Dictionary = {
		"reward_gold": reward_gold,
		"reward_xp": reward_xp,
		"scale_levels": scale_levels,
		"inter_wave_delay": inter_wave_delay,
		"instance_scope": instance_scope,
	}
	# Bossless hordes are valid: with no boss_template_id, start_horde
	# finishes the horde after the last wave instead of spawning a boss.
	if boss_template_id != "":
		cfg["boss_template_id"] = boss_template_id
		cfg["boss_name"] = boss_name
	if not waves.is_empty():
		# The wave count IS the def count: without this, start_horde
		# defaults to 3 and runs phantom waves past the authored list
		# (a 2-def config would spawn an empty wave 3).
		cfg["waves"] = waves.size()
		var defs: Array = []
		for w in waves:
			if w is Dictionary:
				var spawns: Array = []
				for s in w.get("spawns", []):
					if s is Dictionary and str(s.get("template_id", "")) != "" \
							and int(s.get("count", 0)) > 0:
						spawns.append({
							"template_id": str(s["template_id"]),
							"count": int(s["count"]),
						})
				defs.append({
					"spawns": spawns,
					"reward_gold": int(w.get("reward_gold", -1)),
					"reward_xp": int(w.get("reward_xp", -1)),
				})
		cfg["wave_defs"] = defs
	return cfg

## First wave's first template (used when start_horde's template_id
## stays empty so horde_started UI/notification has a sane fallback).
func first_template_id() -> String:
	for w in waves:
		if w is Dictionary:
			for s in w.get("spawns", []):
				if s is Dictionary and s.has("template_id"):
					return str(s["template_id"])
	return ""
