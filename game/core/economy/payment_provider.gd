## PaymentProvider - the swappable real-money seam (the "plugins" law).
##
## The premium currency (Concord Sigils) never mints from gold; it only
## enters a wallet through THIS seam. A provider is one payment
## processor behind a small contract, so processors can be added,
## removed, or swapped without touching the shop service, the panel,
## or any gameplay code:
##
##   PremiumShopService.singleton().registry().register(MyProcessor.new(), true)
##
## The base provider is honest about being unwired: every leg refuses.
## Concrete providers (ManualPaymentProvider ships) implement
## begin_purchase/poll_purchase and are the ONLY place real money
## talk would ever live. Purchase statuses across the seam:
##   "pending"   -- checkout opened, awaiting the processor
##   "complete"  -- processor confirmed; the shop grants the sigils
##   "cancelled" -- the buyer walked away
##   "refused"   -- the processor said no (carries "reason")
extends RefCounted
class_name PaymentProvider

## Resolve the shared checkout board through DataService. Providers own
## which SKU ids they sell; the rows live once in
## data/balance/payment_skus.tres.
func _sku_catalog():
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	var ds = tree.root.get_node_or_null(NodePath("DataService"))
	if ds == null or not ds.has_method("get_payment_sku_catalog"):
		return null
	return ds.get_payment_sku_catalog()


## The requested rows in provider order. Empty means the record is
## absent, malformed, or missing one of the mapped ids.
func _catalog_rows(sku_ids: Array) -> Array:
	var catalog = _sku_catalog()
	if catalog == null or not catalog.is_valid():
		return []
	return catalog.rows_for(sku_ids)


## One SKU row the shop panel renders. sigils = Concord Sigils granted
## on completion; price_label is a DISPLAY string only (the real
## currency exchange stays inside the processor, never gameplay code).
func get_id() -> String:
	return "base"

func get_display_name() -> String:
	return "Base Provider"

func get_catalog(_player_id: String) -> Array:
	return []

func begin_purchase(_player_id: String, _sku_id: String) -> Dictionary:
	return {"status": "refused", "reason": "No processor behind the base seam."}

func poll_purchase(purchase_id: String, _player_id: String = "") -> Dictionary:
	return {"status": "refused", "reason": "Unknown purchase.", "purchase_id": purchase_id}

func cancel_purchase(purchase_id: String, _player_id: String = "") -> Dictionary:
	return {"status": "refused", "reason": "Unknown purchase.", "purchase_id": purchase_id}
