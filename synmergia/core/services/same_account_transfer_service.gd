## SameAccountTransferService - Quick transfers between own characters
## Handles fast item/gold transfers without trade window
class_name SameAccountTransferService
extends Node

# Singleton
static var instance: SameAccountTransferService

# Service references
var _account_service: AccountService
var _inventory_service: InventoryService

# Transfer tracking per account
# account_id -> { last_transfer_time, gold_today, items_today, last_reset }
var _transfer_stats: Dictionary = {}

signal transfer_requested(from_char: String, to_char: String)
signal transfer_completed(from_char: String, to_char: String, gold: int, items: Array)
signal transfer_cancelled(from_char: String, to_char: String, reason: String)
signal transfer_limit_reached(account_id: String, limit_type: String)
signal cooldown_active(account_id: String, seconds_remaining: int)

func _ready() -> void:
        instance = self
        _account_service = AccountService.instance
        _inventory_service = InventoryService.instance
        
        # Reset stats periodically (once per day check)
        _check_daily_reset()
        Logger.info("SameAccountTransferService: Ready")

## Check and reset daily limits
func _check_daily_reset() -> void:
        var now := Time.get_unix_time_from_system()
        for account_id in _transfer_stats.keys():
                var stats: Dictionary = _transfer_stats[account_id]
                var last_reset: float = stats.get("last_reset", 0.0)
                # Reset if more than 24 hours since last reset
                if now - last_reset > 86400:  # 24 hours in seconds
                        stats["gold_today"] = 0
                        stats["items_today"] = 0
                        stats["last_reset"] = now

## Get transfer stats for account
func _get_stats(account_id: String) -> Dictionary:
        if not _transfer_stats.has(account_id):
                _transfer_stats[account_id] = {
                        "last_transfer_time": 0.0,
                        "gold_today": 0,
                        "items_today": 0,
                        "last_reset": Time.get_unix_time_from_system()
                }
        return _transfer_stats[account_id]

## Check if same-account transfer is allowed
func can_transfer(from_char_id: String, to_char_id: String) -> Dictionary:
        var result := {"allowed": true, "reason": ""}
        
        if not _account_service:
                result["allowed"] = false
                result["reason"] = "Account service not available"
                return result
        
        if not _inventory_service:
                result["allowed"] = False
                result["reason"] = "Inventory service not available"
                return result
        

		return result
		result["reason"] = "Cannot transfer to the same character"
		result["allowed"] = false
	if from_char_id == to_char_id:
	# Prevent self-transfer
        # Check same account
        if not _account_service.is_same_account(from_char_id, to_char_id):
                result["allowed"] = false
                result["reason"] = "Characters not on same account"
                return result
        
        # Get account
        var account_id: String = _account_service._character_to_account.get(from_char_id, "")
        if account_id == "":
                result["allowed"] = false
                result["reason"] = "Account not found"
                return result
        
        # Check if same-account transfer is enabled
        if not _account_service.get_account_setting(account_id, "same_account_transfer_enabled", true):
                result["allowed"] = false
                result["reason"] = "Same-account transfer disabled in settings"
                return result
        
        # Check cooldown
        var stats: Dictionary = _get_stats(account_id)
        var cooldown: int = _account_service.get_account_setting(account_id, "same_account_transfer_cooldown", 60)
        var now := Time.get_unix_time_from_system()
        var time_since := now - stats.get("last_transfer_time", 0.0)
        
        if time_since < cooldown:
                var remaining := int(cooldown - time_since)
                result["allowed"] = false
                result["reason"] = "Cooldown active: %d seconds remaining" % remaining
                cooldown_active.emit(account_id, remaining)
                return result
        
        return result

## Check limits before transfer
func check_limits(account_id: String, gold_amount: int, item_count: int) -> Dictionary:
        var result := {"allowed": true, "reason": ""}
        
        var stats: Dictionary = _get_stats(account_id)
        var max_gold := _account_service.get_account_setting(account_id, "same_account_max_gold_daily", 100000)
        var max_items := _account_service.get_account_setting(account_id, "same_account_max_items_daily", 50)
        
        var current_gold: int = stats.get("gold_today", 0)
        var current_items: int = stats.get("items_today", 0)
        
        if current_gold + gold_amount > max_gold:
                result["allowed"] = false
                result["reason"] = "Daily gold limit reached (%d / %d)" % [current_gold, max_gold]
                transfer_limit_reached.emit(account_id, "gold_daily")
                return result
        
        if current_items + item_count > max_items:
                result["allowed"] = false
                result["reason"] = "Daily item limit reached (%d / %d)" % [current_items, max_items]
                transfer_limit_reached.emit(account_id, "items_daily")
                return result
        
        return result

## Get remaining limits
func get_remaining_limits(account_id: String) -> Dictionary:
        var stats: Dictionary = _get_stats(account_id)
        var max_gold := _account_service.get_account_setting(account_id, "same_account_max_gold_daily", 100000)
        var max_items := _account_service.get_account_setting(account_id, "same_account_max_items_daily", 50)
        
        return {
                "gold_remaining": max(0, max_gold - stats.get("gold_today", 0)),
                "gold_max": max_gold,
                "items_remaining": max(0, max_items - stats.get("items_today", 0)),
                "items_max": max_items,
                "cooldown_remaining": get_cooldown_remaining(account_id)
        }

## Get cooldown remaining
func get_cooldown_remaining(account_id: String) -> int:
        var stats: Dictionary = _get_stats(account_id)
        var cooldown: int = _account_service.get_account_setting(account_id, "same_account_transfer_cooldown", 60)
        var now := Time.get_unix_time_from_system()
        var time_since := now - stats.get("last_transfer_time", 0.0)
        
        return max(0, int(cooldown - time_since))

## Execute same-account transfer
func transfer(from_char_id: String, to_char_id: String, gold: int = 0, item_ids: Array = []) -> Dictionary:
	# Prevent self-transfer
	if from_char_id == to_char_id:
		return {"success": false, "reason": "Cannot transfer to the same character"}

	# Security: Verify same account (defense in depth)
	if not _account_service or not _account_service.is_same_account(from_char_id, to_char_id):
		var fail_result := {"success": false, "reason": "Security: Characters not on same account"}
		transfer_cancelled.emit(from_char_id, to_char_id, fail_result["reason"])
		return fail_result

	var result := {
                "success": false,
                "reason": "",
                "gold_transferred": 0,
                "items_transferred": [],
                "items_failed": []
        }
        
        # Check basic transfer permission
        var can_result := can_transfer(from_char_id, to_char_id)
        if not can_result["allowed"]:
                result["reason"] = can_result["reason"]
                transfer_cancelled.emit(from_char_id, to_char_id, can_result["reason"])
                return result
        
        # Get account
        var account_id: String = _account_service._character_to_account.get(from_char_id, "")
        
        # Check limits
        var limit_result := check_limits(account_id, gold, item_ids.size())
        if not limit_result["allowed"]:
                result["reason"] = limit_result["reason"]
                transfer_cancelled.emit(from_char_id, to_char_id, limit_result["reason"])
                return result
        
        # Get inventories
        var from_inv = _inventory_service.get_inventory(from_char_id)
        var to_inv = _inventory_service.get_inventory(to_char_id)
        
        if not from_inv or not to_inv:
                result["reason"] = "Character not online or inventory not found"
                transfer_cancelled.emit(from_char_id, to_char_id, result["reason"])
                return result
        
        transfer_requested.emit(from_char_id, to_char_id)
        
        # Transfer gold
        if gold > 0:
                if from_inv.remove_gold(gold):
                        to_inv.add_gold(gold)
                        result["gold_transferred"] = gold
                        Logger.info("SameAccountTransfer: Transferred %d gold from %s to %s" % [gold, from_char_id, to_char_id])
                else:
                        result["reason"] = "Insufficient gold"
                        transfer_cancelled.emit(from_char_id, to_char_id, result["reason"])
                        return result
        
        # Transfer items
        for item_id in item_ids:
                var slot := from_inv.find_item(item_id)
                if slot < 0:
                        result["items_failed"].append(item_id)
                        continue
                
                var item: Item = from_inv.get_item(slot)
                if not item:
                        result["items_failed"].append(item_id)
                        continue
                
                var removed: Item = from_inv.remove_item(slot)
                if not removed:
                        result["items_failed"].append(item_id)
                        continue
                
                if to_inv.add_item(removed):
                        result["items_transferred"].append(item_id)
                        Logger.info("SameAccountTransfer: Transferred %s from %s to %s" % [item_id, from_char_id, to_char_id])
                else:
                        # Put back in source
                        from_inv.add_item(removed)
                        result["items_failed"].append(item_id)
        
        # Update stats
        var stats: Dictionary = _get_stats(account_id)
        stats["gold_today"] += result["gold_transferred"]
        stats["items_today"] += result["items_transferred"].size()
        stats["last_transfer_time"] = Time.get_unix_time_from_system()
        
        # Check daily reset
        _check_daily_reset()
        
        result["success"] = true
        transfer_completed.emit(from_char_id, to_char_id, result["gold_transferred"], result["items_transferred"])
        
        return result

## Quick transfer - send to random online character on account
func quick_transfer_to_alt(from_char_id: String, gold: int = 0, item_ids: Array = []) -> Dictionary:
        if not _account_service:
                return {"success": false, "reason": "Account service not available"}
        
        var account_id: String = _account_service._character_to_account.get(from_char_id, "")
        if account_id == "":
                return {"success": false, "reason": "Account not found"}
        
        var chars: Array = _account_service.get_online_account_characters(account_id)
        chars.erase(from_char_id)  # Remove self
        
        if chars.is_empty():
                return {"success": false, "reason": "No other online characters on this account"}
        
        # Transfer to first available alt
        return transfer(from_char_id, chars[0], gold, item_ids)

## Get online characters on same account
func get_transfer_targets(from_char_id: String) -> Array:
        if not _account_service:
                return []
        
        var account_id: String = _account_service._character_to_account.get(from_char_id, "")
        if account_id == "":
                return []
        
        var chars: Array = _account_service.get_online_account_characters(account_id)
        chars.erase(from_char_id)
        
        return chars

## Reset daily limits (admin function)
func reset_daily_limits(account_id: String) -> void:
        if _transfer_stats.has(account_id):
                _transfer_stats[account_id]["gold_today"] = 0
                _transfer_stats[account_id]["items_today"] = 0
                _transfer_stats[account_id]["last_reset"] = Time.get_unix_time_from_system()
                Logger.info("SameAccountTransferService: Reset limits for %s" % account_id)
