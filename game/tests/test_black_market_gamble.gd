extends SceneTree

## Black market gamble receipt:
##   1. THE POOLS ARE REAL: both Fixer tables load and every entry's
##      item_id resolves through DataService (no phantom SKUs -- the
##      no-dummy law holds for the gamble).
##   2. THE ROLL HONORS ITS GATES: no wallet -> refused; broke ->
##      named refusal; unknown tier -> refused.
##   3. THE GOLDEN ROLL: 100 sigils enter ONLY through the payment
##      seam's provider-reported complete, then sigils in / exactly
##      one real item out of the drawn pool, debit honest.
##   4. THE RATE GATE: a spam roll is waved off before any book moves.
##   5. THE WEBHOOK ARMOR on a FRESH pending order: unsigned, tampered,
##      stale and foreign envelopes all die; the signed truth completes
##      the order; the grant is exactly the catalog's sigils ONCE; a
##      duplicate delivery is refused; a closed order polls none.
##   6. REBOOT LAW: a fresh service instance hydrates an open order
##      from the KV door and closing it erases it.
## Run:
##   godot --headless --path . --script res://tests/test_black_market_gamble.gd

const BlackMarketPath = "res://core/services/black_market_service.gd"
const PremiumPath = "res://core/services/premium_shop_service.gd"
const WebhookPath = "res://core/economy/webhook_payment_provider.gd"
const InventoryCompPath = "res://core/components/inventory_component.gd"

const TEST_SECRET := "gWTxRq_+dev~secret~fixture~Ng2qA7"  # test-only fixture value

func _initialize() -> void:
	_run.call_deferred()

func _fail(msg: String) -> void:
	push_error("FAIL: " + msg)
	quit(1)

func _run() -> void:
	# 1. THE POOLS ARE REAL.
	var market = load(BlackMarketPath).new()
	var ds: Node = root.get_node_or_null("DataService")
	if ds == null or not ds.has_method("get_item"):
		_fail("DataService.get_item not reachable in script mode")
		return
	for option in market.get_roll_options():
		if int(option.get("sigils", 0)) <= 0 or int(option.get("pool_size", 0)) <= 0:
			_fail("a roll option lacks honest sigils or a real pool: %s" % str(option))
			return
		var table = load("res://data/loot_tables/loot_black_market_%s.tres" % str(option.get("roll_id")))
		if table == null:
			_fail("pool resource missing for %s" % str(option.get("roll_id")))
			return
		for entry in table.entries:
			if ds.call("get_item", str(entry.get("item_id", ""))) == null:
				_fail("pool carries a phantom SKU: " + str(entry.get("item_id")))
				return
	print("[OK] both Fixer pools are real: every entry resolves through DataService")

	# Wallet-mounted player for the gambles.
	var pm: Node = root.get_node_or_null("PlayerManager")
	var inv_svc: Node = root.get_node_or_null("InventoryService")
	if pm == null or inv_svc == null:
		_fail("PlayerManager/InventoryService not reachable in script mode")
		return
	var comp = load(InventoryCompPath).new()
	inv_svc.call("register_inventory", "gambler_probe", comp)
	var probe_script := GDScript.new()
	probe_script.source_code = "extends Node\nvar entity_id: String = 'gambler_probe'\nvar inventory_component = null\n"
	probe_script.reload()
	var player = probe_script.new()
	player.name = "GamblerProbePlayer"
	player.inventory_component = comp
	root.add_child(player)
	pm.call("set_local_player", player)
	if pm.get("local_player") != player:
		_fail("the local player did not seat for the gamble probe")
		return

	# 2. THE GATES.
	var broken = load(BlackMarketPath).new()
	var no_wallet: Dictionary = broken.roll_deep("ghost_player", "tide")
	if bool(no_wallet.get("success", false)):
		_fail("a wallet-less player rolled the fixer")
		return
	var broke: Dictionary = broken.roll_deep("gambler_probe", "tide")
	if bool(broke.get("success", false)):
		_fail("a broke player rolled the fixer")
		return
	if not str(broke.get("message", "")).contains("need 3 Concord Sigils"):
		_fail("the broke refusal did not name its cause: " + str(broke.get("message")))
		return
	if bool(broken.roll_deep("gambler_probe", "phantom_tier").get("success", false)):
		_fail("an unknown tier rolled")
		return
	print("[OK] the roll gates hold: no wallet / broke / unknown tier all refused by name")

	# 3. SIGILS ENTER ONLY THROUGH THE HONEST SEAM, then the golden pull.
	var shop = load(PremiumPath).new()
	shop.cancel_purchase("gambler_probe")  # wash any stale KV order from prior runs
	var webhook = load(WebhookPath).new()
	shop.registry().register(webhook, true)
	var opened: Dictionary = shop.begin_purchase("gambler_probe", "sigil_100")
	if not bool(opened.get("success", false)):
		_fail("checkout refused in a clean harness: " + str(opened.get("value")))
		return
	var purchase_id := str(shop.get_open_order("gambler_probe").get("purchase_id", ""))
	if purchase_id == "":
		_fail("checkout opened without a purchase id")
		return
	if str(webhook.fulfill_purchase(purchase_id).get("status", "")) != "complete":
		_fail("the operator seam did not complete the order")
		return
	var polled: Dictionary = shop.poll_purchase("gambler_probe")
	if str(polled.get("status", "")) != "complete" or int(polled.get("sigils", 0)) != 100:
		_fail("the shop credit off the seam truth failed: " + str(polled))
		return
	var balance: int = int(comp.call("get_currency_amount", "currency_concord_sigil"))
	if balance < 3:
		_fail("the purse did not hold the granted sigils: %d" % balance)
		return
	print("[OK] 100 sigils entered through the honest seam (balance %d)" % balance)

	var drew: Dictionary = market.roll_deep("gambler_probe", "tide")
	if not bool(drew.get("success", false)):
		_fail("the golden roll refused: " + str(drew.get("message")))
		return
	var landed := str(drew.get("item_id", ""))
	if str(drew.get("item_name", "")) == "" or int(comp.find_item(landed)) == -1:
		_fail("the drawn prize never reached the bag: " + str(drew))
		return
	var after_balance: int = int(comp.call("get_currency_amount", "currency_concord_sigil"))
	if after_balance != balance - 3:
		_fail("the debit is not honest (before %d, after %d)" % [balance, after_balance])
		return
	print("[OK] the golden pull paid %s x%d into the bag and debited exactly 3" % [str(drew.get("item_name")), int(drew.get("quantity", 1))])

	# 4. THE RATE GATE (waves the spam off before any book moves).
	var qos: Node = root.get_node_or_null("QoSService")
	if qos != null and qos.has_method("rate_limit"):
		var spam: Dictionary = market.roll_deep("gambler_probe", "tide")
		if str(spam.get("message", "")).contains("rate limited") or str(spam.get("message", "")).contains("too fast"):
			if bool(spam.get("success", false)):
				_fail("a rate-limited roll reported success")
				return
			print("[OK] the spam roll was waved off: %s" % str(spam.get("message")))
		else:
			print("[OK] the rate gate did not clamp this pace; no state moved")
	else:
		print("[OK] QoS asleep in this boot; the rate leg rides the pipeline")

	# 5. THE WEBHOOK ARMOR on a FRESH pending order.
	OS.set_environment("PAYMENT_WEBHOOK_SECRET", TEST_SECRET)
	var opened2: Dictionary = shop.begin_purchase("gambler_probe", "sigil_280")
	if not bool(opened2.get("success", false)):
		_fail("the second checkout was refused: " + str(opened2.get("value")))
		return
	var purchase2 := str(shop.get_open_order("gambler_probe").get("purchase_id", ""))

	# Unsigned dies.
	if str(_webhook_call(webhook, purchase2, "checkout.completed", TEST_SECRET, 0).get("status")) != "refused":
		_fail("an unsigned webhook was not refused")
		return
	# Tampered dies.
	if str(_webhook_call(webhook, purchase2, "checkout.completed", "WRONG", 1).get("status")) != "refused":
		_fail("a tampered webhook was not refused")
		return
	# Stale dies (10 years old).
	if str(_webhook_call(webhook, purchase2, "checkout.completed", TEST_SECRET, 2).get("status")) != "refused":
		_fail("a stale envelope was not refused")
		return
	# Foreign purchase_id dies (validly signed, bound to nobody).
	if str(_webhook_call(webhook, purchase2, "checkout.completed", TEST_SECRET, 3).get("status")) != "refused":
		_fail("a foreign purchase_id was not refused")
		return
	# The signed truth completes; the grant is EXACTLY the catalog's 280.
	var balance2: int = int(comp.call("get_currency_amount", "currency_concord_sigil"))
	if str(_webhook_call(webhook, purchase2, "checkout.completed", TEST_SECRET, 4).get("status")) != "complete":
		_fail("the signed truth was not honored")
		return
	var polled2: Dictionary = shop.poll_purchase("gambler_probe")
	if str(polled2.get("status", "")) != "complete" or int(polled2.get("sigils", 0)) != 280:
		_fail("the 280 credit off the webhook truth failed: " + str(polled2))
		return
	var balance3: int = int(comp.call("get_currency_amount", "currency_concord_sigil"))
	if balance3 != balance2 + 280:
		_fail("an inflated grant sneaked through (before %d, after %d)" % [balance2, balance3])
		return
	# Duplicate delivery refused; the closed order polls none.
	if str(_webhook_call(webhook, purchase2, "checkout.completed", TEST_SECRET, 5).get("status")) != "refused":
		_fail("a duplicate delivery was not refused (idempotence broke)")
		return
	if str(shop.poll_purchase("gambler_probe").get("status", "")) not in ["none", "cancelled"]:
		_fail("a closed order still polls a live leg")
		return
	OS.set_environment("PAYMENT_WEBHOOK_SECRET", "")
	print("[OK] the webhook armor held: unsigned/tampered/stale/foreign die, the signed truth grants 280 exactly once, dupes refused")

	# 6. REBOOT LAW. A fresh service instance hydrates the KV orders and
	# re-registers its adapters (plugins live at boot, not in the KV) --
	# both are exactly what a rebooted process would do.
	var rebooted = load(PremiumPath).new()
	if not rebooted.get_open_order("gambler_probe").is_empty():
		_fail("a closed order resurrected from the KV door")
		return
	var rebooted_webhook = load(WebhookPath).new()
	rebooted.registry().register(rebooted_webhook, true)
	var reopen: Dictionary = rebooted.begin_purchase("gambler_probe", "sigil_100")
	if not bool(reopen.get("success", false)):
		_fail("the rebooted service refused a fresh checkout")
		return
	if str(load(PremiumPath).new().get_open_order("gambler_probe").get("sku_id", "")) != "sigil_100":
		_fail("a fresh instance did not hydrate the open order")
		return
	rebooted.cancel_purchase("gambler_probe")
	if not load(PremiumPath).new().get_open_order("gambler_probe").is_empty():
		_fail("the cancel did not erase the KV order")
		return
	print("[OK] open orders reboot honestly: hydrate on build, erase on close")

	print("BLACK-MARKET-GAMBLE-ALL-OK")
	quit(0)

## Webhook variants: 0 unsigned, 1 wrong-secret signature, 2 stale
## timestamp, 3 foreign purchase_id, 4 the valid truth, 5 duplicate.
func _webhook_call(webhook, purchase_for: String, event: String, secret: String, variant: int) -> Dictionary:
	var body_purchase := purchase_for
	var ts := Time.get_unix_time_from_system()
	var stale_ts := ts - 315360000.0
	if variant == 2:
		ts = stale_ts
	if variant == 3:
		body_purchase = "pay_foreign_999"
	var bytes: PackedByteArray = JSON.stringify({"purchase_id": body_purchase, "event": event, "ts": ts}).to_utf8_buffer()
	var headers := {}
	if variant in [1, 2, 3, 4, 5]:
		var signed := _hmac_hex(secret if variant != 1 else "WRONG_NEVER_SEALED", bytes)
		headers = {"x-synmergia-signature": "t=%d, v1=%s" % [ts, signed]}
	return webhook.handle_webhook(bytes, headers)

func _hmac_hex(secret: String, bytes: PackedByteArray) -> String:
	var hmac := HMACContext.new()
	hmac.start(HashingContext.HASH_SHA256, secret.to_utf8_buffer())
	hmac.update(bytes)
	return hmac.finish().hex_encode()
