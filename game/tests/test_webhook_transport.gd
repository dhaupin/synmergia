extends SceneTree

## Webhook transport receipt (the engine half of the payment webhook
## entry; the bridge sidecar's own suite lives in srv/webhook-bridge):
##   1. BOOT LAW: no WEBHOOK_BRIDGE_URL -> the transport is an honest
##      OFF (enabled stays false, the ledger stays empty); with the URL
##      -> ON, one poller against one bridge, cadence configurable.
##   2. THE ONCE LAW AT THE DOOR: a bridge-shaped envelope
##      {delivery_id, channel, body_b64, headers} whose RAW bytes carry
##      the signed truth completes a pending order with EXACTLY ONE
##      route-to-door; the verdict is 'processed' and the books pay
##      through the panel poll leg.
##   3. REDELIVERY HONESTY: the same delivery_id answers from the
##      ledger -- the resolver count never moves, the verdict repeats,
##      the books stay one paid order.
##   4. REFUSALS ARE ANSWERS: an unsigned envelope dies at the door AND
##      settles in the ledger, so a hostile replay cannot wedge the
##      queue; the refused id never re-runs the door either.
##   5. ROUTES: an unrouted channel never reaches the board; a
##      provider-null board refuses by name; both settle.
##   6. THE RECORD STRIPS NOTHING IT NEEDS: signature headers arrive at
##      the armor case-normalized, raw body bytes verbatim.
## Run:
##   godot --headless --path . --script res://tests/test_webhook_transport.gd

const PremiumPath = "res://core/services/premium_shop_service.gd"
const WebhookPath = "res://core/economy/webhook_payment_provider.gd"
const TransportPath = "res://core/economy/webhook_transport.gd"
const InventoryCompPath = "res://core/components/inventory_component.gd"

const TEST_SECRET := "gWTxRq_+dev~secret~fixture~Ng2qA7"  # test-only fixture value

func _initialize() -> void:
	_run.call_deferred()

func _fail(msg: String) -> void:
	push_error("FAIL: " + msg)
	quit(1)

func _run() -> void:
	# 1. BOOT LAW. The cold transport: no bridge URL in the env.
	OS.set_environment("WEBHOOK_BRIDGE_URL", "")
	var cold: Node = load(TransportPath).new()
	root.add_child(cold)  # _ready reads the env and stays OFF
	if bool(cold.get("_enabled")):
		_fail("the cold transport enabled itself without a bridge URL")
		return
	if not cold.ledger_readout().is_empty():
		_fail("an OFF transport is not a silent transport")
		return
	cold.free()
	print("[OK] boot law: no WEBHOOK_BRIDGE_URL, no poller (OFF is an honest state)")

	# The warm transport.
	OS.set_environment("WEBHOOK_BRIDGE_URL", "http://127.0.0.1:8083")
	var t: Node = load(TransportPath).new()
	root.add_child(t)
	if not bool(t.get("_enabled")):
		_fail("the warm transport did not enable off its env URL")
		return
	if int(t.poll_ms) != 5000:
		_fail("the transport lost its default poll cadence: %d" % int(t.poll_ms))
		return
	t.configure(1234)
	if int(t.poll_ms) != 1234:
		_fail("configure() did not take")
		return
	print("[OK] boot law: the URL-enabled transport is ON with a configurable cadence")

	# 2. THE ONCE LAW AT THE DOOR. Real board, real webhook provider,
	# and a resolver that counts every fresh delivery's route attempt.
	OS.set_environment("PAYMENT_WEBHOOK_SECRET", TEST_SECRET)
	# Wallets mounted for each probe buyer: the poll leg grants into the
	# ONE purse, and an unmounted purse would strand its order honestly
	# (the book-never-buries law) -- that is leg 7's own receipt.
	var inv_svc: Node = root.get_node_or_null("InventoryService")
	if inv_svc == null or not inv_svc.has_method("register_inventory"):
		_fail("InventoryService.register_inventory not reachable in script mode")
		return
	var wallets := {}
	for buyer_id in ["transport_probe", "transport_probe_unsigned", "transport_probe_mixed"]:
		var comp = load(InventoryCompPath).new()
		inv_svc.call("register_inventory", buyer_id, comp)
		wallets[buyer_id] = comp
	var shop = load(PremiumPath).new()
	var webhook = load(WebhookPath).new()
	shop.registry().register(webhook, true)
	var routes := [0]
	t.resolver = func(_provider_id: String):
		routes.append(routes.size() + 0)
		routes[0] = routes[0] + 1
		return webhook

	var test_buyer := "transport_probe"
	var checkout: Dictionary = shop.begin_purchase(test_buyer, "sigil_100")
	if not bool(checkout.get("success", false)):
		_fail("the transport checkout was refused: " + str(checkout.get("value")))
		return
	var purchase_id := str(shop.get_open_order(test_buyer).get("purchase_id", ""))
	var body := JSON.stringify({"purchase_id": purchase_id, "event": "checkout.completed", "ts": Time.get_unix_time_from_system()})
	var raw: PackedByteArray = body.to_utf8_buffer()
	var envelope := {
		"delivery_id": "whk_truth_1",
		"channel": "payment",
		"body_b64": Marshalls.raw_to_base64(raw),
		"headers": {"x-synmergia-signature": "t=%d,v1=%s" % [int(Time.get_unix_time_from_system()) - 1, _hmac_hex(TEST_SECRET, raw)]},
	}
	var verdict: Dictionary = t.deliver_once(envelope)
	if str(verdict.get("verdict")) != "processed":
		_fail("the signed truth did not process through the transport: " + str(verdict))
		return
	if routes[0] != 1:
		_fail("the door was routed %d times for one delivery" % int(routes[0]))
		return
	var bronze_wallet = wallets[test_buyer]
	var paid_order: Dictionary = shop.poll_purchase(test_buyer)
	if str(paid_order.get("status")) != "complete" or int(paid_order.get("sigils")) != 100:
		_fail("the paid order did not ride the poll leg: " + str(paid_order))
		return
	if int(bronze_wallet.call("get_currency_amount", "currency_concord_sigil")) != 100:
		_fail("the poll leg granted a non-100 purse")
		return
	print("[OK] the signed truth rode the transport into the door once (100 sigils through the poll leg)")

	# 3. REDELIVERY HONESTY.
	var again: Dictionary = t.deliver_once(envelope)
	if routes[0] != 1:
		_fail("a redelivery re-routed the door (the once law broke)")
		return
	if str(again.get("verdict")) != "processed":
		_fail("the ledger lost the first verdict: " + str(again))
		return
	var ledger_rows: Array = t.ledger_readout()
	if ledger_rows.size() != 1 or str(ledger_rows[0].get("verdict")) != "processed":
		_fail("the ledger is not one processed row: " + str(ledger_rows))
		return
	print("[OK] a redelivered id re-answers from the ledger -- the door was never re-routed")

	# 4. REFUSALS ARE ANSWERS (and settle, so a replay cannot wedge the
	# queue). A second honest checkout whose delivery arrives UNSIGNED.
	var buyer2 := "transport_probe_unsigned"
	var checkout2: Dictionary = shop.begin_purchase(buyer2, "sigil_280")
	if not bool(checkout2.get("success", false)):
		_fail("the unsigned checkout was refused: " + str(checkout2.get("value")))
		return
	var purchase2 := str(shop.get_open_order(buyer2).get("purchase_id", ""))
	var unsigned := {
		"delivery_id": "whk_unsigned_1",
		"channel": "payment",
		"body_b64": Marshalls.raw_to_base64(JSON.stringify({"purchase_id": purchase2, "event": "checkout.completed", "ts": Time.get_unix_time_from_system()}).to_utf8_buffer()),
		"headers": {},
	}
	var refused: Dictionary = t.deliver_once(unsigned)
	if str(refused.get("verdict")) != "refused" or routes[0] != 2:
		_fail("an unsigned envelope did not die at the (routed) door: " + str(refused))
		return
	var refused_again: Dictionary = t.deliver_once(unsigned)
	if routes[0] != 2 or str(refused_again.get("verdict")) != "refused":
		_fail("a refused envelope re-routed the door or lost its verdict")
		return
	var rows_after: Array = t.ledger_readout()
	if rows_after.size() != 2:
		_fail("a settled refusal is not in the ledger: " + str(rows_after))
		return
	# The unsigned leg never paid; the order polls pending for the
	# signed retry that will follow on the next delivery.
	if str(shop.poll_purchase(buyer2).get("status")) != "pending":
		_fail("an unsigned replay moved the paid books: " + str(shop.poll_purchase(buyer2)))
		return
	print("[OK] refusals are answers: unsigned dies, settles, and a replay neither re-runs nor unsays it")

	# 5. ROUTES: unrouted channel + provider-null board.
	var wrong_channel: Dictionary = t.deliver_once({"delivery_id": "whk_other", "channel": "steam_purchase", "body_b64": "e30=", "headers": {}})
	if str(wrong_channel.get("verdict")) != "refused" or routes[0] != 2:
		_fail("an unrouted channel sneaked at the door: " + str(wrong_channel))
		return
	t.resolver = func(_provider_id: String):
		routes[0] = routes[0] + 1
		return null
	var boardless: Dictionary = t.deliver_once({"delivery_id": "whk_noprov", "channel": "payment", "body_b64": "e30=", "headers": {}})
	if str(boardless.get("verdict")) != "refused" or not str(boardless.get("detail")).contains("no provider"):
		_fail("a provider-null board did not refuse by name: " + str(boardless))
		return
	if t.ledger_readout().size() != 4:
		_fail("the ledger lost a settled delivery: " + str(t.ledger_readout()))
		return
	print("[OK] routes: the channel map and the board both answer by name")

	# 6. THE RECORD STRIPS NOTHING IT NEEDS: a mixed-case signature
	# header through the transport's normalization still honors the
	# armor. (Also proves the RAW byte path twice in a row.)
	t.resolver = func(_provider_id: String):
		return webhook
	var buyer3 := "transport_probe_mixed"
	var checkout3: Dictionary = shop.begin_purchase(buyer3, "sigil_100")
	if not bool(checkout3.get("success", false)):
		_fail("the mixed-case checkout was refused: " + str(checkout3.get("value")))
		return
	var purchase3 := str(shop.get_open_order(buyer3).get("purchase_id", ""))
	var body3 := JSON.stringify({"purchase_id": purchase3, "event": "checkout.completed", "ts": Time.get_unix_time_from_system()})
	var raw3: PackedByteArray = body3.to_utf8_buffer()
	var verdict3: Dictionary = t.deliver_once({
		"delivery_id": "whk_truth_2",
		"channel": "payment",
		"body_b64": Marshalls.raw_to_base64(raw3),
		"headers": {"X-SYNMERGIA-Signature": "t=%d,v1=%s" % [int(Time.get_unix_time_from_system()), _hmac_hex(TEST_SECRET, raw3)]},
	})
	if str(verdict3.get("verdict")) != "processed":
		_fail("the mixed-case signature header did not survive the transport: " + str(verdict3))
		return
	if str(shop.poll_purchase(buyer3).get("status")) != "complete":
		_fail("the mixed-case delivery never paid its order")
		return
	if int(wallets[buyer3].call("get_currency_amount", "currency_concord_sigil")) != 100:
		_fail("the mixed-case poll did not grant exactly 100")
		return
	print("[OK] the delivery ladder kept every byte: signature case-normalized, raw body verbatim")

	# Cleanup: the env secrets leave first.
	OS.set_environment("PAYMENT_WEBHOOK_SECRET", "")
	OS.set_environment("WEBHOOK_BRIDGE_URL", "")
	for buyer_id in wallets:
		inv_svc.call("unregister_inventory", buyer_id)
	t.free()
	print("WEBHOOK-TRANSPORT-ALL-OK")
	quit(0)

func _hmac_hex(secret: String, bytes: PackedByteArray) -> String:
	var hmac := HMACContext.new()
	hmac.start(HashingContext.HASH_SHA256, secret.to_utf8_buffer())
	hmac.update(bytes)
	return hmac.finish().hex_encode()
