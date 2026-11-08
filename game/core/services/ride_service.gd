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
## path and its profile (a lunar-class profile: movement_leviathan)
## owns the gravity.
##
## Acquisition difficulty lives in the DATA (source, required_level,
## the drop's rarity); the service is the ledger, never the gate.
extends Node

const DictStore = preload("res://adapters/persistence/dict_store.gd")
const SwimStateScript = preload("res://core/frame/srv/swim_state.gd")
const MountDataScript = preload("res://core/schemas/mount_data.gd")
const GliderStateScript = preload("res://core/frame/srv/glider_state.gd")
const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind

## Fired on every summon/dismiss (R45): the runtime body (globe_player)
## listens for these to adopt/hand back the mount's movement laws.
## server-side summon/dismiss paths and the body both ride the same
## signal -- there is no second sync path to drift.
signal mount_summoned(player_id: String, mount_id: String)
signal mount_dismounted(player_id: String, mount_id: String)

const _KV: String = "ride_service/mounts/"
## The wardens' own sky. Granted automatically when a GM enters the
## world (GMs need to get around too); grantable by hand ONLY to GM
## riders -- the GM source door is fail-closed for everyone else.
const GM_MOUNT_ID: String = "mount_gm_skywarden"

var _owned: Dictionary = {}    # player_id -> {mount_id: true}
var _active: Dictionary = {}   # player_id -> mount_id (session truth)
var _chars: Dictionary = {}    # player_id -> CharacterData (session truth)


func _ready() -> void:
	if GameManager != null and not GameManager.player_entered_world.is_connected(_on_player_entered_world):
		GameManager.player_entered_world.connect(_on_player_entered_world)


func _on_player_entered_world(player_id: String, character_data) -> void:
	if character_data != null:
		_chars[player_id] = character_data
	if character_data is CharacterData and character_data.is_gm() \
			and grant_mount(player_id, GM_MOUNT_ID):
		GameLog.info("RideService: the Skywarden answers a warden (" + player_id + ")")


## The rider's character truth this session (null when unknown -- the
## probe/service-caller case).
func _rider_character(player_id: String):
	return _chars.get(player_id, null)


func _rider_is_gm(player_id: String) -> bool:
	var cd = _rider_character(player_id)
	return cd != null and cd is CharacterData and cd.is_gm()


## -1 when the rider is unknown to this session: the level gate stays
## open for service-level callers (probes, admin paths, agents) and
## closes for every real rider fed in by player_entered_world.
func _rider_level(player_id: String) -> int:
	var cd = _rider_character(player_id)
	if cd == null or not (cd is CharacterData):
		return -1
	return int(cd.level)


## The rider's species law, resolved through the faction registry's
## .tres truth (DataService.get_faction -- the same Faction resources
## the faction system loads; FactionManager's book rehydrates from
## persistence and fills on world load, so the data registry is the
## one truth available in every mode). Empty mount faction = anyone
## may ride; an unknown faction id, an empty species, or an unknown
## rider = fail-closed (an unknown law must never wave a rider
## through).
func _rider_faction_ok(player_id: String, mount) -> bool:
	var wanted := str(mount.faction_id)
	if wanted.is_empty():
		return true
	var cd = _rider_character(player_id)
	if cd == null or not (cd is CharacterData):
		return false
	var species := str(cd.species_id)
	if species.is_empty() or DataService == null:
		return false
	var f = DataService.get_faction(wanted)
	if f == null:
		return false
	return str(f.species_id) == species


## The rider's voice: two mount toasts through the typed pipeline
## (summoned / back to the whistle). Safe in --script mode: the
## dispatcher self-heals when the HUD is absent.
func _notify_mount(kind: int, player_id: String, mount_name: String, message: String) -> void:
	if NotificationService == null or mount_name.is_empty():
		return
	NotificationService.notify(kind, message, "RideService",
		"ride:%s:%s" % [player_id, mount_name], {}, player_id)


## -- Ownership ---------------------------------------------------------

func _owned_key(player_id: String) -> String:
	return _KV + player_id


func _load_owned(player_id: String) -> void:
	if _owned.has(player_id):
		return
	# R48: the ownership ledger rides the RELOAD-DURABLE store -- a
	# fresh guest who re-enters after a browser reload must still own
	# what they bought. "default" was memory-only: the wasm heap died
	# on F5 and the pacer vanished.
	var store := DictStore.new("durable_mounts")
	var row = store.get_kv(_owned_key(player_id), null)
	var book: Dictionary = {}
	if row is Dictionary:
		for mount_id in row.keys():
			book[str(mount_id)] = true
	_owned[player_id] = book


func _persist_owned(player_id: String) -> void:
	var store := DictStore.new("durable_mounts")
	var book: Dictionary = _owned.get(player_id, {})
	if book.is_empty():
		store.erase(_owned_key(player_id))
	else:
		store.set_kv(_owned_key(player_id), book.duplicate())


func owns_mount(player_id: String, mount_id: String) -> bool:
	_load_owned(player_id)
	return _owned[player_id].has(mount_id)


## Grant a mount into the rider's book. Refuses unknown mounts (data
## is the id truth), duplicates (soulbound is the default posture), and
## GM-source mounts for non-GM riders (fail-closed: an unknown rider is
## not a warden). Quests, drops, vendors, and events all call THIS --
## one ledger.
func grant_mount(player_id: String, mount_id: String) -> bool:
	var mount = DataService.get_mount(mount_id) if DataService != null else null
	if mount == null:
		GameLog.warn("RideService: grant refused, unknown mount: " + mount_id)
		return false
	if int(mount.source) == MountDataScript.MountSource.GM and not _rider_is_gm(player_id):
		GameLog.warn("RideService: grant refused, GM mount for a non-warden: " + mount_id)
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
## the same path). The mount's required_level is the law for every
## rider the service knows (world-entry truth); unknown riders stay
## service-level callers. Returns false for unowned/unknown mounts and
## level-gated riders.
func summon(player_id: String, mount_id: String) -> bool:
	if not owns_mount(player_id, mount_id):
		GameLog.warn("RideService: summon refused, not owned: " + mount_id)
		return false
	var mount = DataService.get_mount(mount_id)
	if mount == null:
		return false
	var rider_level := _rider_level(player_id)
	if rider_level >= 0 and rider_level < int(mount.required_level):
		GameLog.warn("RideService: summon refused, level %d < %d for %s" % [rider_level, int(mount.required_level), mount_id])
		return false
	if not _rider_faction_ok(player_id, mount):
		GameLog.warn("RideService: summon refused, faction gate for %s on %s" % [mount_id, player_id])
		return false
	_active[player_id] = mount_id
	mount_summoned.emit(player_id, mount_id)
	var profile = DataService.get_mount_movement_profile(mount)
	if AntiCheatService:
		if profile != null:
			AntiCheatService.set_profile_limits(player_id, str(profile.id))
		else:
			AntiCheatService.set_profile_limits(player_id, "movement_standard")
	_notify_mount(NotifKind.MOUNT_SUMMONED, player_id, str(mount.display_name),
		"You summon the %s" % str(mount.display_name))
	GameLog.info("RideService: mount summoned: %s (%s)" % [mount_id, player_id])
	return true


## -- The vendor door (grant wiring) -------------------------------------

## The purchasable-mount catalog, built from DATA truth: every mount
## with a vendor price -- the gold purse (currency gold or empty) or a
## non-gold wallet whose CurrencyData carries a vendor kind (FAVOR,
## TOKEN, EVENT; BLACK_MARKET scrip is not a shop good). Fields mirror
## VendorService's catalog shape ({id, display_name, price, currency,
## level, kind}). No numbers are invented here -- the .tres is the
## price tag.
func get_shop_catalog() -> Array:
	var out: Array = []
	if DataService == null:
		return out
	for id in DataService.get_all_mounts():
		var m = DataService.get_mount(str(id))
		if m == null:
			continue
		var cur := str(m.currency_id)
		var cost := int(m.cost)
		if cost <= 0:
			continue
		if cur != "" and cur != "currency_gold" \
				and not _vendor_currency(cur):
			continue
		out.append({
			"id": str(m.id),
			"display_name": str(m.display_name),
			"price": cost,
			"currency": cur,
			"level": int(m.required_level),
			"kind": int(m.kind),
		})
	return out


## True when a non-gold currency id is a vendor wallet: the catalog
## must know it (no invented ids) and its kind must be a shop good
## (FAVOR/TOKEN/EVENT; BLACK_MARKET scrip is spent in darker places).
func _vendor_currency(currency_id: String) -> bool:
	var cd = DataService.get_currency(currency_id) if DataService != null else null
	if cd == null:
		return false
	return int(cd.kind) == CurrencyData.CurrencyKind.FAVOR \
		or int(cd.kind) == CurrencyData.CurrencyKind.TOKEN \
		or int(cd.kind) == CurrencyData.CurrencyKind.EVENT


## The purchase door for mounts. One gate chain, each leg loud:
## known mount -> priced (gold or a vendor-kind currency) ->
## not already owned (the ledger refuses duplicates) -> level law
## (world-entry truth when known) -> faction law (species truth when
## known; unknown riders pass service-level, the level gate's own
## idiom) -> purse law (gold or the favor ledger; a ledger refusal
## ROLLS BACK nothing -- the purse is checked before it is touched)
## -> grant through the ONE ledger. Returns the VendorService
## {success, message} shape plus "mount_id"; announces acquisition
## through the typed pipeline (MOUNT_ACQUIRED -- the grantor announces
## acquisition, per sec 7).
func purchase_mount(player_id: String, mount_id: String) -> Dictionary:
	var mount = DataService.get_mount(mount_id) if DataService != null else null
	if mount == null:
		GameLog.warn("RideService: purchase refused, unknown mount: " + mount_id)
		return {"success": false, "message": "Unknown mount"}
	var cur := str(mount.currency_id)
	var cost := int(mount.cost)
	var favor := cur != "" and cur != "currency_gold" and _vendor_currency(cur)
	if cost <= 0 or (cur != "" and cur != "currency_gold" and not favor):
		return {"success": false, "message": "Not for sale"}
	if owns_mount(player_id, mount_id):
		return {"success": false, "message": "You already ride this one"}
	var rider_level := _rider_level(player_id)
	if rider_level >= 0 and rider_level < int(mount.required_level):
		GameLog.warn("RideService: purchase refused, level %d < %d for %s" % [rider_level, int(mount.required_level), mount_id])
		return {"success": false, "message": "Requires level %d" % int(mount.required_level)}
	if not _rider_faction_ok(player_id, mount):
		GameLog.warn("RideService: purchase refused, faction gate for %s on %s" % [mount_id, player_id])
		return {"success": false, "message": "Your people cannot ride this one"}
	var inv = InventoryService.get_inventory(player_id) if InventoryService != null else null
	if inv == null:
		return {"success": false, "message": "No purse to pay with"}
	if favor:
		if inv.get_currency_amount(cur) < cost:
			return {"success": false, "message": "Not enough %s (need %d, have %d)" % [str(mount.currency_id), cost, inv.get_currency_amount(cur)]}
		if not inv.remove_currency(cur, cost):
			return {"success": false, "message": "Not enough %s" % str(mount.currency_id)}
	else:
		if inv.get_gold() < cost:
			return {"success": false, "message": "Not enough gold (need %d, have %d)" % [cost, inv.get_gold()]}
		if not inv.remove_gold(cost):
			return {"success": false, "message": "Not enough gold"}
	if not grant_mount(player_id, mount_id):
		if favor:
			inv.add_currency(cur, cost)  # the ledger is the law; refund what the chain refused
		else:
			inv.add_gold(cost)
		GameLog.warn("RideService: purchase rolled back after ledger refusal: " + mount_id)
		return {"success": false, "message": "Purchase failed"}
	# The stable audit (R47): the purchase/summon/dismiss trio through
	# ONE channel -- the web journey probe's game-side oracles ride
	# these marks the way the menu journey rides the a11y stream.
	GameLog.info("RideService: mount purchased: %s (%s)" % [mount_id, player_id])
	_notify_mount(NotifKind.MOUNT_ACQUIRED, player_id, str(mount.display_name),
		"You have acquired the %s" % str(mount.display_name))
	return {"success": true, "message": "Purchased %s" % str(mount.display_name), "mount_id": mount_id}


## Dismount: clear the session book and hand the body back humanoid
## limits (the safe default -- the rider's own profile re-stamps on
## their next spawn stamp). The mount returns to its
## whistle -- the waterline and the cliff both end here.
func dismiss(player_id: String) -> bool:
	if not _active.has(player_id):
		return false
	var mount_name := active_mount_name(player_id)
	var mount_id := active_mount_id(player_id)
	_active.erase(player_id)
	mount_dismounted.emit(player_id, mount_id)
	if AntiCheatService:
		AntiCheatService.set_profile_limits(player_id, "movement_standard")
	_notify_mount(NotifKind.MOUNT_DISMISSED, player_id, mount_name,
		"The %s returns to its whistle" % mount_name)
	GameLog.info("RideService: mount dismissed: %s (%s)" % [mount_id, player_id])
	return true


## The display name of the mount being ridden ("" when unmounted).
func active_mount_name(player_id: String) -> String:
	var mount = active_mount(player_id)
	return "" if mount == null else str(mount.display_name)


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


## The cliff law, service-executed (glider_state.MOUNT_DISMOUNT_ON_FALL,
## decided in S12, wired here): a mounted rider who falls past the
## glider deploy gate BAILS -- the mount returns to its whistle (book
## cleared, humanoid limits restamped) and the rider keeps the fall,
## glider usable from there. A bond that dies at the bottom of a ravine
## is a broken promise: the mount never falls. Only GROUND mounts bail
## (bails_on_fall) -- sky mounts fly, swimmers swim, space is space.
## Callers feed this per tick while airborne, exactly like
## water_stamp_for while wet.
func fall_stamp_for(player_id: String, falling: bool, altitude: float) -> Dictionary:
	var mount = active_mount(player_id)
	if mount == null:
		return {"action": "none"}
	if falling and altitude >= GliderStateScript.DEPLOY_HEIGHT_METERS \
			and mount.bails_on_fall():
		dismiss(player_id)
		return {"action": "bail"}
	return {"action": "ride"}
