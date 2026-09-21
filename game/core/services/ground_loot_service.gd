## GroundLootService - World-space loot drops with pickup flow.
##
## The single source of truth for items lying on the ground. Every loot
## source funnels through create_drop():
##   - Enemy deaths (Enemy._on_died rolls its LootTable)
##   - Player deaths in PvP zones / duels (DeathFeatures drop rules)
##   - Chests/containers (create_container_drop)
##   - Quest/item rewards (create_reward_drop)
##
## Pickup: an interact action (E / F / gamepad A / the InteractLayer)
## finds the nearest drop in pickup range and moves the Items into the
## player's InventoryComponent (registered with InventoryService).
##
## Preload-only static-ish singleton pattern: registered as an autoload
## AFTER InventoryService/LootService (its _ready only touches EventHub).
extends Node

const Item = preload("res://core/schemas/item.gd")
const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind

signal drop_spawned(drop_id: String, drop: Dictionary)
signal drop_picked_up(drop_id: String, player, items: Array)
signal drop_despawned(drop_id: String, reason: String)

## How long a ground drop persists before despawning (seconds).
const DEFAULT_DESPAWN_SECONDS: float = 120.0
## Physical pickup range from the player.
const PICKUP_RADIUS: float = 2.5
## How far from a player's death spot their dropped items scatter.
const DROP_SCATTER_RADIUS: float = 1.5

## drop_id -> drop Dictionary (see create_drop for shape)
var _drops: Dictionary = {}
var _next_id: int = 1

## Autoload-safe logging: bare GameLog references abort at compile time
## in --script test mode (autoloads are not pre-loaded there).
func _log(level: String, msg: String) -> void:
	var gl := get_node_or_null("/root/GameLog")
	if gl != null and gl.has_method(level):
		gl.call(level, msg)

## Autoload-safe hub emit (same reason as _log): a bare EventHub
## identifier is a parse-time edge, which aborts --script-mode compiles
## of this file and every test that preloads it.
func _hub_emit(signal_name: String, args: Array) -> void:
	var hub := get_node_or_null("/root/EventHub")
	if hub != null and hub.has_signal(signal_name):
		hub.callv("emit_signal", [signal_name] + args)

## Autoload-safe player toast (NotificationService has the same parse-time
## edge as EventHub in --script test mode).
func _notify_player(entity_id: String, kind: int, message: String,
		source: String, dedupe_key: String, data: Dictionary) -> void:
	var ns := get_node_or_null("/root/NotificationService")
	if ns == null or not ns.has_method("notify"):
		return
	ns.notify(kind, message, source, dedupe_key, data, entity_id)

func _ready() -> void:
	# Persistence: drops are session-transient world state. Rehydrating
	# them across a server restart would need snapshot_store; for now
	# they live and die with the process (same tier as enemy AI memory).
	_log("info", "GroundLootService: ready")

## Create a ground drop at a world position.
## items: Array of either Item instances or {item_id, quantity} dicts
## (dicts are resolved through DataService.get_item; unresolvable ids
## are skipped so a bad .tres cannot kill a death drop).
## position: Vector3 world position. options (all optional):
##   despawn_seconds: float  lifetime override (0 = never despawn)
##   owner_id: String        restrict pickup to one player until expiry
##                            fraction owner_lock_fraction (PvP drops)
##   source: String          "enemy"|"pvp_drop"|"duel_drop"|"chest"|"reward"
##   currency: Dictionary    coin id -> amount, carried through pickup
## Returns the drop id ("" when nothing usable was given).
func create_drop(position: Vector3, items: Array, options: Dictionary = {}) -> String:
	var resolved_items: Array = _resolve_items(items)
	if resolved_items.is_empty() and options.get("currency", {}).is_empty():
		return ""

	var drop_id := "drop_%d_%d" % [Time.get_unix_time_from_system(), _next_id]
	_next_id += 1

	var drop := {
		"id": drop_id,
		"position": position,
		"items": resolved_items,
		"currency": options.get("currency", {}),
		"source": str(options.get("source", "enemy")),
		"owner_id": str(options.get("owner_id", "")),
		"owner_lock_fraction": float(options.get("owner_lock_fraction", 0.0)),
		"spawned_at": Time.get_unix_time_from_system(),
		"despawn_at": _despawn_at(options),
		"node": null,  # visual node, set by the owning scene if it wants one
	}

	_drops[drop_id] = drop
	_hub_emit("ground_loot_spawned", [drop_id, position, resolved_items])
	drop_spawned.emit(drop_id, drop)
	_attach_visual(drop_id, drop)
	_log("info", "GroundLootService: %s drop '%s' (%d items) at %s" % [
		drop["source"], drop_id, resolved_items.size(), position])
	return drop_id


## Attach the floating 3D drop visual when a live 3D scene is running.
## Skipped in headless/script tests (no current scene to parent to).
func _attach_visual(drop_id: String, drop: Dictionary) -> void:
	var ml := Engine.get_main_loop()
	if ml == null or not (ml is SceneTree):
		return
	var tree := ml as SceneTree
	var scene := tree.current_scene
	if scene == null or not scene.is_inside_tree():
		return
	var visual_script := load("res://ui/components/loot_drop_visual.gd")
	if visual_script == null:
		return
	var visual: Node3D = visual_script.new()
	visual.name = "LootDrop_%s" % drop_id
	var pos: Vector3 = drop["position"]
	visual.position = Vector3(pos.x, pos.y + 0.05, pos.z)
	scene.add_child(visual)
	if visual.has_method("setup"):
		visual.setup(drop)
	drop["node"] = visual

## Convenience: chest/container style drop (fixed contents).
func create_container_drop(container_id: String, position: Vector3, items: Array,
		currency: Dictionary = {}) -> String:
	return create_drop(position, items, {
		"source": "chest",
		"currency": currency,
		"despawn_seconds": DEFAULT_DESPAWN_SECONDS * 3.0,  # chests linger
		"owner_id": container_id,  # informational; chests are public
	})

## Convenience: quest/achievement reward bundles. These never despawn
## until picked up and are always owner-locked.
func create_reward_drop(player_id: String, position: Vector3, items: Array) -> String:
	return create_drop(position, items, {
		"source": "reward",
		"owner_id": player_id,
		"owner_lock_fraction": 1.0,  # only the owner, forever
		"despawn_seconds": 0.0,
	})

## Resolve the items array into real Item instances.
func _resolve_items(items: Array) -> Array:
	var resolved: Array = []
	for entry in items:
		if entry is Item:
			resolved.append(entry)
		elif entry is Dictionary and not entry.is_empty():
			var item_id := str(entry.get("item_id", ""))
			var quantity := int(entry.get("quantity", 1))
			if item_id == "" or quantity <= 0:
				continue
			var item: Item = null
			# Runtime lookup: a bare DataService identifier aborts
			# --script-mode compiles (parse-time autoload edge).
			var ds := get_node_or_null("/root/DataService")
			if ds != null and ds.has_method("get_item"):
				item = ds.get_item(item_id)
			if item == null:
				_log("warn", "GroundLootService: unknown item id '%s', skipped" % item_id)
				continue
			# Give each drop its own instance so stacking/binding on one
			# player's pickup does not mutate a shared template resource.
			var inst: Item = item.duplicate(true)
			inst.current_stack = quantity
			resolved.append(inst)
	return resolved

func _despawn_at(options: Dictionary) -> float:
	var seconds := float(options.get("despawn_seconds", DEFAULT_DESPAWN_SECONDS))
	if seconds <= 0.0:
		return -1.0  # never
	return Time.get_unix_time_from_system() + seconds

## Nearest pickupable drop for a player, or null.
func find_nearest_pickup(player) -> Dictionary:
	var best: Dictionary = {}
	var best_dist := PICKUP_RADIUS
	for drop_id in _drops:
		var drop: Dictionary = _drops[drop_id]
		if not _can_pick_up(player, drop):
			continue
		var pos: Vector3 = drop["position"]
		var dist: float = player.global_position.distance_to(pos)
		if dist < best_dist:
			best_dist = dist
			best = drop
	return best

## Ownership/eligibility gate.
func _can_pick_up(player, drop: Dictionary) -> bool:
	var owner_id := str(drop.get("owner_id", ""))
	if owner_id == "":
		return true
	# Rewards: owner only, no expiry.
	if float(drop.get("owner_lock_fraction", 0.0)) >= 1.0:
		return _player_id_of(player) == owner_id
	# PvP drops: owner has first claim until a fraction of the lifetime
	# has passed; after that it is public (classic loot-window rule).
	var age := float(Time.get_unix_time_from_system() - int(drop.get("spawned_at", 0)))
	var lifetime := float(drop.get("despawn_at", 0)) - float(drop.get("spawned_at", 0))
	if lifetime <= 0.0:
		lifetime = DEFAULT_DESPAWN_SECONDS
	var lock_window := lifetime * float(drop.get("owner_lock_fraction", 0.0))
	if age < lock_window:
		return _player_id_of(player) == owner_id
	return true

func _player_id_of(player) -> String:
	if player == null:
		return ""
	if "entity_id" in player and str(player.entity_id) != "":
		return str(player.entity_id)
	if "player_id" in player:
		return str(player.player_id)
	return ""

## Attempt pickup of the nearest (or a specific) drop. Returns the
## items that actually landed in the inventory (empty on failure).
func try_pickup(player, drop_id: String = "") -> Array:
	if player == null or not is_instance_valid(player):
		return []

	var drop: Dictionary = {}
	if drop_id != "":
		drop = _drops.get(drop_id, {})
	else:
		drop = find_nearest_pickup(player)
	if drop.is_empty():
		return []

	var player_id := _player_id_of(player)
	if player_id == "":
		_log("warn", "GroundLootService: pickup blocked, no player id")
		return []

	# Range check (specific-id pickup still requires being in range).
	if not "global_position" in player:
		return []
	var pos: Vector3 = drop["position"]
	if player.global_position.distance_to(pos) > PICKUP_RADIUS:
		return []

	if not _can_pick_up(player, drop):
		# Toast: item belongs to someone else's loot window.
		_notify_player(player_id, NotifKind.ITEM_TRANSFERRED,
			"This loot belongs to someone else for now.",
			"GroundLootService",
			"loot_lock:%s:%s" % [player_id, str(drop["id"])],
			{"drop_id": str(drop["id"])})
		return []

	# Delegation gate (LootRulesService): party rules, smart class
	# routing, guild locks, karma gates. "" = candidate may loot;
	# otherwise the drop is reserved for another player. Lazy /root
	# resolution: LootRulesService is registered after this service, and
	# a bare forward identifier would poison script-mode compilation.
	var loot_rules = get_node_or_null(NodePath("/root/LootRulesService"))
	if loot_rules != null and loot_rules.has_method("resolve_delegation"):
		var reserved_for := str(loot_rules.resolve_delegation(drop, player_id))
		if reserved_for != "" and reserved_for != "?":
				var why := ""
				if loot_rules.has_method("describe_reservation"):
					why = str(loot_rules.describe_reservation(drop))
				_notify_player(player_id, NotifKind.ITEM_TRANSFERRED,
					"This loot is not yours%s." % (" %s" % why if why != "" else ""),
					"GroundLootService",
					"delegated:%s:%s" % [player_id, str(drop["id"])],
					{"drop_id": str(drop["id"])})
				return []

	# Route items through InventoryService so persistence, the
	# InventoryComponent signal chain, and full-bag handling all fire.
	# Runtime lookup (parse-time autoload edge in --script mode).
	var inventory: Node = null
	var inv_svc := get_node_or_null("/root/InventoryService")
	if inv_svc != null and inv_svc.has_method("get_inventory"):
		inventory = inv_svc.get_inventory(player_id)
	if inventory == null:
		_log("warn", "GroundLootService: no inventory for %s" % player_id)
		return []

	var picked: Array = []
	var failed: Array = []
	for item in drop["items"]:
		if inventory.has_method("add_item") and inventory.add_item(item):
			picked.append(item)
		else:
			failed.append(item)

	# Currency lands via the duck-typed add_gold path (PlayerController
	# mirrors PlayerManager.add_gold).
	var currency: Dictionary = drop.get("currency", {})
	if not currency.is_empty() and "add_gold" in player and player.has_method("add_gold"):
		var total: int = 0
		for coin_id in currency:
			total += int(currency[coin_id])
		if total > 0:
			player.add_gold(total)

	if picked.is_empty():
		if not failed.is_empty():
			_notify_player(player_id, NotifKind.ITEM_FULL,
				"Your bags are full.",
				"GroundLootService",
				"bags_full:%s" % player_id,
				{})
		return []

	# Partial pickup keeps the remainder on the ground.
	var final_drop_id := str(drop["id"])
	if not failed.is_empty():
		drop["items"] = failed
	else:
		_remove_drop(final_drop_id, "picked_up")

	_hub_emit("ground_loot_picked_up", [player, final_drop_id, picked])
	drop_picked_up.emit(final_drop_id, player, picked)
	_log("info", "GroundLootService: %s picked up %d item(s) from %s" % [
		player_id, picked.size(), str(drop.get("source", "drop"))])
	return picked

func _remove_drop(drop_id: String, reason: String) -> void:
	var drop: Dictionary = _drops.get(drop_id, {})
	if drop.is_empty():
		return
	var node = drop.get("node", null)
	if node != null and is_instance_valid(node):
		node.queue_free()
	_drops.erase(drop_id)
	_hub_emit("ground_loot_despawned", [drop_id, reason])
	drop_despawned.emit(drop_id, reason)

## Expire old drops.
func _process(_delta: float) -> void:
	var now := Time.get_unix_time_from_system()
	var expired: Array = []
	for drop_id in _drops:
		var despawn_at: float = float(_drops[drop_id].get("despawn_at", -1.0))
		if despawn_at > 0.0 and now > despawn_at:
			expired.append(drop_id)
	for drop_id in expired:
		_remove_drop(drop_id, "expired")

func get_drop_count() -> int:
	return _drops.size()

func get_drop(drop_id: String) -> Dictionary:
	return _drops.get(drop_id, {})

## Debug/admin helper.
func clear_all() -> void:
	var ids := _drops.keys()
	for id in ids:
		_remove_drop(str(id), "cleared")
