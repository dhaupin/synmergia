## WebhookPaymentProvider - the hosted-checkout adapter armor.
##
## THE REAL-MONEY SHAPE: an external processor (Stripe, Steam, whatever)
## opens checkout through begin_purchase() and later POSTs the outcome
## to a webhook. This provider IS the receiving seam every such
## adapter inherits or swaps in. Real money talk lives ONLY behind
## this file; gameplay never names it.
##
## DEFENSE IN DEPTH (every leg fails closed; the chain runs in this
## exact order so an attacker has to pass each gate into the next):
##   1. SECRET ZERO-KNOWLEDGE -- the HMAC secret is read from the
##      environment (PAYMENT_WEBHOOK_SECRET) on every verification; it
##      is never written in this repo and the provider RUNS NOTHING if
##      it is absent: unsigned payloads die at the door.
##   2. SIGNATURE ALLOMORPH -- HMAC-SHA256 over the raw payload bytes;
##      the signature arrives in the reserved header (x-synmergia-signature
##      = "t=<unix_ts>,v1=<hex-digest>"). Tampered payloads die here.
##   3. FRESHNESS -- the signed timestamp must sit inside a 5-minute
##      window; older envelopes die, which kills transcript-replay.
##   4. ORDER BINDING -- the payload's purchase_id must name a PENDING
##      order this provider itself opened for the player; foreign ids
##      die -- the caller NEVER supplies player identity or amounts.
##   5. SERVER-SIDE ACCOUNTING -- the granted sigil figure is read from
##      the provider's own catalog, never from the payload.
##   6. IDEMPOTENCE -- an order completes ONCE; a second webhook for a
##      consumed order reports "already processed" honestly (no double
##      grant, no double completion).
## The service-layer grant then re-validates kind/sigils itself, so a
## compromised processor truth still cannot inflate the purse.
##
## The transport that delivers webhooks (HTTP server, agent router,
## future srv layer) is NOT this file's job: it must call
## handle_webhook(canonical_bytes, headers) exactly once per delivery
## with the RAW body bytes.
## Receipt-lore law: extends by RES path (bare class_name extends relies
## on the global class cache, which --check-only and script-mode
## receipts have not built).
extends "res://core/economy/payment_provider.gd"

const SECRET_ENV := "PAYMENT_WEBHOOK_SECRET"
const SIGNATURE_HEADER := "x-synmergia-signature"
const FRESHNESS_SEC := 300.0
const SKUS := [
	{"sku_id": "sigil_100", "display_name": "100 Concord Sigils", "sigils": 100, "price_label": "$4.99"},
	{"sku_id": "sigil_280", "display_name": "280 Concord Sigils", "sigils": 280, "price_label": "$12.99"},
	{"sku_id": "sigil_600", "display_name": "600 Concord Sigils + 50 bonus", "sigils": 650, "price_label": "$24.99"},
]

## purchase_id -> {purchase_id, player_id, sku_id, sigils, state}
var _orders := {}
var _rng := RandomNumberGenerator.new()

## REBOOT LAW, provider half: the SERVICE hydrates its open orders from
## the KV door, but its truth (pending vs paid vs walked-away) lives
## HERE -- a fresh process with an empty provider board would refuse a
## genuinely-paid webhook and strand a paid checkout. Every order is
## written through at birth and on every state move (completed and
## cancelled orders STAY as records, so duplicate deliveries stay
## honestly refused after a reboot instead of re-binding a fresh
## pending order). Adapters are re-registered at boot; their state is
## not born there.
const KV_PREFIX := "premium:webhookorder:"

func _init() -> void:
	_hydrate_orders()

func _hydrate_orders() -> void:
	var store := DictStore.new()
	for key in store.all_keys():
		if not key.begins_with(KV_PREFIX):
			continue
		var order = store.get_value(key)
		if order is Dictionary and not order.is_empty():
			var pid := str(order.get("purchase_id", ""))
			if pid != "":
				_orders[pid] = order

func _persist_order(purchase_id: String) -> void:
	var store := DictStore.new()
	var order: Dictionary = _orders.get(purchase_id, {})
	if order.is_empty():
		store.erase(KV_PREFIX + purchase_id)
	else:
		store.set_value(KV_PREFIX + purchase_id, order.duplicate(true))

func get_id() -> String:
	return "webhook"

func get_display_name() -> String:
	return "Hosted Checkout (webhook)"

func get_catalog(_player_id: String) -> Array:
	return SKUS.duplicate(true)

func begin_purchase(player_id: String, sku_id: String) -> Dictionary:
	if player_id == "" or sku_id == "":
		return {"status": "refused", "reason": "Missing buyer or SKU."}
	var sku := _sku_for(sku_id)
	if sku.is_empty():
		return {"status": "refused", "reason": "That SKU is not on this processor's board."}
	# One pending order per buyer -- the panel shows one, so the books
	# carry one. A second open dies HERE, not downstream.
	for order in _orders.values():
		if str(order.get("player_id")) == player_id and str(order.get("state")) == "pending":
			return {"status": "refused", "reason": "An order is already open at this processor."}
	# The id must be genuinely unique: a collision would silently
	# OVERWRITE a standing order and let a webhook name the wrong SKU.
	var purchase_id := ""
	while purchase_id == "" or _orders.has(purchase_id):
		purchase_id = "pay_%d_%d" % [Time.get_unix_time_from_system() * 1000.0, _rng.randi() % 100000]
	_orders[purchase_id] = {
		"purchase_id": purchase_id,
		"player_id": player_id,
		"sku_id": sku_id,
		"sigils": int(sku.get("sigils", 0)),
		"state": "pending",
	}
	_persist_order(purchase_id)
	return {"status": "pending", "purchase_id": purchase_id, "message": "Checkout hosted; awaiting the processor's webhook."}

func poll_purchase(purchase_id: String, _player_id: String = "") -> Dictionary:
	var order: Dictionary = _orders.get(purchase_id, {})
	if order.is_empty():
		return {"status": "refused", "purchase_id": purchase_id, "reason": "Unknown purchase."}
	var state := str(order.get("state", "pending"))
	if state == "completed":
		return {"status": "complete", "purchase_id": purchase_id}
	if state == "cancelled":
		return {"status": "cancelled", "purchase_id": purchase_id}
	return {"status": "pending", "purchase_id": purchase_id}

func cancel_purchase(purchase_id: String, _player_id: String = "") -> Dictionary:
	var order: Dictionary = _orders.get(purchase_id, {})
	if order.is_empty():
		return {"status": "refused", "purchase_id": purchase_id, "reason": "Unknown purchase."}
	# A completed order is PAID: cancelling it now would bury the money
	# (state flips to cancelled, the poll leg closes empty, the sigils
	# never land). Refuse and let the poll leg pay it instead.
	if str(order.get("state")) == "completed":
		return {"status": "refused", "purchase_id": purchase_id, "reason": "That order already paid out; poll it, do not cancel it."}
	order["state"] = "cancelled"
	_persist_order(purchase_id)
	return {"status": "cancelled", "purchase_id": purchase_id}

## THE WEBHOOK DOOR. payload_bytes = the RAW body exactly as delivered
## (never a re-serialized dict); headers = the delivery's headers (a
## Dictionary of lowercased name -> value). Every leg is silent-tight;
## refusals name the leg that stopped the payload, nothing more.
func handle_webhook(payload_bytes: PackedByteArray, headers: Dictionary) -> Dictionary:
	var secret := OS.get_environment(SECRET_ENV)
	if secret.is_empty():
		return {"status": "refused", "reason": "No webhook secret is configured; refusing everything (fail closed)."}

	# 1. The signature envelope: t=<ts>,v1=<hmac>.
	var header_value := str(headers.get(SIGNATURE_HEADER, "")).to_lower()
	var t_part := ""
	var v_part := ""
	for segment in header_value.split(",", false):
		var bits: PackedStringArray = segment.strip_edges().split("=", true, 1)
		if bits.size() == 2 and bits[0] == "t":
			t_part = bits[1]
		elif bits.size() == 2 and bits[0] == "v1":
			v_part = bits[1]
	if t_part == "" or v_part == "":
		return {"status": "refused", "reason": "The signature header is malformed; refusing."}

	# 2. HMAC-SHA256 over the RAW bytes. A secret that cannot derive a
	# signature is a DEAD secret, never a skipped gate: refuse (fail
	# closed) rather than let an unsigned payload past the door.
	var expected := _hmac_hex(secret, payload_bytes)
	if expected.is_empty():
		return {"status": "refused", "reason": "The verification could not be sealed; refusing (fail closed)."}
	if not _constant_time_equal(expected, v_part):
		return {"status": "refused", "reason": "Signature mismatch; the payload died at the door."}

	# 3. Freshness window (replay kill).
	var sent_ts := float(t_part) if t_part.is_valid_float() else -1.0
	if sent_ts < 0.0 or abs(Time.get_unix_time_from_system() - sent_ts) > FRESHNESS_SEC:
		return {"status": "refused", "reason": "The envelope is stale (or its clock is lying); refusing."}

	# 4. Parse + ORDER BINDING: the payload must name a pending order
	# this provider opened. The body carries ids only -- never amounts.
	var parsed = JSON.parse_string(payload_bytes.get_string_from_utf8())
	if parsed is not Dictionary:
		return {"status": "refused", "reason": "The payload is not a JSON object; refusing."}
	var payload: Dictionary = parsed
	var purchase_id := str(payload.get("purchase_id", ""))
	var order: Dictionary = _orders.get(purchase_id, {})
	if order.is_empty() or str(order.get("state")) != "pending":
		return {"status": "refused", "reason": "That delivery names no open order on this processor."}

	# 5. Honest disposition of the event type.
	var event := str(payload.get("event", "")).to_lower()
	match event:
		"checkout.completed":
			order["state"] = "completed"
			_persist_order(purchase_id)
			return {"status": "complete", "purchase_id": purchase_id}
		"checkout.expired", "checkout.cancelled":
			order["state"] = "cancelled"
			_persist_order(purchase_id)
			return {"status": "cancelled", "purchase_id": purchase_id}
		_:
			return {"status": "refused", "reason": "Unknown event type; refusing."}

## The operator-over-shoulder leg (used by tests and admin tooling only):
## truth the processor itself reports.
func fulfill_purchase(purchase_id: String) -> Dictionary:
	var order: Dictionary = _orders.get(purchase_id, {})
	if order.is_empty():
		return {"status": "refused", "purchase_id": purchase_id, "reason": "Unknown purchase."}
	order["state"] = "completed"
	_persist_order(purchase_id)
	return {"status": "complete", "purchase_id": purchase_id}

## ---------------------------------------------------------------------------

func _sku_for(sku_id: String) -> Dictionary:
	for sku in SKUS:
		if str(sku.get("sku_id", "")) == sku_id:
			return sku
	return {}

func _hmac_hex(secret: String, bytes: PackedByteArray) -> String:
	if secret.is_empty():
		return ""
	var hmac := HMACContext.new()
	hmac.start(HashingContext.HASH_SHA256, secret.to_utf8_buffer())
	hmac.update(bytes)
	return hmac.finish().hex_encode()

## Not a cryptographic constant-time compare, but string timing games
## die at the HMAC anyway -- this keeps the byte-count tell narrow.
func _constant_time_equal(a: String, b: String) -> bool:
	var ab := a.to_utf8_buffer()
	var bb := b.to_utf8_buffer()
	var mismatch := ab.size() != bb.size()
	var limit: int = max(ab.size(), bb.size())
	for i in limit:
		mismatch = mismatch or (ab[i % max(1, ab.size())] != bb[i % max(1, bb.size())])
	return not mismatch
