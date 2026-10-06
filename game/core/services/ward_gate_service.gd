## WardGateService - the hard gate (labs/prd-ward-gate.md).
##
## One registry for the admin keys ("max GMs, skywardens, or other
## admin things") and one place for the breach embargo. Defense in
## depth: a gate opens only when EVERY key signal matches -- the role
## truth (server-side character class, resolved from the warden's own
## session book, never a client claim), the token mounts (the
## RideService ownership ledger -- fail-closed to grant, so its
## presence is an independently-verified signal), and the token items
## (defensive lookup, fail-closed until InventoryService grows one).
## The absence of any signal is enough to keep the gate closed, and an
## unknown rider is always a closed gate.
##
## The same registry carries the BREACH EMBARGO: drop an item id into
## the gate (tres edit for standing bans, embargo_item for the
## temporary ones) and its drops stop everywhere -- the duped ore
## never materializes, and pending loot dies at the pickup gate. Lift
## by hand when the breach is handled.
##
## Script mode: autoloads resolved at runtime (DataService,
## RideService, NotificationService); the service is defensive about
## every one of them.
extends Node

const DictStore = preload("res://adapters/persistence/dict_store.gd")
const CharacterClass = preload("res://core/schemas/character_class.gd")
const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind

## The registry the runtime embargo defaults to when no gate id is given.
const DEFAULT_GATE_ID: String = "gate_warden_keys"
const EMBARGO_KV: String = "ward_gate/embargo/"

## The warden's own session book -- kept INDEPENDENT of RideService's
## (two books, same hook): if one is ever poisoned, the other still
## gates. That is what defense in depth means here.
var _chars: Dictionary = {}   # player_id -> CharacterData (session truth)


func _ready() -> void:
	if GameManager != null and not GameManager.player_entered_world.is_connected(_on_player_entered_world):
		GameManager.player_entered_world.connect(_on_player_entered_world)


func _on_player_entered_world(player_id: String, character_data) -> void:
	if character_data != null:
		_chars[player_id] = character_data


func _rider_character(player_id: String):
	return _chars.get(player_id, null)


## -- The hard gate -----------------------------------------------------

## Role truth from the warden's own book. The GM role (0) resolves
## through CharacterData.is_gm_class (the repo's one class-truth path);
## other roles resolve through DataService. Unknown rider = false.
func _has_role(player_id: String, needed_role: int) -> bool:
	var cd = _rider_character(player_id)
	if cd == null:
		return false
	if int(needed_role) == CharacterClass.Role.GM:
		return CharacterData.is_gm_class(str(cd.class_id))
	var cls = DataService.get_character_class(str(cd.class_id)) if DataService != null else null
	return cls != null and int(cls.role) == int(needed_role)


## The item leg: defensive try-known-methods over InventoryService
## (AGENTS.md defensive helper pattern). Nothing matches today, so the
## leg is fail-closed; when a lookup lands, the gate picks it up.
func _holds_item(player_id: String, item_id: String) -> bool:
	if InventoryService == null:
		return false
	for method_name in ["has_item", "count_item", "get_item_count"]:
		if InventoryService.has_method(method_name):
			var result = InventoryService.call(method_name, player_id, item_id)
			if result is bool:
				return bool(result)
			if result is int:
				return int(result) > 0
			if result is float:
				return float(result) > 0.0
	return false


## The gate verdict on an already-resolved gate. Public so the probe
## can exercise every leg without shipping test-only data.
func gate_open_for(player_id: String, gate) -> bool:
	if gate == null:
		return false
	if not _has_role(player_id, int(gate.key_role)):
		return false
	for mount_id in gate.key_mounts:
		if RideService == null or not RideService.owns_mount(player_id, str(mount_id)):
			return false
	for item_id in gate.key_items:
		if not _holds_item(player_id, str(item_id)):
			return false
	return true


## The hard gate: opens only when every key signal matches.
func can_open(player_id: String, gate_id: String) -> bool:
	var gate = DataService.get_gate(gate_id) if DataService != null else null
	if gate == null:
		GameLog.warn("WardGateService: gate not found: " + str(gate_id))
		return false
	return gate_open_for(player_id, gate)


## -- The breach embargo -------------------------------------------------

## The registry branch on its own (the shipped registry stays empty
## until a breach; the probe proves the branch with an in-memory gate).
func is_embargoed_for_gate(gate, item_id: String) -> bool:
	if gate == null:
		return false
	return Array(gate.embargoed_items).has(str(item_id))


## The runtime ledger row for this item, or null (expired rows erase
## themselves on read -- "temporarily" is a real contract).
func _ledger_embargo(item_id: String):
	var store := DictStore.new()
	var row = store.get_kv(EMBARGO_KV + str(item_id), null)
	if row is Dictionary:
		var expires_at := float(row.get("expires_at", 0.0))
		if expires_at > 0.0 and float(Time.get_unix_time_from_system()) >= expires_at:
			store.erase(EMBARGO_KV + str(item_id))
			return null
		return row
	return null


## True when the item may not enter the world: listed in any loaded
## gate's standing embargo, or held in the runtime ledger.
func is_embargoed(item_id: String) -> bool:
	if DataService != null:
		for gate in DataService.get_all_gates().values():
			if is_embargoed_for_gate(gate, item_id):
				return true
	return _ledger_embargo(item_id) != null


## The drop seam: LootService asks before an item materializes.
func allow_drop(item_id: String) -> bool:
	return not is_embargoed(item_id)


## Drop an item id into the gate: its drops stop everywhere, now.
## duration_s <= 0.0 = until lifted by hand. Admin-only by caller
## contract (this is breach response, not gameplay).
func embargo_item(item_id: String, reason: String, by: String, duration_s: float = 0.0) -> bool:
	var id := str(item_id).strip_edges()
	if id.is_empty():
		return false
	var store := DictStore.new()
	var expires_at := 0.0
	if duration_s > 0.0:
		expires_at = float(Time.get_unix_time_from_system()) + duration_s
	store.set_kv(EMBARGO_KV + id, {
		"item_id": id,
		"reason": str(reason),
		"by": str(by),
		"placed_at": float(Time.get_unix_time_from_system()),
		"expires_at": expires_at,
	})
	GameLog.warn("WardGateService: EMBARGO %s (%s) by %s" % [id, str(reason), str(by)])
	if NotificationService != null:
		NotificationService.notify(NotifKind.ADMIN_ALERT,
			"Ward gate: %s embargoed (%s)" % [id, str(reason)],
			"WardGateService", "embargo:%s" % id,
			{"item_id": id, "reason": str(reason), "by": str(by)}, "")
	return true


## Lift a temporary embargo (breach handled). False when none existed.
func lift_embargo(item_id: String, by: String) -> bool:
	var store := DictStore.new()
	var key := EMBARGO_KV + str(item_id)
	if store.get_kv(key, null) == null:
		return false
	store.erase(key)
	GameLog.info("WardGateService: embargo lifted on %s by %s" % [str(item_id), str(by)])
	return true


## The live embargo list (registry + ledger) for admin views.
func embargoed_items() -> Array:
	var items: Array = []
	if DataService != null:
		for gate in DataService.get_all_gates().values():
			for item_id in gate.embargoed_items:
				if not items.has(str(item_id)):
					items.append(str(item_id))
	var store := DictStore.new()
	for key in store.all_keys():
		if not str(key).begins_with(EMBARGO_KV):
			continue
		var row = store.get_kv(str(key), null)
		if row is Dictionary:
			var item_id := str(row.get("item_id", ""))
			if not item_id.is_empty() and not items.has(item_id):
				items.append(item_id)
	return items
