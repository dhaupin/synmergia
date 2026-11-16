## PaymentSkuCatalogData - the shared checkout board.
## One row per purchasable sigil product. Providers own which rows they
## sell and how checkout is processed; this record owns the product
## identity, sigil amount and display copy. A provider that cannot resolve
## its whole mapping refuses checkout instead of selling a partial board.
extends Resource
class_name PaymentSkuCatalogData

@export var id: String = "payment_skus"
@export var skus: Array[Dictionary] = []


## The row for a SKU id, or an empty dict for an unknown id.
func get_sku(sku_id: String) -> Dictionary:
	for row in skus:
		if str(row.get("sku_id", "")) == sku_id:
			return row
	return {}


## The requested rows in provider order. A missing id invalidates the
## whole slice: a provider never sells a short board.
func rows_for(sku_ids: Array) -> Array:
	var rows: Array = []
	for sku_id in sku_ids:
		var row := get_sku(str(sku_id))
		if row.is_empty():
			return []
		rows.append(row.duplicate(true))
	return rows


## Structural gate: a malformed or duplicate row cannot price checkout.
func is_valid() -> bool:
	if id.is_empty() or skus.is_empty():
		return false
	var seen := {}
	for row in skus:
		var sku_id := str(row.get("sku_id", ""))
		if sku_id.is_empty() or seen.has(sku_id):
			return false
		seen[sku_id] = true
		if str(row.get("display_name", "")).is_empty():
			return false
		if int(row.get("sigils", 0)) <= 0:
			return false
		if str(row.get("price_label", "")).is_empty():
			return false
	return true
