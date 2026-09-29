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

## ---- S13 ROYALE storm (the fog wall) ------------------------------------
## The bounds close with the horde phase-timer shape the shard already
## uses: STORM_* phases tick in order, each holds then shrinks. The
## "fog" is the Sundered Valley's weather_type = "fog" made into a
## rule: a closing wall of ancient wind, not a cosmetic. Outside the
## wall the storm grinds you down (DAMAGE is the wall's teeth -- PUSH
## would shove campers into each other and be read as a mechanic,
## not a punishment). Time limit stays as the DRAW backstop (locked
## decision); the storm is the primary clock.
const STORM_PHASES: Array = [
	{"hold": 60.0, "shrink": 30.0, "radius_ratio": 0.65, "damage": 1.0},
	{"hold": 45.0, "shrink": 30.0, "radius_ratio": 0.40, "damage": 2.0},
	{"hold": 30.0, "shrink": 30.0, "radius_ratio": 0.22, "damage": 4.0},
	{"hold": 30.0, "shrink": 45.0, "radius_ratio": 0.10, "damage": 7.0},
	# NO QUARTER (owner, 2026-09-29): the last phase closes to ZERO --
	# no safe circle, no camper's point, the fog takes everyone still
	# standing at 10 dps. The draw clock becomes mathematically
	# unreachable in a live bout: the ladder ends the argument.
	{"hold": 20.0, "shrink": 30.0, "radius_ratio": 0.0, "damage": 10.0},
]

## The storm's final safe radius as a fraction of the room half
## (clamped by MIN_STORM_RADIUS_M so a tiny zone never closes to
## nothing): 10 fighters in a 5 m circle is a knife fight, which is
## the point of the last phase.
const MIN_STORM_RADIUS_M: float = 5.0

## Total storm length (sum of holds + shrinks) for schedules/UI.
static func storm_total_seconds() -> float:
	var t := 0.0
	for p in STORM_PHASES:
		t += float(p.get("hold", 0.0)) + float(p.get("shrink", 0.0))
	return t


## The storm plan for one bout: radius ratios resolved against the
## room's half-extent into absolute safe radii. Pure function so
## probes, UI and the room agree on one truth. A phase with
## radius_ratio <= 0.0 means a TRUE ZERO circle (no quarter): the
## MIN_STORM_RADIUS_M floor applies only to positive ratios.
static func storm_plan(room_half: float) -> Dictionary:
	var phases: Array = []
	var t := 0.0
	for p in STORM_PHASES:
		var ratio: float = float(p.get("radius_ratio", 0.5))
		var end_radius: float = room_half * ratio
		if ratio > 0.0:
			end_radius = maxf(end_radius, MIN_STORM_RADIUS_M)
		phases.append({
			"start": t,
			"end": t + float(p.get("hold", 0.0)) + float(p.get("shrink", 0.0)),
			"shrink_start": t + float(p.get("hold", 0.0)),
			"radius": end_radius,
			"damage": float(p.get("damage", 1.0)),
		})
		t = phases[-1]["end"]
	return {"phases": phases, "total": t}


## The storm's safe radius at bout-time `elapsed` (0 before the storm
## starts). Pure function; the room lerps between shrinks.
static func storm_radius_at(plan: Dictionary, elapsed: float, start_radius: float) -> float:
	var prev: float = start_radius
	var phases: Array = plan.get("phases", [])
	for p in phases:
		var shrink_start: float = float(p.get("shrink_start", 0.0))
		var phase_end: float = float(p.get("end", 0.0))
		var target: float = float(p.get("radius", 0.0))
		if elapsed <= shrink_start:
			return prev
		if elapsed >= phase_end:
			prev = target
			continue
		var t: float = (elapsed - shrink_start) / maxf(phase_end - shrink_start, 0.001)
		return lerpf(prev, target, t)
	return prev


## Storm damage per second at bout-time `elapsed` (0 = outside any
## live storm phase).
static func storm_damage_at(plan: Dictionary, elapsed: float) -> float:
	for p in plan.get("phases", []):
		if elapsed >= float(p.get("start", 0.0)) and elapsed < float(p.get("end", 0.0)):
			return float(p.get("damage", 1.0))
	return 0.0

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
## S13 ROYALE storm defaults: the wall arms this long after the bout
## starts (the drop and first looting stay calm), then walks inward
## phase by phase (STORM_PHASES above). ZoneData overrides via
## instance_storm_start; a negative value disables the wall entirely.
const DEFAULT_STORM_START_SECONDS: float = 45.0
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
			var storm_phase := DEFAULT_STORM_START_SECONDS
			if zone != null and "instance_storm_start" in zone:
				var ss = float(zone.instance_storm_start)
				if ss != 0.0:
					storm_phase = ss
			var storm_scale := 1.0
			if zone != null and "instance_storm_scale" in zone:
				var sc = float(zone.instance_storm_scale)
				if sc > 0.0:
					storm_scale = sc
			return {
				"mode": mode,
				"respawn_allowed": false,
				"kill_target": 0,
				"time_limit_seconds": time_limit,
				"spawn_shield_seconds": 0.0,
				# S13 storm: the fog wall. The phase ladder (holds, shrinks,
				# radii, per-phase damage) rides the rules dict so UI and
				# probes read the SAME plan the room enforces. Negative
				# storm_start disables the wall for a zone.
				"storm_start_seconds": storm_phase,
				"storm_scale": storm_scale,
				"storm_phases": STORM_PHASES.duplicate(true),
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


## ---- S11 lobby primitives (owner decisions, 2026-09-28) ---------------

## Scatter-spawn: deterministic radial jitter so simultaneously
## teleported fighters never stack (initial spawns, TDM respawns,
## ROYALE drop -- owner decision: EVERY teleport into a bout scatters).
## Golden-angle stepping gives an even ring with no clamping; index 0
## lands exactly on +X of the ring. Pure function.
const SCATTER_GOLDEN_ANGLE: float = 2.399963229728653

static func scatter_spawn(center: Vector3, index: int, ring_radius: float = 3.0) -> Vector3:
	var angle: float = float(index) * SCATTER_GOLDEN_ANGLE
	return center + Vector3(cos(angle) * ring_radius, 0.0, sin(angle) * ring_radius)


## Relative power normalization (owner decision: the lvl 5 vs lvl 60
## problem). Scales a level toward a reference with the boost CAPPED
## at max_boost_ratio so levels keep meaning: a 5 next to a 60 plays
## at 10, never at 60. Callers map the normalized level to bout-local
## stat scaling (AuraComponent buffs inside the room only -- real
## stats never change). 1.0 when at or above the reference.
static func normalized_level(level: int, reference_level: int, max_boost_ratio: float = 2.0) -> int:
	var lvl: int = maxi(level, 1)
	if reference_level <= lvl:
		return lvl
	var ratio: float = float(reference_level) / float(lvl)
	if ratio > max_boost_ratio:
		ratio = max_boost_ratio
	return int(round(float(lvl) * ratio))


## Level-band matchmaking. Raw distance with the band widening as the
## waiter's patience grows (queue head only): after WIDEN_AFTER seconds
## the distance halves, doubling effective reach. Absolute gulfs never
## pass -- a 5 and a 60 do not auto-assemble at any patience; that
## pairing requires the normalized-power consent path instead.
const LEVEL_BAND_BASE: int = 10
const LEVEL_BAND_WIDEN_AFTER_SECONDS: float = 30.0
const LEVEL_BAND_WIDEN_FACTOR: float = 2.0

static func level_band_distance(level_a: int, level_b: int, wait_seconds: float = 0.0) -> int:
	var dist: int = absi(level_a - level_b)
	if wait_seconds >= LEVEL_BAND_WIDEN_AFTER_SECONDS:
		dist = int(float(dist) / LEVEL_BAND_WIDEN_FACTOR)
	return dist

static func level_band_ok(level_a: int, level_b: int, wait_seconds: float = 0.0) -> bool:
	return level_band_distance(level_a, level_b, wait_seconds) <= LEVEL_BAND_BASE


## AFK kick (owner decision: the guy in the woods never stalls a bout
## again). A fighter idle this long inside a live bout is returned to
## their queue stone and the bout books it like a departure. ZoneData
## can override per zone (instance_afk_kick); 0 = disabled.
const DEFAULT_AFK_KICK_SECONDS: float = 90.0

static func afk_kick_seconds(zone) -> float:
	if zone != null and "instance_afk_kick" in zone:
		var v = zone.instance_afk_kick
		if v > 0.0:
			return float(v)
	return DEFAULT_AFK_KICK_SECONDS


## Relative power multiplier for one fighter inside a bout: their
## normalized level (capped boost) against the bout's reference -- the
## ratio is the combat scale. 1.0 at/above reference, never below 1.0
## (a stronger fighter is never nerfed). Pair with power_scale_target
## stats for the Entity.stats dictionary.
static func power_scale(level: int, reference_level: int, max_boost_ratio: float = 2.0) -> float:
	var lvl: int = maxi(level, 1)
	var norm := normalized_level(lvl, reference_level, max_boost_ratio)
	return maxf(float(norm) / float(lvl), 1.0)

## The six Entity stats a power scale multiplies (Entity.stats keys).
const POWER_SCALED_STATS: Array = [
	"strength", "agility", "intelligence", "vitality", "endurance", "wisdom",
]

## Per-stat scaled targets for one fighter. Non-scaled keys in the
## entity's stats (e.g. damage_multiplier) pass through untouched.
static func power_scale_target(stats: Dictionary, level: int, reference_level: int, max_boost_ratio: float = 2.0) -> Dictionary:
	var scale: float = power_scale(level, reference_level, max_boost_ratio)
	var out: Dictionary = {}
	for key in POWER_SCALED_STATS:
		out[key] = int(round(float(int(stats.get(key, 10))) * scale))
	return out
