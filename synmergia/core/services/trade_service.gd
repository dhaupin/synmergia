## TradeService - Player-to-player trading
## Handles trade requests, windows, confirmations, and completion
extends Node

# Service references
var _account_service: AccountService
var _inventory_service: InventoryService
var _same_account_transfer: SameAccountTransferService

# Active trades (trade_id -> trade data)
var _active_trades: Dictionary = {}

# Pending trade requests (player_id -> trade_request)
var _pending_requests: Dictionary = {}

# Trade request timeout
const REQUEST_TIMEOUT_SECONDS: float = 60.0

# Trade states
enum TradeState {
				PENDING,		 # Request sent, waiting for response
				ACCEPTED,		 # Both players accepted, in trade window
				CONFIRMING,	 # Both adding items, ready to confirm
				COMPLETED,	 # Trade executed
				CANCELLED,	 # Trade cancelled by one party
				EXPIRED			 # Request timed out
}

# Trade limits (using GameConfig for centralized configuration)
const MAX_TRADE_SLOTS: int = GameConfig.Trade.MAX_SLOTS

signal trade_requested(from_id: String, to_id: String)
signal trade_accepted(trade_id: String, player1: String, player2: String)
signal trade_declined(from_id: String, to_id: String)
signal trade_cancelled(trade_id: String, cancelled_by: String)
signal trade_confirmed(trade_id: String, player_id: String)
signal trade_unconfirmed(trade_id: String, player_id: String)
signal trade_completed(trade_id: String, trades: Dictionary)
signal trade_started(trade_id: String, player1: String, player2: String)	# Emitted when trade actually begins (both accepted)
signal trade_expired(trade_id: String)
signal trade_failed(trade_id: String)
signal item_added_to_trade(trade_id: String, player_id: String, item_id: String, quantity: int)
signal item_removed_from_trade(trade_id: String, player_id: String, item_id: String, quantity: int)
signal gold_added_to_trade(trade_id: String, player_id: String, amount: int)
signal gold_removed_from_trade(trade_id: String, player_id: String, amount: int)

func _ready() -> void:
				GameLogger.info("TradeService: Ready")
				
				# Initialize service references from autoloads
				_account_service = AccountService if AccountService else null
				_inventory_service = InventoryService if InventoryService else null
				_same_account_transfer = SameAccountTransferService if SameAccountTransferService else null

## Request a trade
func request_trade(from_id: String, to_id: String) -> bool:
	# QoS: Rate limit trade requests (player notified by QoSService)
	if not QoSService.rate_limit(from_id, "trade"):
		return false
	
	# Security: Check if player is trade restricted
	if SecurityService.is_restricted(from_id, "trade"):
		_notify_player(from_id, "You are temporarily restricted from trading.")
		return false
	
	# Check same-account trade
	if _account_service and not _account_service.can_same_account_trade(from_id, to_id)["allowed"]:
		GameLogger.info("TradeService: Same-account trade not allowed between %s and %s" % [from_id, to_id])
		return false

				if from_id == to_id:
								return false
				
				# Check if either player is already in a trade
				if _is_in_trade(from_id) or _is_in_trade(to_id):
								return false
				
				# Check for duplicate requests
				if _pending_requests.has(to_id):
								return false
				
				var request := {
								"from_id": from_id,
								"to_id": to_id,
								"timestamp": Time.get_unix_time_from_system(),
								"expires_at": Time.get_unix_time_from_system() + REQUEST_TIMEOUT_SECONDS
				}
				
				_pending_requests[to_id] = request
				trade_requested.emit(from_id, to_id)
				GameLogger.info("TradeService: Trade request from %s to %s" % [from_id, to_id])
				
				return true

## Accept a trade request
func accept_trade(to_id: String) -> String:
				var request: Dictionary = _pending_requests.get(to_id)
				if not request:
								return ""
				
				# Check if expired
				if Time.get_unix_time_from_system() > request["expires_at"]:
								_pending_requests.erase(to_id)
								trade_expired.emit("")
								return ""
				
				var from_id := request["from_id"]
				var trade_id := "trade_%s_%s_%d" % [from_id, to_id, Time.get_ticks_msec()]
				
				var trade := {
								"id": trade_id,
								"player1": from_id,
								"player2": to_id,
								"state": TradeState.ACCEPTED,
								"player1_items": [],
								"player2_items": [],
								"player1_gold": 0,
								"player2_gold": 0,
								"player1_confirmed": false,
								"player2_confirmed": false,
								"created_at": Time.get_unix_time_from_system()
				}
				
				_active_trades[trade_id] = trade
				_pending_requests.erase(to_id)
				
				trade_accepted.emit(trade_id, from_id, to_id)
				GameLogger.info("TradeService: Trade %s accepted" % trade_id)
				
				return trade_id

## Decline a trade request
func decline_trade(to_id: String) -> bool:
				var request: Dictionary = _pending_requests.get(to_id)
				if not request:
								return false
				
				var from_id := request["from_id"]
				_pending_requests.erase(to_id)
				
				trade_declined.emit(from_id, to_id)
				GameLogger.info("TradeService: Trade declined by %s" % to_id)
				
				return true

## Cancel a trade
func cancel_trade(trade_id: String, player_id: String) -> bool:
				var trade: Dictionary = _active_trades.get(trade_id)
				if not trade:
								return false
				
				if trade["player1"] != player_id and trade["player2"] != player_id:
								return false
				
				_active_trades.erase(trade_id)
				trade_cancelled.emit(trade_id, player_id)
				GameLogger.info("TradeService: Trade %s cancelled by %s" % [trade_id, player_id))
				
				return true

## Add item to trade
func add_item(trade_id: String, player_id: String, item_id: String, quantity: int = 1) -> bool:
				var trade: Dictionary = _active_trades.get(trade_id)
				if not trade or trade["state"] > TradeState.CONFIRMING:
								return false
				
				var items_key := _get_items_key(trade, player_id)
				if items_key == "":
								return false
				
				# Check if item already in trade
				var items: Array = trade[items_key]
				for item_data in items:
								if item_data["item_id"] == item_id:
												return false	# Already added
				
				if items.size() >= MAX_TRADE_SLOTS:
								return false
				
				items.append({"item_id": item_id, "quantity": quantity})
				trade[items_key] = items
				
				# Unconfirm if was confirmed
				_unconfirm(trade, player_id)
				
				item_added_to_trade.emit(trade_id, player_id, item_id, quantity)
				GameLogger.debug("TradeService: %s added %s x%d to trade %s" % [player_id, item_id, quantity, trade_id])
				
				return true

## Remove item from trade
func remove_item(trade_id: String, player_id: String, item_id: String) -> bool:
				var trade: Dictionary = _active_trades.get(trade_id)
				if not trade or trade["state"] > TradeState.CONFIRMING:
								return false
				
				var items_key := _get_items_key(trade, player_id)
				if items_key == "":
								return false
				
				var items: Array = trade[items_key]
				for i in range(items.size()):
								if items[i]["item_id"] == item_id:
												items.remove_at(i)
												trade[items_key] = items
												
												# Unconfirm if was confirmed
												_unconfirm(trade, player_id)
												
												item_removed_from_trade.emit(trade_id, player_id, item_id, 1)
												return true
				
				return false

## Add gold to trade
func add_gold(trade_id: String, player_id: String, amount: int) -> bool:
				var trade: Dictionary = _active_trades.get(trade_id)
				if not trade or trade["state"] > TradeState.CONFIRMING:
								return false
				
				if amount <= 0:
								return false
				
				var gold_key := _get_gold_key(trade, player_id)
				if gold_key == "":
								return false
				
				trade[gold_key] += amount
				
				# Unconfirm if was confirmed
				_unconfirm(trade, player_id)
				
				gold_added_to_trade.emit(trade_id, player_id, amount)
				GameLogger.debug("TradeService: %s added %d gold to trade %s" % [player_id, amount, trade_id])
				
				return true

## Remove gold from trade
func remove_gold(trade_id: String, player_id: String, amount: int) -> bool:
				var trade: Dictionary = _active_trades.get(trade_id)
				if not trade or trade["state"] > TradeState.CONFIRMING:
								return false
				
				var gold_key := _get_gold_key(trade, player_id)
				if gold_key == "":
								return false
				
				if trade[gold_key] < amount:
								return false
				
				trade[gold_key] -= amount
				
				# Unconfirm if was confirmed
				_unconfirm(trade, player_id)
				
				gold_removed_from_trade.emit(trade_id, player_id, amount)
				return true

## Confirm trade
func confirm_trade(trade_id: String, player_id: String) -> bool:
				var trade: Dictionary = _active_trades.get(trade_id)
				if not trade:
								return false
				
				if trade["state"] == TradeState.ACCEPTED:
								trade["state"] = TradeState.CONFIRMING
				
				if trade["state"] != TradeState.CONFIRMING:
								return false
				
				if trade["player1"] == player_id:
								trade["player1_confirmed"] = true
				elif trade["player2"] == player_id:
								trade["player2_confirmed"] = true
				else:
								return false
				
				trade_confirmed.emit(trade_id, player_id)
				
				# Check if both confirmed
				if trade["player1_confirmed"] and trade["player2_confirmed"]:
								return _complete_trade(trade_id)
				
				return true

## Unconfirm trade
func _unconfirm(trade: Dictionary, player_id: String) -> void:
				if trade["state"] != TradeState.CONFIRMING:
								return
				
				if trade["player1"] == player_id:
								trade["player1_confirmed"] = false
				elif trade["player2"] == player_id:
								trade["player2_confirmed"] = false
				
				trade_unconfirmed.emit(trade["id"], player_id)

## Complete the trade
func _complete_trade(trade_id: String) -> bool:
	var trade: Dictionary = _active_trades.get(trade_id)
	if not trade:
		return false

	var player1 := trade["player1"]
	var player2 := trade["player2"]
	var player1_items := trade["player1_items"]
	var player2_items := trade["player2_items"]
	var player1_gold := trade["player1_gold"]
	var player2_gold := trade["player2_gold"]

	# Execute the actual item/gold transfer
	var transfer_success := true
	if _inventory_service:
		var transfer_result := _inventory_service.execute_trade(
			trade_id, player1, player2,
			player1_items, player2_items,
			player1_gold, player2_gold
		)
		trade["transfer_result"] = transfer_result
		transfer_success = transfer_result.get("success", false)

	# Only mark as completed if transfer succeeded
	if transfer_success:
		trade["state"] = TradeState.COMPLETED

		var trades := {
		player1: {
		"items": player1_items,
		"gold": player1_gold
		},
		player2: {
		"items": player2_items,
		"gold": player2_gold
		}
		}

		# Log trade history
		_log_trade(player1, player2, player1_items, player2_items, player1_gold, player2_gold)

		# Set cooldowns
		_set_cooldown(player1)
		_set_cooldown(player2)

		trade_completed.emit(trade_id, trades)
		GameLogger.info("TradeService: Trade %s completed" % trade_id)
	else:
		trade["state"] = TradeState.FAILED
		GameLogger.error("TradeService: Trade %s failed during item/gold transfer" % trade_id)
		trade_failed.emit(trade_id)

	# Clean up after a delay
	await get_tree().create_timer(5.0).timeout
	_active_trades.erase(trade_id)

	return true

## Get trade info
func get_trade(trade_id: String) -> Dictionary:
				return _active_trades.get(trade_id, {})

## Check if player is in a trade
func _is_in_trade(player_id: String) -> bool:
				for trade in _active_trades.values():
								if trade["player1"] == player_id or trade["player2"] == player_id:
												return true
				return false

## Get player's active trade
func get_player_trade(player_id: String) -> Dictionary:
				for trade in _active_trades.values():
								if trade["player1"] == player_id or trade["player2"] == player_id:
												return trade
				return {}

## Get items key for player
func _get_items_key(trade: Dictionary, player_id: String) -> String:
				if trade["player1"] == player_id:
								return "player1_items"
				elif trade["player2"] == player_id:
								return "player2_items"
				return ""

## Get gold key for player
func _get_gold_key(trade: Dictionary, player_id: String) -> String:
				if trade["player1"] == player_id:
								return "player1_gold"
				elif trade["player2"] == player_id:
								return "player2_gold"
				return ""

## Check if item can be traded (not soulbound, etc.)
func can_trade_item(item: Item) -> bool:
				if item == null:
								return false
				
				# Soulbound items cannot be traded
				if item.soulbound:
								GameLogger.debug("TradeService: Item %s cannot be traded (soulbound)" % item.display_name)
								return false
				
				# Items bound on pickup cannot be traded
				if item.bind_on_pickup or item.is_bound:
								GameLogger.debug("TradeService: Item %s cannot be traded (bound)" % item.display_name)
								return false
				
				# Items bound on equip cannot be traded (only after equip - handled separately)
				# Note: bind_on_equip items can be traded BEFORE being equipped
				# This is checked separately when equipping
				
				# Check for quest items (would need quest system integration)
				# For now, items with required_class are assumed to be quest/achievement items
				if item.required_class == "QUEST_ONLY":
								GameLogger.debug("TradeService: Item %s cannot be traded (quest item)" % item.display_name)
								return false
				
				# Check if item is unique and already owned
				if item.unique and _is_item_owned_by_anyone(item.id):
								GameLogger.debug("TradeService: Item %s cannot be traded (unique, already owned)" % item.display_name)
								return false
				
				return true

## Check if an item with this base ID is owned by anyone
func _is_item_owned_by_anyone(item_id: String) -> bool:
				if not InventoryService:
								return false
				
				var all_players := EntityService.get_all_players() if EntityService else []
				for player in all_players:
								if not is_instance_valid(player):
												continue
								var inventory: Dictionary = InventoryService.get_player_inventory(player.entity_id)
								for slot_key in inventory:
												var slot_data = inventory[slot_key]
												if slot_data.has("item_id") and slot_data["item_id"] == item_id:
																return true
				return false

## Get pending trade request for player
func get_pending_request(player_id: String) -> Dictionary:
				return _pending_requests.get(player_id, {})

# ============ TRADE HISTORY ============

# Trade history (player_id -> [completed trades])
var _trade_history: Dictionary = {}

# Max history per player
const MAX_HISTORY: int = GameConfig.Trade.MAX_HISTORY

## Get trade history for player

## Quick same-account trade (bypasses trade window)
## Returns result dict with success status
func quick_same_account_trade(from_id: String, to_id: String, 
															 from_gold: int, to_gold: int = 0,
															 from_items: Array = [], to_items: Array = []) -> Dictionary:
var result := {
"success": false,
"reason": "",
"trade_id": ""
}

# Check same account
if not is_same_account(from_id, to_id):
result["reason"] = "Not same account"
return result

# Check if quick trade is allowed for this account
var account_id: String = ""
if _account_service:
account_id = _account_service._character_to_account.get(from_id, "")
if account_id != "":
var allowed := _account_service.get_account_setting(account_id, "allow_same_account_trade", true)
if not allowed:
result["reason"] = "Same-account trade disabled"
return result

# Use SameAccountTransferService if available
if _same_account_transfer:
# Transfer from -> to
var r1 := _same_account_transfer.transfer(from_id, to_id, from_gold, from_items)
# Transfer to -> from (if any)
var r2 := {"success": true, "items_transferred": []}
if to_gold > 0 or not to_items.is_empty():
r2 = _same_account_transfer.transfer(to_id, from_id, to_gold, to_items)

result["success"] = r1["success"] and r2["success"]
result["from_transfer"] = r1
result["to_transfer"] = r2
trade_completed.emit("", result)
return result

# Fallback to inventory service
if _inventory_service:
var exec_result := _inventory_service.execute_trade(
"quick_%s_%s" % [from_id, to_id],
from_id, to_id,
from_items, to_items,
from_gold, to_gold
)
result["success"] = exec_result["success"]
trade_completed.emit("", result)
return result

result["reason"] = "No transfer service available"
return result

func get_trade_history(player_id: String, limit: int = 20) -> Array:
				var history: Array = _trade_history.get(player_id, [])
				return history.slice(max(0, history.size() - limit), history.size())

## Log completed trade
func _log_trade(player1: String, player2: String, player1_items: Array, player2_items: Array, 
								player1_gold: int, player2_gold: int) -> void:
				var timestamp := Time.get_unix_time_from_system()
				
				# Log for player 1
				if not _trade_history.has(player1):
								_trade_history[player1] = []
				_trade_history[player1].append({
								"timestamp": timestamp,
								"partner_id": player2,
								"items_given": player1_items,
								"items_received": player2_items,
								"gold_given": player1_gold,
								"gold_received": player2_gold
				})
				
				# Log for player 2
				if not _trade_history.has(player2):
								_trade_history[player2] = []
				_trade_history[player2].append({
								"timestamp": timestamp,
								"partner_id": player1,
								"items_given": player2_items,
								"items_received": player1_items,
								"gold_given": player2_gold,
								"gold_received": player1_gold
				})
				
				# Trim history
				while _trade_history[player1].size() > MAX_HISTORY:
								_trade_history[player1].pop_at(0)
				while _trade_history[player2].size() > MAX_HISTORY:
								_trade_history[player2].pop_at(0)

# ============ ANTI-SCAM MEASURES ============

# Anti-scam settings
var _confirmation_countdown_seconds: float = 3.0
var _trade_cooldown_seconds: float = 10.0
var _player_last_trade: Dictionary = {}

signal confirmation_countdown_started(trade_id: String, seconds: float)
signal confirmation_countdown_cancelled(trade_id: String, cancelled_by: String)
signal confirmation_countdown_tick(trade_id: String, seconds_remaining: float)
signal confirmation_countdown_complete(trade_id: String)

## Start confirmation countdown (anti-scam)
func start_confirmation_countdown(trade_id: String) -> bool:
				var trade: Dictionary = _active_trades.get(trade_id)
				if not trade:
								return false
				if trade["state"] != TradeState.CONFIRMING:
								return false
				if not (trade["player1_confirmed"] and trade["player2_confirmed"]):
								return false
				trade["countdown_started"] = Time.get_unix_time_from_system()
				trade["countdown_seconds"] = _confirmation_countdown_seconds
				confirmation_countdown_started.emit(trade_id, _confirmation_countdown_seconds)
				GameLogger.info("TradeService: Countdown started for trade %s" % trade_id)
				return true

## Cancel confirmation countdown
func cancel_confirmation_countdown(trade_id: String, player_id: String) -> bool:
				var trade: Dictionary = _active_trades.get(trade_id)
				if not trade or not trade.has("countdown_started"):
								return false
				trade.erase("countdown_started")
				trade.erase("countdown_seconds")
				trade["player1_confirmed"] = false
				trade["player2_confirmed"] = false
				confirmation_countdown_cancelled.emit(trade_id, player_id)
				return true

## Check trade cooldown
func can_trade(player_id: String) -> bool:
				if _player_last_trade.has(player_id):
								var elapsed := Time.get_unix_time_from_system() - _player_last_trade[player_id]
								if elapsed < _trade_cooldown_seconds:
												return false
				return true

## Get cooldown remaining
func get_cooldown_remaining(player_id: String) -> float:
				if not _player_last_trade.has(player_id):
								return 0.0
				var elapsed := Time.get_unix_time_from_system() - _player_last_trade[player_id]
				return max(0.0, _trade_cooldown_seconds - elapsed)

## Set cooldown (called after trade completes)
func _set_cooldown(player_id: String) -> void:
				_player_last_trade[player_id] = Time.get_unix_time_from_system()

# ============ TRADE WINDOW UI HELPERS ============

## Get trade summary for UI
func get_trade_summary(trade_id: String, player_id: String) -> Dictionary:
				var trade: Dictionary = _active_trades.get(trade_id, {})
				if trade.is_empty():
								return {}
				var is_player1 := trade["player1"] == player_id
				var other_id := trade["player2"] if is_player1 else trade["player1"]
				var my_items: Array = trade["player1_items"] if is_player1 else trade["player2_items"]
				var other_items: Array = trade["player2_items"] if is_player1 else trade["player1_items"]
				var my_gold: int = trade["player1_gold"] if is_player1 else trade["player2_gold"]
				var other_gold: int = trade["player2_gold"] if is_player1 else trade["player1_gold"]
				return {
								"trade_id": trade_id,
								"other_player_id": other_id,
								"my_items": my_items,
								"other_items": other_items,
								"my_gold": my_gold,
								"other_gold": other_gold,
								"my_confirmed": trade["player1_confirmed"] if is_player1 else trade["player2_confirmed"],
								"other_confirmed": trade["player2_confirmed"] if is_player1 else trade["player1_confirmed"],
								"state": trade["state"],
								"countdown_remaining": _get_countdown_remaining(trade)
				}

## Get countdown remaining
func _get_countdown_remaining(trade: Dictionary) -> float:
				if not trade.has("countdown_started"):
								return 0.0
				var elapsed := Time.get_unix_time_from_system() - trade["countdown_started"]
				return max(0.0, _confirmation_countdown_seconds - elapsed)

## Validate trade (for restrictions)
func validate_trade(player_id: String, item: Item) -> Dictionary:
				var result := {"valid": true, "reason": ""}
				if item.get("soulbound", false):
								result["valid"] = false
								result["reason"] = "Soulbound items cannot be traded"
								return result
				if item.get("bind_on_pickup", false):
								result["valid"] = false
								result["reason"] = "Bind-on-pickup items cannot be traded"
								return result
				if item.get("is_quest_item", false):
								result["valid"] = false
								result["reason"] = "Quest items cannot be traded"
								return result
				if not can_trade(player_id):
								result["valid"] = false
								result["reason"] = "Trade cooldown active"
								return result
				return result

## Check if same account
func is_same_account(player1_id: String, player2_id: String) -> bool:
				if AccountService:
					return AccountService.is_same_account(player1_id, player2_id)
				return false

## Refund all items and gold when trade is cancelled
func _refund_trade_items(trade: Dictionary) -> void:
if not _inventory_service:
return

var player1 := trade["player1"]
var player2 := trade["player2"]

# Refund player1's items
var p1_items: Array = trade.get("player1_items", [])
for item_data in p1_items:
var item_id := item_data.get("item_id", "")
var quantity: int = item_data.get("quantity", 1)
if _inventory_service.has_inventory(player1):
var inv: InventoryComponent = _inventory_service.get_inventory(player1)
var slot := inv.find_item(item_id)
if slot >= 0:
inv.remove_item(slot, quantity)

# Refund player2's items
var p2_items: Array = trade.get("player2_items", [])
for item_data in p2_items:
var item_id := item_data.get("item_id", "")
var quantity: int = item_data.get("quantity", 1)
if _inventory_service.has_inventory(player2):
var inv: InventoryComponent = _inventory_service.get_inventory(player2)
var slot := inv.find_item(item_id)
if slot >= 0:
inv.remove_item(slot, quantity)

# Refund gold
var p1_gold: int = trade.get("player1_gold", 0)
var p2_gold: int = trade.get("player2_gold", 0)

if p1_gold > 0 and _inventory_service.has_inventory(player1):
# Find and remove the gold from player2's side (it was added during trade)
var inv1: InventoryComponent = _inventory_service.get_inventory(player1)
inv1.add_gold(p1_gold)

if p2_gold > 0 and _inventory_service.has_inventory(player2):
var inv2: InventoryComponent = _inventory_service.get_inventory(player2)
inv2.add_gold(p2_gold)

GameLogger.debug("TradeService: Refunded items and gold for cancelled trade")

## ============================================================================
## PLAYER NOTIFICATIONS
## ============================================================================

## Send notification to player
func _notify_player(player_id: String, message: String) -> void:
if NotificationService:
NotificationService.send_to_player(
player_id,
message,
NotificationService.NotificationType.WARNING,
NotificationService.Priority.HIGH
)
GameLogger.debug("TradeService: Notified %s: %s" % [player_id, message])
