## BlackMarketData - the Underdeck Fixer's roll board.
## The service owns the weighted draw, debit/refund ledger, and rate gate;
## this record owns the priced tiers, currency, and the LootTable each tier
## reads. One row per roll: roll_id, label, sigils, table, rarity_boost.
extends Resource
class_name BlackMarketData

@export var id: String = "black_market"
@export var currency_id: String = ""
@export var rolls: Array[Dictionary] = []


## The board row for a tier, or an empty dict for an unknown id.
func get_roll(roll_id: String) -> Dictionary:
	for row in rolls:
		if str(row.get("roll_id", "")) == roll_id:
			return row
	return {}


## Structural gate: a board with no currency or a malformed tier cannot
## price a pull, so the service refuses it instead of drawing for free.
func is_valid() -> bool:
	if id.is_empty() or currency_id.is_empty() or rolls.is_empty():
		return false
	for row in rolls:
		if str(row.get("roll_id", "")).is_empty():
			return false
		if int(row.get("sigils", 0)) <= 0:
			return false
		if str(row.get("table", "")).is_empty():
			return false
	return true
