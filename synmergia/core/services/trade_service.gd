## TradeService - Player-to-player trading
## Handles trade requests, windows, confirmations, and completion
class_name TradeService
extends Node

# Active trades (trade_id -> trade data)
var _active_trades: Dictionary = {}

# Pending trade requests (player_id -> trade_request)
var _pending_requests: Dictionary = {}

# Trade request timeout
const REQUEST_TIMEOUT_SECONDS: float = 60.0

# Trade states
enum TradeState {
        PENDING,     # Request sent, waiting for response
        ACCEPTED,    # Both players accepted, in trade window
        CONFIRMING,  # Both adding items, ready to confirm
        COMPLETED,   # Trade executed
        CANCELLED,   # Trade cancelled by one party
        EXPIRED      # Request timed out
}

# Max trade slots
const MAX_TRADE_SLOTS: int = 10

signal trade_requested(from_id: String, to_id: String)
signal trade_accepted(trade_id: String, player1: String, player2: String)
signal trade_declined(from_id: String, to_id: String)
signal trade_cancelled(trade_id: String, cancelled_by: String)
signal trade_confirmed(trade_id: String, player_id: String)
signal trade_unconfirmed(trade_id: String, player_id: String)
signal trade_completed(trade_id: String, trades: Dictionary)
signal trade_expired(trade_id: String)
signal item_added_to_trade(trade_id: String, player_id: String, item_id: String, quantity: int)
signal item_removed_from_trade(trade_id: String, player_id: String, item_id: String, quantity: int)
signal gold_added_to_trade(trade_id: String, player_id: String, amount: int)
signal gold_removed_from_trade(trade_id: String, player_id: String, amount: int)

func _ready() -> void:
        Logger.info("TradeService: Ready")

## Request a trade
func request_trade(from_id: String, to_id: String) -> bool:
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
        Logger.info("TradeService: Trade request from %s to %s" % [from_id, to_id])
        
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
        Logger.info("TradeService: Trade %s accepted" % trade_id)
        
        return trade_id

## Decline a trade request
func decline_trade(to_id: String) -> bool:
        var request: Dictionary = _pending_requests.get(to_id)
        if not request:
                return false
        
        var from_id := request["from_id"]
        _pending_requests.erase(to_id)
        
        trade_declined.emit(from_id, to_id)
        Logger.info("TradeService: Trade declined by %s" % to_id)
        
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
        Logger.info("TradeService: Trade %s cancelled by %s" % [trade_id, player_id))
        
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
                        return false  # Already added
        
        if items.size() >= MAX_TRADE_SLOTS:
                return false
        
        items.append({"item_id": item_id, "quantity": quantity})
        trade[items_key] = items
        
        # Unconfirm if was confirmed
        _unconfirm(trade, player_id)
        
        item_added_to_trade.emit(trade_id, player_id, item_id, quantity)
        Logger.debug("TradeService: %s added %s x%d to trade %s" % [player_id, item_id, quantity, trade_id])
        
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
        Logger.debug("TradeService: %s added %d gold to trade %s" % [player_id, amount, trade_id])
        
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
        
        # TODO: Actually transfer items and gold
        # This would:
        # 1. Remove items from each player's inventory
        # 2. Remove gold from each player's inventory
        # 3. Add items to each player's inventory
        # 4. Add gold to each player's inventory
        
        trade["state"] = TradeState.COMPLETED
        
        var trades := {
                trade["player1"]: {
                        "items": trade["player1_items"],
                        "gold": trade["player1_gold"]
                },
                trade["player2"]: {
                        "items": trade["player2_items"],
                        "gold": trade["player2_gold"]
                }
        }
        
        trade_completed.emit(trade_id, trades)
        Logger.info("TradeService: Trade %s completed" % trade_id)
        
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
        # TODO: Check item flags for soulbound, bind on pickup, quest item
        return true

## Get pending trade request for player
func get_pending_request(player_id: String) -> Dictionary:
        return _pending_requests.get(player_id, {})
