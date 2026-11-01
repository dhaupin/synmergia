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

## The SKU rows this provider sells. held as DATA so a processor swap
## only reimplements the seam, not the catalog.
const SKU_CATALOG := [
	{
		"sku_id": "sigil_pack_pouch",
		"display_name": "Pouch of Sigils",
		"sigils": 5,
		"price_label": "starter price (not wired)",
	},
	{
		"sku_id": "sigil_pack_coffer",
		"display_name": "Coffer of Sigils",
		"sigils": 12,
		"price_label": "vault price (not wired)",
	},
	{
		"sku_id": "sigil_pack_charter",
		"display_name": "Vault Charter of Sigils",
		"sigils": 30,
		"price_label": "deep-stall price (not wired)",
	},
]

var _pending := {}   # purchase_id -> {player_id, sku_id, sku, status}

func get_id() -> String:
	return "manual"

func get_display_name() -> String:
	return "Manual Checkout (dev seed)"

func get_catalog(_player_id: String) -> Array:
	return SKU_CATALOG.duplicate(true)

func begin_purchase(player_id: String, sku_id: String) -> Dictionary:
	for sku in SKU_CATALOG:
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
