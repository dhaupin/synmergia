## LootService - Loot distribution and management
## Handles loot rolling, party loot sharing, auto-loot, and loot rules
class_name LootService
extends Node

# Active loot rolls (loot_id -> loot data)
var _active_loot: Dictionary = {}

# Player loot assignments (entity_id -> [items])
var _player_loot: Dictionary = {}

# Loot timers
var _loot_timeout_seconds: float = 300.0  # 5 minutes to loot

# Need/Greed rolls (loot_id -> {player_id -> roll})
var _need_greed_rolls: Dictionary = {}

# Loot roll types
enum RollType {
        NEED,    # Will use the item
        GREED,   # Wants to sell/transmog
        PASS     # Doesn't want
}

signal loot_dropped(source_id: String, loot_id: String, items: Array, currency: Dictionary)
signal loot_rolled(loot_id: String, player_id: String, roll_type: RollType, roll_value: int)
signal loot_assigned(loot_id: String, player_id: String, items: Array)
signal loot_expired(loot_id: String)
signal loot_picked_up(player_id: String, items: Array)
signal loot_passed(loot_id: String, player_id: String)
signal loot_need_before_greed_started(loot_id: String, eligible_players: Array)
signal loot_distributed(loot_id: String, distributions: Dictionary)

func _ready() -> void:
        Logger.info("LootService: Ready")

## Create loot from enemy death
func create_loot(source_id: String, loot_table: LootTable, player_level: int = 1, context: Dictionary = {}) -> String:
        var loot_id := "loot_%s_%d" % [source_id, Time.get_ticks_msec()]
        
        var result := loot_table.roll_drop()
        
        var loot_data := {
                "id": loot_id,
                "source_id": source_id,
                "table_id": loot_table.id,
                "items": result["items"],
                "currency": result["currency"],
                "has_loot": result["got_any"],
                "auto_loot": loot_table.auto_loot,
                "need_before_greed": loot_table.need_before_greed,
                "created_at": Time.get_unix_time_from_system(),
                "expires_at": Time.get_unix_time_from_system() + _loot_timeout_seconds,
                "eligible_players": [],
                "assigned_to": ""
        }
        
        _active_loot[loot_id] = loot_data
        
        if result["got_any"]:
                loot_dropped.emit(source_id, loot_id, result["items"], result["currency"])
                Logger.info("LootService: Created loot %s with %d items" % [loot_id, result["items"].size()])
        
        return loot_id

## Create loot from container (chest, crate, etc.)
func create_container_loot(container_id: String, items: Array, currency: Dictionary = {}, 
                           auto_loot: bool = false) -> String:
        var loot_id := "loot_%s_%d" % [container_id, Time.get_ticks_msec()]
        
        var loot_data := {
                "id": loot_id,
                "source_id": container_id,
                "table_id": "",
                "items": items,
                "currency": currency,
                "has_loot": not items.is_empty() or not currency.is_empty(),
                "auto_loot": auto_loot,
                "need_before_greed": false,
                "created_at": Time.get_unix_time_from_system(),
                "expires_at": Time.get_unix_time_from_system() + _loot_timeout_seconds,
                "eligible_players": [],
                "assigned_to": ""
        }
        
        _active_loot[loot_id] = loot_data
        
        if loot_data["has_loot"]:
                loot_dropped.emit(container_id, loot_id, items, currency)
        
        return loot_id

## Set eligible players for loot (for parties)
func set_eligible_players(loot_id: String, player_ids: Array) -> void:
        var loot := _active_loot.get(loot_id)
        if loot:
                loot["eligible_players"] = player_ids
                Logger.debug("LootService: Set %d eligible players for loot %s" % [player_ids.size(), loot_id])

## Start Need/Greed rolling
func start_need_greed_roll(loot_id: String, initiator_id: String) -> bool:
        var loot := _active_loot.get(loot_id)
        if not loot or loot["assigned_to"] != "":
                return false
        
        if not loot["need_before_greed"]:
                # Auto-assign to initiator
                return assign_loot(loot_id, initiator_id)
        
        loot["eligible_players"] = [initiator_id]  # TODO: Get party members
        _need_greed_rolls[loot_id] = {}
        
        loot_need_before_greed_started.emit(loot_id, loot["eligible_players"])
        Logger.info("LootService: Started NBG for loot %s" % loot_id)
        
        return true

## Roll for loot (Need/Greed)
func roll_for_loot(loot_id: String, player_id: String, roll_type: RollType, roll_value: int) -> bool:
        if not _active_loot.has(loot_id):
                return false
        
        if not _need_greed_rolls.has(loot_id):
                return false
        
        var rolls: Dictionary = _need_greed_rolls[loot_id]
        if rolls.has(player_id):
                return false  # Already rolled
        
        rolls[player_id] = {"type": roll_type, "value": roll_value, "timestamp": Time.get_unix_time_from_system()}
        _need_greed_rolls[loot_id] = rolls
        
        loot_rolled.emit(loot_id, player_id, roll_type, roll_value)
        Logger.debug("LootService: Player %s rolled %s: %d" % [player_id, RollType.keys()[roll_type], roll_value])
        
        # Check if all eligible have rolled
        var loot: Dictionary = _active_loot[loot_id]
        if rolls.size() >= loot["eligible_players"].size():
                _resolve_need_greed(loot_id)
        
        return true

## Resolve Need/Greed
func _resolve_need_greed(loot_id: String) -> void:
        var loot := _active_loot.get(loot_id)
        if not loot:
                return
        
        var rolls: Dictionary = _need_greed_rolls[loot_id]
        
        var best_roller := ""
        var best_type := RollType.PASS
        var best_value := 0
        
        for player_id in rolls:
                var roll: Dictionary = rolls[player_id]
                if roll["type"] == RollType.NEED:
                        if best_type != RollType.NEED or roll["value"] > best_value:
                                best_roller = player_id
                                best_type = RollType.NEED
                                best_value = roll["value"]
                elif roll["type"] == RollType.GREED:
                        if best_type == RollType.PASS or roll["value"] > best_value:
                                best_roller = player_id
                                best_type = RollType.GREED
                                best_value = roll["value"]
        
        if best_roller != "":
                assign_loot(loot_id, best_roller)

## Assign loot to a player
func assign_loot(loot_id: String, player_id: String) -> bool:
        var loot := _active_loot.get(loot_id)
        if not loot or loot["assigned_to"] != "":
                return false
        
        loot["assigned_to"] = player_id
        
        var items := loot["items"]
        var currency := loot["currency"]
        
        # Store for player pickup
        if not _player_loot.has(player_id):
                _player_loot[player_id] = []
        
        _player_loot[player_id].append({
                "loot_id": loot_id,
                "items": items,
                "currency": currency,
                "auto_loot": loot["auto_loot"]
        })
        
        loot_assigned.emit(loot_id, player_id, items)
        Logger.info("LootService: Assigned loot %s to %s" % [loot_id, player_id])
        
        return true

## Pick up loot for a player
func pickup_loot(player_id: String, loot_id: String = "") -> Array:
        var items_received: Array = []
        
        if loot_id != "":
                # Pick up specific loot
                var found := false
                for i in range(_player_loot.get(player_id, []).size()):
                        var loot: Dictionary = _player_loot[player_id][i]
                        if loot["loot_id"] == loot_id:
                                items_received = loot["items"]
                                _player_loot[player_id].remove_at(i)
                                found = true
                                break
                if not found:
                        return []
        else:
                # Pick up all available loot
                for loot_data in _player_loot.get(player_id, []):
                        items_received.append_array(loot_data["items"])
                _player_loot[player_id] = []
        
        if not items_received.is_empty():
                loot_picked_up.emit(player_id, items_received)
                Logger.info("LootService: %s picked up %d items" % [player_id, items_received.size()])
        
        return items_received

## Pass on loot (for NBG)
func pass_loot(loot_id: String, player_id: String) -> bool:
        if not _active_loot.has(loot_id):
                return false
        
        if _need_greed_rolls.has(loot_id):
                var rolls: Dictionary = _need_greed_rolls[loot_id]
                if not rolls.has(player_id):
                        rolls[player_id] = {"type": RollType.PASS, "value": 0, "timestamp": Time.get_unix_time_from_system()}
                        loot_passed.emit(loot_id, player_id)
                        return true
        
        return false

## Get player's pending loot
func get_pending_loot(player_id: String) -> Array:
        return _player_loot.get(player_id, [])

## Get active loot at position
func get_loot_at_position(position: Vector3, radius: float = 5.0) -> Array:
        # This would be implemented with spatial queries
        # For now, return all active loot
        return _active_loot.values()

## Expire old loot
func expire_loot(loot_id: String) -> void:
        if _active_loot.has(loot_id):
                var loot := _active_loot[loot_id]
                
                # Clean up assignments
                for player_id in _player_loot:
                        var loot_list: Array = _player_loot[player_id]
                        for i in range(loot_list.size()):
                                if loot_list[i]["loot_id"] == loot_id:
                                        loot_list.remove_at(i)
        
                _active_loot.erase(loot_id)
                _need_greed_rolls.erase(loot_id)
                
                loot_expired.emit(loot_id)
                Logger.info("LootService: Loot %s expired" % loot_id)

## Check and expire old loot
func _process(delta: float) -> void:
        var now := Time.get_unix_time_from_system()
        var expired: Array = []
        
        for loot_id in _active_loot:
                var loot: Dictionary = _active_loot[loot_id]
                if now > loot["expires_at"]:
                        expired.append(loot_id)
        
        for loot_id in expired:
                expire_loot(loot_id)

## Distribute loot to party (share_loot)
func distribute_party_loot(party_id: String, loot_id: String, items: Array) -> Dictionary:
        var distributions: Dictionary = {}
        
        # TODO: Get party members from PartyService
        # For now, assign to first eligible or roll
        
        loot_distributed.emit(loot_id, distributions)
        return distributions

## Get loot info
func get_loot_info(loot_id: String) -> Dictionary:
        return _active_loot.get(loot_id, {})

## Check if player has pending loot
func has_pending_loot(player_id: String) -> bool:
        return not _player_loot.get(player_id, []).is_empty()

## Abandon loot (player walks away)
func abandon_loot(player_id: String, loot_id: String) -> bool:
        if _player_loot.has(player_id):
                var loot_list: Array = _player_loot[player_id]
                for i in range(loot_list.size()):
                        if loot_list[i]["loot_id"] == loot_id:
                                loot_list.remove_at(i)
                                Logger.info("LootService: %s abandoned loot %s" % [player_id, loot_id])
                                return true
        return false
