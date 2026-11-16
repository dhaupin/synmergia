## test_payment_skus.gd - THE SHARED CHECKOUT BOARD RECEIPT.
##
## The two payment providers used to carry separate SKU arrays. This
## receipt locks the one-record law:
##   1. DataService resolves one valid payment_skus record with six rows.
##   2. The manual and webhook providers resolve their own mapped slices
##      from that record, with their existing amounts and labels.
##   3. Both still refuse an unknown SKU.
##   4. Removing the record makes both providers fail closed instead of
##      selling a partial board.
##
## Run:
##   cd game && godot --headless --path . --script res://tests/test_payment_skus.gd
extends SceneTree

var _checks := 0
var _fails := 0


func _init() -> void:
	call_deferred("_run")


func _check(label: String, cond: bool) -> void:
	_checks += 1
	if cond:
		print("  [OK] " + label)
	else:
		_fails += 1
		print("  [FAIL] " + label)


func _finish() -> void:
	print("--- PAYMENT SKUS: %d passed, %d failed ---" % [_checks - _fails, _fails])
	quit(0 if _fails == 0 else 1)


func _rows_match(rows: Array, catalog) -> bool:
	if rows.is_empty():
		return false
	for row in rows:
		var expected: Dictionary = catalog.get_sku(str(row.get("sku_id", "")))
		if expected.is_empty():
			return false
		for key in ["display_name", "sigils", "price_label"]:
			if row.get(key) != expected.get(key):
				return false
	return true


func _run() -> void:
	var ds = root.get_node_or_null("DataService")
	_check("DataService autoload present", ds != null)
	if ds == null:
		return _finish()
	_check("DataService exposes the shared SKU catalog",
		ds.has_method("get_payment_sku_catalog"))
	var catalog = ds.get_payment_sku_catalog()
	_check("payment_skus record resolves", catalog != null)
	if catalog == null:
		return _finish()
	_check("payment_skus record is valid", catalog.is_valid())
	_check("record carries all six shared rows", catalog.skus.size() == 6)

	var ManualProvider = load("res://core/economy/manual_payment_provider.gd")
	var WebhookProvider = load("res://core/economy/webhook_payment_provider.gd")
	var manual = ManualProvider.new()
	var webhook = WebhookProvider.new()
	var manual_rows: Array = manual.get_catalog("probe")
	var webhook_rows: Array = webhook.get_catalog("probe")
	_check("manual maps three rows", manual_rows.size() == 3)
	_check("webhook maps three rows", webhook_rows.size() == 3)
	_check("manual rows resolve from the shared record", _rows_match(manual_rows, catalog))
	_check("webhook rows resolve from the shared record", _rows_match(webhook_rows, catalog))

	var pouch: Dictionary = catalog.get_sku("sigil_pack_pouch")
	var sigil_100: Dictionary = catalog.get_sku("sigil_100")
	_check("manual pouch keeps 5 sigils", int(pouch.get("sigils", 0)) == 5)
	_check("webhook 100 keeps 100 sigils", int(sigil_100.get("sigils", 0)) == 100)
	_check("webhook 600 keeps its 650-sigil bonus",
		int(catalog.get_sku("sigil_600").get("sigils", 0)) == 650)

	var manual_unknown: Dictionary = manual.begin_purchase("probe", "sigil_pack_ghost")
	var webhook_unknown: Dictionary = webhook.begin_purchase("probe", "sigil_ghost")
	_check("manual still refuses an unknown SKU",
		str(manual_unknown.get("status")) == "refused")
	_check("webhook still refuses an unknown SKU",
		str(webhook_unknown.get("status")) == "refused")

	# Fail-closed leg: drop the record, leave everything else intact.
	var balance: Dictionary = ds.get("_balance")
	var saved = balance.get("payment_skus")
	_check("record is registered in balance data", saved != null)
	balance.erase("payment_skus")
	var broken_manual = ManualProvider.new()
	var broken_webhook = WebhookProvider.new()
	_check("manual sells nothing without the record",
		broken_manual.get_catalog("probe").is_empty())
	_check("webhook sells nothing without the record",
		broken_webhook.get_catalog("probe").is_empty())
	var manual_missing: Dictionary = broken_manual.begin_purchase("probe", "sigil_pack_pouch")
	var webhook_missing: Dictionary = broken_webhook.begin_purchase("probe", "sigil_100")
	_check("manual names the missing catalog",
		str(manual_missing.get("status")) == "refused"
		and str(manual_missing.get("reason", "")).contains("catalog"))
	_check("webhook names the missing catalog",
		str(webhook_missing.get("status")) == "refused"
		and str(webhook_missing.get("reason", "")).contains("catalog"))
	if saved != null:
		balance["payment_skus"] = saved
	_check("catalog restored for the rest of the run",
		ds.get_payment_sku_catalog() != null)

	_finish()
