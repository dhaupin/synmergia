## Corpse - Lootable corpse entity
## Created when an entity dies, can be looted by other players
extends Node3D
class_name Corpse

## Runtime autoload lookup (script-mode-safe; the bare identifier
## fails compile when autoloads are absent -- test_islands).
func _glog() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("GameLog")) if tree and tree.root else null


signal corpse_looted(corpse: Corpse, looter: Entity)
signal corpse_despawned(corpse: Corpse, reason: String)

enum Visibility {
	EVERYONE,        # All players can see
	FACTION_ONLY,    # Same faction only
	GUILD_ONLY,      # Same guild only
	PARTY_ONLY,      # Same party only
	OWNER_ONLY,      # Only owner can see (private loot)
	ENEMIES_ONLY     # Only enemies can see (for enemy loot)
}

@export var corpse_id: String = ""
@export var owner_entity_id: String = ""
@export var loot_radius: float = 5.0

# Visibility settings
@export var visibility_mode: Visibility = Visibility.EVERYONE
@export var owner_faction_id: String = ""
@export var owner_guild_id: String = ""
@export var owner_party_id: String = ""

var _owner = null
var _killer = null
var _loot_items: Array[Dictionary] = []
var _is_looted: bool = false
var _decay_timer: float = 0.0
var _decay_duration: float = 600.0  # 10 minutes default
var _decay_started: bool = false

func _ready() -> void:
	add_to_group("corpses")

	# Set decay timer from config
	_decay_duration = GameConfig.Respawn.CORPSE_DESPAWN_TIME

	# Start decay timer
	_decay_timer = _decay_duration

func setup(owner, killer = null) -> void:
	_owner = owner
	_killer = killer
	owner_entity_id = owner.entity_id
	corpse_id = "corpse_%s_%d" % [owner.entity_id, Time.get_unix_time_from_system()]

	# Store faction/guild/party info for visibility
	owner_faction_id = owner.faction_id if "faction_id" in owner else ""
	owner_guild_id = owner.guild_id if "guild_id" in owner else ""
	owner_party_id = owner.party_id if "party_id" in owner else ""

	# Copy position
	if owner.has_method("get_global_position"):
		global_position = owner.get_global_position()

	# Roll for loot based on owner's drop table
	_roll_loot()

func _roll_loot() -> void:
	_loot_items = []

	# Loot-table rolls happen EXACTLY ONCE per kill, in
	# Enemy._on_died -> _roll_and_drop_loot() (the ground-drop path).
	# The corpse must not roll EnemyData.roll_loot() again -- that
	# double-dipped the table (2x table items per kill) and paid the
	# gold_min/gold_max range a second time on top of KillRewards.
	# The corpse's job is carry loot + karma coins only.
	if _owner and "karma" in _owner:
		var karma := _owner.get("karma") as int
		if karma > 0:
			var gold_drop := karma / 10  # 10% of karma as gold
			if gold_drop > 0:
				_loot_items.append({
					"item_id": "gold",
					"quantity": gold_drop,
					"display_name": "Gold Coins",
					"looted": false,
				})

	# Also include dropped equipment/items from the owner's inventory
	if _owner and "inventory_component" in _owner and _owner.inventory_component != null:
		var inventory = _owner.inventory_component
		if inventory and inventory.has_method("get_all_items"):
			_loot_items.append_array(inventory.get_all_items())

func _process(delta: float) -> void:
	if _is_looted:
		return

	# Decay timer
	_decay_timer -= delta
	if _decay_timer <= 0:
		_despawn("Timer expired")

	# Visual feedback for decay (optional: change color/fade)
	if _decay_timer < 60.0 and not _decay_started:
		_start_decay_visual()
		_decay_started = true

func _start_decay_visual() -> void:
	# Visual decay effect: start fading out the corpse
	# This would typically modify the mesh material's albedo alpha
	# For now, just log it - actual implementation would depend on visual system
	if _glog(): _glog().debug("Corpse %s: Starting decay visual (will fade out)" % corpse_id)

## Check if a player can SEE this corpse (visibility)
func can_see(observer) -> bool:
	# Duck-typed: observer may be an Entity, PlayerController, or test stub.
	# `.has()` is not a method on Objects (4.7.2) -- use the `in` operator.
	match visibility_mode:
		Visibility.EVERYONE:
			return true
		Visibility.FACTION_ONLY:
			return "faction_id" in observer and observer.faction_id == owner_faction_id
		Visibility.GUILD_ONLY:
			return "guild_id" in observer and observer.guild_id == owner_guild_id
		Visibility.PARTY_ONLY:
			return "party_id" in observer and observer.party_id == owner_party_id
		Visibility.OWNER_ONLY:
			return observer.entity_id == owner_entity_id
		Visibility.ENEMIES_ONLY:
			return not ("faction_id" in observer) or observer.faction_id != owner_faction_id
	return true

## Set visibility mode (can be changed based on zone rules)
func set_visibility_mode(mode: Visibility) -> void:
	visibility_mode = mode

## Check if a player can loot this corpse
func can_loot(looter: Entity) -> bool:
	if _is_looted:
		return false

	# Range check
	if looter.has_method("get_global_position"):
		var distance: float = global_position.distance_to(looter.get_global_position())
		if distance > loot_radius:
			return false

	return true

## Get loot items
func get_loot_items() -> Array[Dictionary]:
	return _loot_items.duplicate(true)  # Return a copy

## Loot an item from the corpse
func loot_item(looter: Entity, item_index: int) -> Dictionary:
	# Re-check corpse state
	if _is_looted:
		return {"success": false, "reason": "Corpse already fully looted"}

	if _decay_timer <= 0:
		return {"success": false, "reason": "Corpse has expired"}

	if not can_loot(looter):
		return {"success": false, "reason": "Too far from corpse"}

	if item_index < 0 or item_index >= _loot_items.size():
		return {"success": false, "reason": "Invalid item index"}

	var item: Dictionary = _loot_items[item_index]
	if item.get("looted", false):
		return {"success": false, "reason": "Already looted"}

	# Atomically mark as looted to prevent race conditions
	if item.get("looted", false):
		return {"success": false, "reason": "Already looted (race condition prevented)"}

	# Mark as looted
	item["looted"] = true

	# Give item to looter
	var result := {"success": true, "item": item}

	if looter.has_method("add_item"):
		looter.add_item(item.duplicate())

	corpse_looted.emit(self, looter)

	# Check if all items are looted
	if _all_items_looted():
		_despawn("All items looted")

	return result

## Loot all items at once
func loot_all(looter: Entity) -> Array[Dictionary]:
	var results: Array[Dictionary] = []

	for i in range(_loot_items.size()):
		if not _loot_items[i].get("looted", false):
			var result := loot_item(looter, i)
			if result.get("success", false):
				results.append(result)

	return results

## Check if all items are looted
func _all_items_looted() -> bool:
	for item in _loot_items:
		if not item.get("looted", false):
			return false
	return true

## Despawn the corpse
func _despawn(reason: String) -> void:
	corpse_despawned.emit(self, reason)
	queue_free()

## Get remaining time before despawn
func get_remaining_time() -> float:
	return max(0, _decay_timer)

## Get owner info
func get_owner_info() -> Dictionary:
	return {
		"owner_id": owner_entity_id,
		"owner_name": _owner.display_name if _owner else "Unknown",
		"killer_id": _killer.entity_id if _killer else "",
		"killer_name": _killer.display_name if _killer else "Unknown",
		"position": {
			"x": global_position.x,
			"y": global_position.y,
			"z": global_position.z
		}
	}
