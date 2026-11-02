## WebhookTransport - the engine half of the payment webhook entry.
##
## The armored sidecar (srv/webhook-bridge, port 8083, nginx route
## /hooks/) now accepts the external processor's HTTP POSTs and queues
## every delivery VERBATIM -- but until this poller existed the queue
## answered to silence: envelopes landed with zero application legs,
## no provider door ever opened, no GL audit line ever described a
## payload, and three shipped SKUs sat behind a wall that between
## customer and wallet. THE LOOP CLOSED: this transport walks the
## bridge queue, hands each delivery ONCE to the provider board's
## webhook door (handle_webhook(raw_bytes, headers) -- the armor in
## webhook_payment_provider.gd), and acks the VERDICT back on the
## bridge record. THE EXACTLY-ONCE SHAPE:
##   claim   the bridge lease holds one delivery for one poller (TTL
##           lapses on poller death, so a standing delivery is never
##           stranded; redelivery stays honest);
##   once    a per-process ledger (_handled) refuses to re-call
##           handle_webhook for a delivery id this process already
##           resolved -- redelivery re-acks the FIRST verdict;
##   verdict the exact disposition (processed | refused | expired |
##           error) plus the armor's own reason rides the ack, so the
##           operator audit shows what the armor decided, nothing more;
##   fail-soft transport legs (poll/ack network problems) retry on the
##           next tick, but application verdicts ALWAYS ack -- a
##           refusal is an answer, and answering keeps a hostile
##           replay from wedging the queue.
##   At-least-once transport + the armor's order-state idempotence =
##   exactly-once books: a duplicate delivery that reaches the door
##   reports "already processed" and the poll leg pays instead.
## The HMAC secret stays in the ENGINE env (PAYMENT_WEBHOOK_SECRET);
## the transport reads none and verifies none -- it is transport, not
## armor.
##
## Boot law: OFF unless the deployment env carries WEBHOOK_BRIDGE_URL
## (bootstrap sum logged either way). Clients hold no poller: the
## caller is the server runtime (NetworkManager's server boot).
##
## Receipt-lore law: no parse-time preloads of game scripts (autoload
## names register after parse); the provider board resolves at runtime
## through the PremiumShopService singleton, and `resolver` is
## injectable for script-mode receipts.
extends Node

const DEFAULT_POLL_MS := 5000
const MIN_POLL_MS := 1000
const DEFAULT_TIMEOUT_MS := 10000
const MAX_DETAIL := 256

## The board. resolver -> provider for an id; receipts swap it.
var resolver: Callable = Callable()

var poll_ms: int = DEFAULT_POLL_MS
var _bridge_url := ""
var _timeout_ms: int = DEFAULT_TIMEOUT_MS
var _enabled := false
var _busy := false
var _http: HTTPRequest = null
var _ack_http: HTTPRequest = null
var _timer: Timer = null
# delivery_id -> verdict string. THE ONCE LAW's whole runtime: a
# second look at the same id never re-runs the door.
var _handled := {}

## ---------------------------------------------------------------------------

func _ready() -> void:
	_bridge_url = OS.get_environment("WEBHOOK_BRIDGE_URL").rstrip("/")
	if _bridge_url.is_empty():
		_glog("info", "webhook transport: no WEBHOOK_BRIDGE_URL in the env; OFF (clients hold no poller).")
		return
	if OS.has_environment("WEBHOOK_TRANSPORT_TIMEOUT_MS"):
		_timeout_ms = int(OS.get_environment("WEBHOOK_TRANSPORT_TIMEOUT_MS"))
	_http = HTTPRequest.new()
	_http.accept_gzip = false
	_http.timeout = _timeout_sec()
	_http.use_threads = false
	_http.request_completed.connect(_on_poll_result)
	add_child(_http)
	_ack_http = HTTPRequest.new()
	_ack_http.accept_gzip = false
	_ack_http.timeout = _timeout_sec()
	_ack_http.use_threads = false
	_ack_http.request_completed.connect(_on_ack_result)
	add_child(_ack_http)
	_timer = Timer.new()
	_timer.wait_time = float(poll_ms) / 1000.0
	_timer.timeout.connect(_tick)
	add_child(_timer)
	_enabled = true
	_glog("info", "webhook transport: ON -- polling %s/%s every %d ms; delivery ledger empty, the armor owns the books." % [
		_bridge_url, "deliveries/next", poll_ms,
	])
	_timer.start()

func _timeout_sec() -> float:
	return maxf(float(_timeout_ms) / 1000.0, 1.0)

## Runtime seam (env default; receipts may reseat).
func configure(poll_interval_ms: int) -> void:
	poll_ms = max(MIN_POLL_MS, poll_interval_ms)
	if _timer != null:
		_timer.wait_time = float(poll_ms) / 1000.0
		if _enabled and _timer.is_stopped():
			_timer.start()

## ---------------------------------------------------------------------------

## Script-mode-safe GameLog voice.
func _glog(level: String, message: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var log = tree.root.get_node_or_null(NodePath("GameLog")) if tree and tree.root else null
	if log == null or not log.has_method(level):
		print("[webhook-transport] %s: %s" % [level, message])
		return
	log.call(level, message)

## The default board reach: PremiumShopService's provider registry.
func _default_resolver(provider_id: String):
	var script := load("res://core/services/premium_shop_service.gd")
	if script == null or not script.can_instantiate():
		return null
	var svc = script.singleton()
	if svc == null:
		return null
	var board = svc.registry()
	if board == null:
		return null
	return board.get_provider(provider_id)

func _resolver_for(provider_id: String):
	if resolver.is_valid():
		return resolver.call(provider_id)
	return _default_resolver(provider_id)

## The channel route: today ONE channel (payment -> the webhook
## processor), env-overridable when a second processor lands.
func _provider_id_for(channel: String) -> String:
	if channel != "payment":
		return ""
	if OS.has_environment("PAYMENT_WEBHOOK_PROVIDER"):
		return OS.get_environment("PAYMENT_WEBHOOK_PROVIDER")
	return "webhook"

## ---------------------------------------------------------------------------

## THE POLL TICK: one request in flight; transport trouble retries
## next tick, application truth never rewinds.
func _tick() -> void:
	if not _enabled or _busy:
		return
	_busy = true
	var target := _bridge_url + "/deliveries/next"
	var sent := _http.request(target, PackedStringArray(["Accept: application/json"]), HTTPClient.METHOD_GET)
	if sent != OK:
		_busy = false
		_glog("warn", "webhook transport: the poll could not start; retrying on the next tick.")

func _on_poll_result(poll_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if poll_result != HTTPRequest.RESULT_SUCCESS:
		_busy = false
		_glog("warn", "webhook transport: the poll leg failed (result %d); retrying on the next tick." % poll_result)
		return
	if code >= 500:
		_busy = false
		_glog("warn", "webhook transport: the bridge answered %d on the poll; retrying on the next tick." % code)
		return
	if code != 200:
		_busy = false
		_glog("error", "webhook transport: the bridge answered %d on the poll; refusing to continue blind (check WEBHOOK_BRIDGE_URL)." % code)
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if parsed is not Dictionary:
		_busy = false
		_glog("error", "webhook transport: the poll answer is not a JSON object; skipping this beat.")
		return
	var delivery = parsed.get("delivery")
	if delivery is not Dictionary:
		_busy = false
		return  # an empty queue is a quiet poll, never an error
	# A dug-out delivery holds _busy across the door's synchronous run
	# AND its ack flight; the ack handler releases both.
	var claim := str(parsed.get("claim", ""))
	# A record without a lease should not exist and cannot be acked;
	# skipping keeps the TTL reopening it for an honest claim.
	if claim.is_empty():
		_busy = false
		_glog("warn", "webhook transport: the bridge answered a delivery with no claim token; skipping (its TTL reopens it honestly).")
		return
	_handle_claimed(delivery, claim)

## ONE CLAIM: door -> ack. The bridge lease covers both calls. _busy
## stays until the ack flight lands (or dies); the door call itself is
## synchronous.
func _handle_claimed(delivery: Dictionary, claim: String) -> void:
	var delivery_id := str(delivery.get("delivery_id", ""))
	var verdict := deliver_once(delivery)
	deliver_ack(delivery_id, claim, verdict)

## The ack leg: POST {claim, verdict, detail}. The result speaks in
## _on_ack_result; here only "could not even start" is knowable.
func deliver_ack(delivery_id: String, claim: String, verdict: Dictionary) -> void:
	var detail := str(verdict.get("detail", "")).substr(0, MAX_DETAIL)
	var payload := {
		"claim": claim,
		"verdict": str(verdict.get("verdict", "error")),
		"detail": str(detail),
	}
	var target := "%s/deliveries/%s/ack" % [_bridge_url, delivery_id]
	var sent := _ack_http.request(target, PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, JSON.stringify(payload))
	if sent != OK:
		_busy = false
		_glog("warn", "webhook transport: the ack for delivery %s could not start; the claim TTL reopens it honestly (the ledger answers the reopen)." % delivery_id)

func _on_ack_result(poll_result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_busy = false
	if poll_result != HTTPRequest.RESULT_SUCCESS:
		_glog("warn", "webhook transport: the ack flight failed in transit; the claim TTL reopens the delivery, and its ledger answers the reopen.")
		return
	if code == 200:
		return  # the quietest good answer
	if code == 409:
		_glog("warn", "webhook transport: the bridge refused the ack (claim lapsed mid-flight at code %d); the once-law ledger covers the books." % code)
		return
	_glog("warn", "webhook transport: the bridge answered %d on the ack; the claim TTL reopens the delivery honestly." % code)

## ---------------------------------------------------------------------------

## THE ONCE LAW. delivery = {delivery_id, channel, body_b64, ...} as the
## bridge stored it. Returns {verdict, detail}. Only the FIRST encounter
## with an id opens the door; later looks answer from the ledger.
func deliver_once(delivery: Dictionary) -> Dictionary:
	var delivery_id := str(delivery.get("delivery_id", ""))
	if _handled.has(delivery_id):
		var cached := str(_handled.get(delivery_id, ""))
		_glog("info", "webhook transport: delivery %s re-answered from the ledger (%s); the door was never re-opened." % [delivery_id, cached])
		return {"verdict": cached, "detail": "already handled in this process"}
	# Malformed envelope: honesty first, and the delivery still leaves
	# the queue so one broken pulse cannot wedge the transport.
	if delivery_id.is_empty():
		return {"verdict": "error", "detail": "the bridge envelope carried no delivery_id"}
	var channel := str(delivery.get("channel", ""))
	var provider_id := _provider_id_for(channel)
	if provider_id.is_empty():
		var reason: String = "channel '%s' is unrouted (no provider id on the channel map)" % channel
		_settle(delivery_id, "refused", reason)
		return {"verdict": "refused", "detail": reason}
	var provider = _resolver_for(provider_id)
	if provider == null:
		var reason: String = "no provider '%s' is registered on the payment board" % provider_id
		_settle(delivery_id, "refused", reason)
		return {"verdict": "refused", "detail": reason}
	if not provider.has_method("handle_webhook"):
		var reason: String = "provider '%s' speaks no webhook door" % provider_id
		_settle(delivery_id, "refused", reason)
		return {"verdict": "refused", "detail": reason}
	var raw := Marshalls.base64_to_raw(str(delivery.get("body_b64", "")))
	var headers := _normalize_headers(delivery.get("headers", {}))
	var answer: Dictionary = provider.handle_webhook(raw, headers)  # ONCE
	var status := str(answer.get("status", ""))
	if status == "complete":
		_settle(delivery_id, "processed", str(answer.get("purchase_id", "")))
		return {"verdict": "processed", "detail": str(answer.get("purchase_id", ""))}
	if status == "refused":
		var reason2 := str(answer.get("reason", "the door refused"))
		_settle(delivery_id, "refused", reason2)
		return {"verdict": "refused", "detail": reason2}
	if status == "cancelled":
		_settle(delivery_id, "expired", str(answer.get("purchase_id", "")))
		return {"verdict": "expired", "detail": str(answer.get("purchase_id", ""))}
	var reason3: String = "the door answered an unrecognized status '%s'" % status
	_settle(delivery_id, "error", reason3)
	return {"verdict": "error", "detail": reason3}

## EVERY deliver_once exit lands here first: the ledger writes, THEN the
## verdict travels, so no re-entrant beat can double-run the door.
func _settle(delivery_id: String, verdict: String, detail: String) -> void:
	_handled[delivery_id] = verdict
	_glog("info", "webhook transport: delivery %s -> %s (%s)" % [delivery_id, verdict, detail.substr(0, MAX_DETAIL)])

## Defensive header normalization: the bridge already lowercases; a
## queue voice that forgot still cannot make the armor case-sensitive.
func _normalize_headers(src) -> Dictionary:
	var out := {}
	if src is Dictionary:
		for key in src.keys():
			out[str(key).to_lower()] = str(src[key])
	return out

## Operator reconciliation readout (no secrets; ids + verdicts only).
func ledger_readout() -> Array:
	var rows := []
	for id in _handled.keys():
		rows.append({"delivery_id": str(id), "verdict": str(_handled[id])})
	return rows
