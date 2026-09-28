## InstanceContract - the S9 instances/lobby contract constants
## (prd-spherical-mvp.md S9). Locked decision 3: instances (arena,
## duel, dungeon) are PLANAR AABB worlds with vanilla -Y gravity,
## whatever the world shape knob says. This file is the single
## reference for what an instance promises the entities inside it;
## InstanceService serves it per zone, ZoneManager owns the instance
## lifecycle underneath (create_instance / destroy_instance /
## capacity), and future instance scenes consume it instead of
## hardcoding gravity or lobby rules per scene.
##
## Frame-style static helper: no autoload, no GameManager dependency.
extends RefCounted

class_name InstanceContract

## The gravity contract: every instanced world pulls straight down
## (global -Y) with this acceleration, regardless of
## synmergia/world/shape. Radial gravity NEVER reaches instances
## (locked decision 3; the spherical ground path is quarantined to
## the globe scene).
const GRAVITY_FORCE: float = 20.0
const UP_DIRECTION: Vector3 = Vector3(0, 1, 0)

## Default entry deadline (seconds) a lobby waits for a full party
## before auto-launching short-handed. ZoneData can override per zone
## (see instance_entry_deadline below).
const DEFAULT_ENTRY_DEADLINE: float = 20.0

## Lobby states for one instance's front door.
enum LobbyState {
	OPEN,       ## Accepting join requests (seats remain)
	FULL,       ## Capacity reached; waiting to start
	LOCKED,     ## Started; no new entrants
	CLOSED      ## Teardown pending; not accepting anyone
}

## What kind of bout an instance hosts (owner decision, 2026-09-28:
## modes are a contract-level concept, baked in BEFORE S10 wiring so
## later modes never retrofit the bout controller).
enum InstanceMode {
	ELIMINATION,     ## One life; last team standing wins (duels)
	TEAM_DEATHMATCH, ## Respawn + shield; first team to kill target
	ROYALE           ## Reserved: shrinking bounds, later session
}

## Contract defaults per mode. ZoneData exports can override
## kill_target / time_limit_seconds / spawn_shield_seconds per zone
## (see zone_data.gd instance_* fields); bout_rules() applies them.
const DEFAULT_KILL_TARGET: int = 25
const DEFAULT_TIME_LIMIT_SECONDS: float = 600.0
const DEFAULT_SPAWN_SHIELD_SECONDS: float = 4.0
##
## Spawn-shield conduct (owner decision, S11 goals): the shield is
## fire-and-you-lose-it. Any SELF-INITIATED action (attack, skill
## cast, potion, self-buff) breaks it; received effects (team aura,
## aoe heal, buffs from others) never do. Combat bridge enforces via
## ArenaFighter.break_shield().

## Planar-gravity guarantee for an instanced zone. Instances ignore
## the world shape knob entirely; this returns the values an instance
## scene must set on its physics bodies. Pure function of nothing --
## the contract is constant by design.
static func gravity_contract() -> Dictionary:
	return {
		"gravity_force": GRAVITY_FORCE,
		"up_direction": UP_DIRECTION,
		"shape": "planar",
	}

## Effective entry deadline for a zone: the ZoneData override wins
## when positive, otherwise the shared default. Duck-typed read so
## hand-built ZoneData (no instance_entry_deadline yet) still works.
static func entry_deadline(zone) -> float:
	if zone != null and "instance_entry_deadline" in zone:
		var d = zone.instance_entry_deadline
		if d > 0.0:
			return d
	return DEFAULT_ENTRY_DEADLINE

## Everything a bout controller needs for one zone, derived from its
## InstanceMode. Pure function; duck-typed zone reads (hand-built or
## old ZoneData without the exports still resolve). ELIMINATION has
## no respawn and no kill target; TEAM_DEATHMATCH respawns under a
## spawn shield and races to kill_target; ROYALE reports the same
## shape so controllers can be written against one dict.
static func bout_rules(zone) -> Dictionary:
	var mode := int(InstanceMode.ELIMINATION)
	if zone != null and "instance_mode" in zone:
		mode = int(zone.instance_mode)
	var kill_target := DEFAULT_KILL_TARGET
	if zone != null and "instance_kill_target" in zone:
		var kt = int(zone.instance_kill_target)
		if kt > 0:
			kill_target = kt
	var time_limit := DEFAULT_TIME_LIMIT_SECONDS
	if zone != null and "instance_time_limit" in zone:
		var tl = float(zone.instance_time_limit)
		if tl > 0.0:
			time_limit = tl
	var shield := DEFAULT_SPAWN_SHIELD_SECONDS
	if zone != null and "instance_spawn_shield" in zone:
		var ss = float(zone.instance_spawn_shield)
		if ss > 0.0:
			shield = ss
	match mode:
		InstanceMode.ELIMINATION:
			return {
				"mode": mode,
				"respawn_allowed": false,
				"kill_target": 0,
				"time_limit_seconds": time_limit,
				"spawn_shield_seconds": 0.0,
			}
		InstanceMode.TEAM_DEATHMATCH:
			return {
				"mode": mode,
				"respawn_allowed": true,
				"kill_target": kill_target,
				"time_limit_seconds": time_limit,
				"spawn_shield_seconds": shield,
			}
		InstanceMode.ROYALE:
			return {
				"mode": mode,
				"respawn_allowed": false,
				"kill_target": 0,
				"time_limit_seconds": time_limit,
				"spawn_shield_seconds": 0.0,
			}
	return bout_rules(null)

## Lobby state for one instance, derived from ZoneManager's instance
## dict shape ({"players": [...], "zone_data": ZoneData}). Pure
## function so probes and future lobby UI agree with the service.
## full_when_started: an already-started instance reports LOCKED.
static func lobby_state_for(instance_data: Dictionary, started: bool) -> int:
	if instance_data.is_empty():
		return LobbyState.CLOSED
	var cap := 0
	var zdata = instance_data.get("zone_data")
	if zdata != null and "instance_capacity" in zdata:
		cap = int(zdata.instance_capacity)
	var count := 0
	var players = instance_data.get("players", [])
	if players is Array:
		count = players.size()
	if started:
		return LobbyState.LOCKED
	if cap > 0 and count >= cap:
		return LobbyState.FULL
	return LobbyState.OPEN

## Does a candidate party fit one instance's remaining seats?
## Party of one (solo) fits unless FULL/LOCKED. Pure function.
static func party_fits(instance_data: Dictionary, party_size: int, started: bool) -> bool:
	var state := lobby_state_for(instance_data, started)
	if state != LobbyState.OPEN:
		return false
	var cap := 0
	var zdata = instance_data.get("zone_data")
	if zdata != null and "instance_capacity" in zdata:
		cap = int(zdata.instance_capacity)
	var count := 0
	var players = instance_data.get("players", [])
	if players is Array:
		count = players.size()
	return cap <= 0 or count + party_size <= cap
