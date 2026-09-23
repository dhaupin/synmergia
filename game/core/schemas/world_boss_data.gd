## WorldBossData - Timed open-world world-boss spawn schedule.
##
## Turns "a boss that spawns every few hours" into content: designers
## author .tres files under data/world_bosses/ and SpawnService boots
## the schedule (first spawn after an initial delay, respawn counted
## from the boss's DEATH, not from its spawn -- a boss killed 2 minutes
## after appearing does not skip its downtime).
##
## Shape (flat .tres, same style as HordeData):
##   id               stable id (== file stem convention: world_boss_<id>.tres)
##   boss_template_id EnemyData template id (DataService.get_enemy)
##   display_name     spawn-name override ("" = template's display_name)
##   zone_id          home zone (spawn at the zone center)
##   position         optional explicit spawn point (Vector3.ZERO = center)
##   interval_seconds respawn downtime after death (hours -> 3600*n)
##   first_delay_s    delay before the FIRST spawn after boot
##   announce         server-wide announcement on spawn (default true)
##   window_seconds   despawn timer while unclaimed (0 = stays until killed)
##   max_level_diff   reserved for future scaling (unused by SpawnService)
##
## Consumption: SpawnService.load_world_boss_schedules() scans the dir
## at _ready and starts each schedule; /boss schedule (admin) lists,
## runs, and stops them at runtime. Tests author schedules in code via
## to_config()/from_config() or stamp short intervals directly.
extends Resource
class_name WorldBossData

## Stable id (== file stem convention: world_boss_<id>.tres in
## data/world_bosses/).
@export var id: String = ""
## EnemyData template id resolved through DataService.get_enemy.
@export var boss_template_id: String = ""
## Spawn-name override; empty = the template's display_name.
@export var display_name: String = ""
## Home zone (ZoneManager.get_zone id). Spawn lands at the zone center
## unless position is set.
@export var zone_id: String = ""
## Explicit spawn position in world space; ZERO = zone center.
@export var position: Vector3 = Vector3.ZERO
## Respawn downtime counted from the boss's DEATH (seconds).
## "Every few hours" = 3600 * n. 0 disables the loop (spawn once).
@export var interval_seconds: float = 7200.0
## Delay before the first spawn after boot (seconds). Lets the server
## settle before the world boss arrives.
@export var first_delay_s: float = 60.0
## Server-wide spawn announcement (the classic world-boss callout).
@export var announce: bool = true
## Despawn timer while the boss is up and unclaimed (seconds; 0 = it
## stays until killed). Sweeps unengaged bosses so the world does not
## accumulate idle world bosses across days of uptime.
@export var window_seconds: float = 0.0

## Flatten to the runtime config Dictionary start_world_boss_schedule()
## consumes (mirrors HordeData.to_config).
func to_config() -> Dictionary:
	var cfg: Dictionary = {
		"boss_template_id": boss_template_id,
		"zone_id": zone_id,
		"interval_seconds": maxf(0.0, interval_seconds),
		"first_delay_s": maxf(0.0, first_delay_s),
		"announce": announce,
		"window_seconds": maxf(0.0, window_seconds),
	}
	if display_name != "":
		cfg["display_name"] = display_name
	if position != Vector3.ZERO:
		cfg["position"] = position
	return cfg

## Apply a runtime config Dictionary over this resource (tests and
## future editors build schedules in code).
func from_config(cfg: Dictionary) -> void:
	boss_template_id = str(cfg.get("boss_template_id", ""))
	zone_id = str(cfg.get("zone_id", ""))
	interval_seconds = maxf(0.0, float(cfg.get("interval_seconds", 0.0)))
	first_delay_s = maxf(0.0, float(cfg.get("first_delay_s", 0.0)))
	announce = bool(cfg.get("announce", true))
	window_seconds = maxf(0.0, float(cfg.get("window_seconds", 0.0)))
	display_name = str(cfg.get("display_name", ""))
	position = cfg.get("position", Vector3.ZERO) if cfg.has("position") else Vector3.ZERO
