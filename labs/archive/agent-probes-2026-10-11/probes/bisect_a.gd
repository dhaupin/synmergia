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

func _ready() -> void:
	# Persistence: drops are session-transient world state. Rehydrating
	# them across a server restart would need snapshot_store; for now
	# they live and die with the process (same tier as enemy AI memory).
	GameLog.info("GroundLootService: ready")

## Create a ground drop at a world position.
## items: Array of either Item instances or {item_id, quantity} dicts
## (dicts are resolved through DataService.get_item; unresolvable ids
## are skipped so a bad .tres cannot kill a death drop).
