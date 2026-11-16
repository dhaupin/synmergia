## ManualPaymentProvider - the shippable placeholder processor.
##
## Checkout is REAL from the buyer's side: begin_purchase opens a
## pending order, cancel cancels it, poll reports its state. Money
## never moves automatically -- an operator fulfills the order through
## fulfill_purchase() (the admin/dev seam; the same hook a Stripe /
## Steam / Xsolla adapter would replace). Nothing here invents goods:
## the shop service only grants sigils when a purchase reports
## "complete", and completion only comes through this seam.
extends "res://core/economy/payment_provider.gd"

## The SKU ids this processor sells. The rows live once in the shared
## data/balance/payment_skus.tres record; this is the processor mapping.
const SKU_IDS := [
	"sigil_pack_pouch",
	"sigil_pack_coffer",
	"sigil_pack_charter",
]

var _pending := {}   # purchase_id -> {player_id, sku_id, sku, status}

func get_id() -> String:
	return "manual"

func get_display_name() -> String:
	return "Manual Checkout (dev seed)"

func get_catalog(_player_id: String) -> Array:
	return _catalog_rows(SKU_IDS)

func begin_purchase(player_id: String, sku_id: String) -> Dictionary:
	var catalog := _catalog_rows(SKU_IDS)
	if catalog.is_empty():
		return {"status": "refused", "reason": "Payment catalog unavailable."}
	for sku in catalog:
		if str(sku.get("sku_id")) == sku_id:
			var pid := "order_%d_%s" % [Time.get_ticks_msec(), player_id]
			_pending[pid] = {
				"player_id": player_id,
				"sku_id": sku_id,
				"sku": sku.duplicate(true),
				"status": "pending",
			}
			return {
				"status": "pending",
				"purchase_id": pid,
				"message": "Order %s opened with the manual provider." % pid,
			}
	return {"status": "refused", "reason": "Unknown SKU: %s" % sku_id}

func poll_purchase(purchase_id: String, _player_id: String = "") -> Dictionary:
	if _pending.has(purchase_id):
		return {"status": str(_pending[purchase_id]["status"]), "purchase_id": purchase_id}
	return {"status": "refused", "reason": "Unknown purchase.", "purchase_id": purchase_id}

func cancel_purchase(purchase_id: String, _player_id: String = "") -> Dictionary:
	if _pending.has(purchase_id):
		# A completed order is PAID: flipping it to cancelled here would
		# bury the money before the poll leg pays it out. Refuse and let
		# the buyer poll instead. (The webhook adapter carries the same
		# guard -- the processor contract, not a provider flavor.)
		if str(_pending[purchase_id]["status"]) == "complete":
			return {"status": "refused", "purchase_id": purchase_id, "reason": "That order already paid out; poll it, do not cancel it."}
		_pending[purchase_id]["status"] = "cancelled"
		return {"status": "cancelled", "purchase_id": purchase_id}
	return {"status": "refused", "reason": "Unknown purchase.", "purchase_id": purchase_id}

## The operator seam: confirm payment outside the game (dashboard,
## webhook, terminal) then bless the order. Polls read statuses,
## never invent them: blessing an unknown id stays refused.
func fulfill_purchase(purchase_id: String) -> Dictionary:
	if _pending.has(purchase_id) and str(_pending[purchase_id]["status"]) == "pending":
		_pending[purchase_id]["status"] = "complete"
		return {"status": "complete", "purchase_id": purchase_id}
	return {"status": "refused", "reason": "Unknown or already-settled purchase.", "purchase_id": purchase_id}
