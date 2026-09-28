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
