## AgentSlotBalanceData - the one-time Concord Sigil prices for agent seats.
## AgentRoster owns the free floor, the cap and the debit/grant gate; this
## record owns the price of each paid slot.
extends Resource
class_name AgentSlotBalanceData

@export var id: String = "agent_slots"
## Slot index (1-based) -> one-time sigil price.
@export var slot_prices: Dictionary = {
	2: 250,
	3: 900,
	4: 2500,
	5: 6000,
}


func is_valid() -> bool:
	if id.is_empty() or slot_prices.is_empty():
		return false
	for slot in slot_prices:
		if int(slot) < 2:
			return false
		if int(slot_prices[slot]) < 0:
			return false
	return true
