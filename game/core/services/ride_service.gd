## RideService - the riding layer across land, water, sky, and space
## mounts (labs/prd-mounts.md).
##
## One book per rider: what they OWN (persisted, the WaypointService/
## FerryService DictStore idiom) and what they are RIDING (session
## truth -- summon again next login, like the ferry manifest).
##
## The service is the STAMPING seam. summon resolves the mount's
## MovementProfile through DataService.get_mount_movement_profile
## (one derivation -- the Movement Design System owns speeds) and
## stamps the anticheat; the water handoff returns the S14.6 stamp
## (swim/dismount/ride) so the band laws live in exactly one place.
## Space mounts are already lawful: MountKind.SPACE rides this same
## path and its profile (movement_lunar-class) owns the gravity.
##
## Acquisition difficulty lives in the DATA (source, required_level,
## the drop's rarity); the service is the ledger, never the gate.
extends Node

const DictStore = preload("res://adapters/persistence/dict_store.gd")
const SwimStateScript = preload("res://core/frame/srv/swim_state.gd")

const _KV: String = "ride_service/mounts/"

var _owned: Dictionary = {}    # player_id -> {mount_id: true}
var _active: Dictionary = {}   # player_id -> mount_id (session truth)


## -- Ownership ---------------------------------------------------------

func _owned_key(player_id: String) -> String:
	return _KV + player_id


func _load_owned(player_id: String) -> void:
	if _owned.has(player_id):
		return
	var store := DictStore.new()
	var row = store.get_kv(_owned_key(player_id), null)
	var book: Dictionary = {}
	if row is Dictionary:
		for mount_id in row.keys():
			book[str(mount_id)] = true
	_owned[player_id] = book


func _persist_owned(player_id: String) -> void:
	var store := DictStore.new()
	var book: Dictionary = _owned.get(player_id, {})
	if book.is_empty():
		store.erase(_owned_key(player_id))
	else:
		store.set_kv(_owned_key(player_id), book.duplicate())


func owns_mount(player_id: String, mount_id: String) -> bool:
	_load_owned(player_id)
	return _owned[player_id].has(mount_id)


## Grant a mount into the rider's book. Refuses unknown mounts (data
## is the id truth) and duplicates (soulbound is the default posture).
## Quests, drops, vendors, and events all call THIS -- one ledger.
func grant_mount(player_id: String, mount_id: String) -> bool:
	if DataService == null or DataService.get_mount(mount_id) == null:
		GameLog.warn("RideService: grant refused, unknown mount: " + mount_id)
		return false
	_load_owned(player_id)
	if _owned[player_id].has(mount_id):
		return false
	_owned[player_id][mount_id] = true
	_persist_owned(player_id)
	return true


## Revoke (GM/moderation path): removes ownership and dismisses the
## mount if it was active.
func revoke_mount(player_id: String, mount_id: String) -> bool:
	_load_owned(player_id)
	if not _owned[player_id].has(mount_id):
		return false
	_owned[player_id].erase(mount_id)
	_persist_owned(player_id)
	if active_mount_id(player_id) == mount_id:
		dismiss(player_id)
	return true


## -- Riding ------------------------------------------------------------

func active_mount_id(player_id: String) -> String:
	return str(_active.get(player_id, ""))


## The MountData being ridden right now (null when unmounted).
func active_mount(player_id: String):
	var mount_id := active_mount_id(player_id)
	if mount_id.is_empty() or DataService == null:
		return null
	return DataService.get_mount(mount_id)


## Summon an owned mount: session truth + the anticheat stamp from the
## mount's own MovementProfile (one derivation; MountKind.SPACE rides
## the same path). Returns false for unowned/unknown mounts.
func summon(player_id: String, mount_id: String) -> bool:
	if not owns_mount(player_id, mount_id):
		GameLog.warn("RideService: summon refused, not owned: " + mount_id)
		return false
	var mount = DataService.get_mount(mount_id)
	if mount == null:
		return false
	_active[player_id] = mount_id
	var profile = DataService.get_mount_movement_profile(mount)
	if AntiCheatService:
		if profile != null:
			AntiCheatService.set_profile_limits(player_id, str(profile.id))
		else:
			AntiCheatService.set_profile_limits(player_id, "movement_standard")
	return true


## Dismount: clear the session book and hand the body back humanoid
## limits (the safe default -- the rider's own profile re-stamps on
## their next _apply_movement_profile).
func dismiss(player_id: String) -> bool:
	if not _active.has(player_id):
		return false
	_active.erase(player_id)
	if AntiCheatService:
		AntiCheatService.set_profile_limits(player_id, "movement_standard")
	return true


## The S14.6 water handoff in one call: what happens to the rider at
## this band. Land (and air/space) mounts: ride while WADING, DISMOUNT
## at the waterline (swim_state.MOUNT_DISMOUNT_ON_SUBMERGE -- dismiss
## clears the book and restamps). Water mounts: swim, with the stamp
## payload the caller feeds to AnticheatService (set_aquatic_limits
## with speed, plus set_current_drift(OceanService.effective_current
## (pos, immune))). No mount: "none" (the naked-swimmer paths run
## unchanged).
func water_stamp_for(player_id: String, band: int) -> Dictionary:
	var mount = active_mount(player_id)
	if mount == null:
		return {"action": "none"}
	if band <= SwimStateScript.State.WADING:
		return {"action": "ride"}
	if not mount.is_swimmer():
		dismiss(player_id)
		return {"action": "dismount"}
	return {
		"action": "swim",
		"speed": float(mount.swim_speed),
		"grace": float(mount.squeeze_grace_m),
		"crush_bonus": float(mount.crush_depth_bonus_m),
		"immune": bool(mount.current_immune),
	}
