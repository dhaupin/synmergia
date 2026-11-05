## ShardBus - the swappable cross-shard transport seam (the "plugins" law).
##
## Phase 1 of labs/prd-shard-mesh.md: the coordinator's cross-shard
## events need a REAL transport so separate shard processes can exchange
## them. A bus is one transport behind a small contract, so the transport
## (in-process today, Redis mailboxes later, a dedicated broker whenever)
## can be swapped without touching the coordinator or any gameplay code:
##
##   CoordinatorService.bus_registry().register(MyBus.new(), true)
##
## Nothing in the coordinator path names a concrete transport.
##
## THE MAILBOX PROTOCOL (the default template; subclasses supply a store):
##   * each bus instance has a SELF ID (its shard id).
##   * subscribe(topic) records the self id in the topic's subscriber set.
##   * publish(topic, message) drops a JSON copy into the per-(subscriber,
##     topic) inbox list of every OTHER subscriber -- a publisher never
##     receives its own fan-out (the no-echo law).
##   * poll(topic) drains the self inbox for that topic, in order.
##
## Per-topic inboxes mean one shard can subscribe to several topics
## without stealing another topic's mail. The store is the swappable part
## (memory = process-local; redis = cross-process); a transport that is
## not store-backed overrides the public methods instead of `_store()`.
extends RefCounted
class_name ShardBus

const SUBS_PREFIX := "shardbus:subs:"
const INBOX_PREFIX := "shardbus:inbox:"
## Upper bound on messages drained from one inbox in a single poll, so a
## runaway producer cannot starve the caller's frame.
const MAX_DRAIN: int = 512

var _self_id: String = ""

func get_id() -> String:
	return "base"

func get_display_name() -> String:
	return "Base Bus"

## Open/connect the transport. 0 = ok, non-zero = failed (the caller
## falls back to the default bus).
func open(_config: Dictionary) -> int:
	return 0

func close() -> void:
	pass

func healthy() -> bool:
	return _store() != null

## The backing CacheStore. Null = unwired, so every leg refuses.
func _store():
	return null

func set_self_id(id: String) -> void:
	_self_id = id

func get_self_id() -> String:
	return _self_id

func _subs_key(topic: String) -> String:
	return SUBS_PREFIX + topic

func _inbox_key(topic: String) -> String:
	return INBOX_PREFIX + _self_id + ":" + topic

func _peer_inbox_key(subscriber_id: String, topic: String) -> String:
	return INBOX_PREFIX + subscriber_id + ":" + topic

func subscribe(topic: String) -> void:
	var s = _store()
	if s == null or _self_id.is_empty():
		return
	s.sadd(_subs_key(topic), _self_id)

func unsubscribe(topic: String) -> void:
	var s = _store()
	if s == null or _self_id.is_empty():
		return
	s.srem(_subs_key(topic), _self_id)

func subscribers(topic: String) -> Array:
	var s = _store()
	if s == null:
		return []
	return s.smembers(_subs_key(topic))

## Fan a message out to every subscriber of the topic except the
## publisher. Returns how many inboxes accepted a copy.
func publish(topic: String, message: Variant) -> int:
	var s = _store()
	if s == null:
		return 0
	var envelope := JSON.stringify({"topic": topic, "message": message})
	var delivered := 0
	for sid in s.smembers(_subs_key(topic)):
		var peer := str(sid)
		if peer.is_empty() or peer == _self_id:
			continue
		s.rpush(_peer_inbox_key(peer, topic), envelope)
		delivered += 1
	return delivered

## Drain the self inbox for the topic, in delivery order.
func poll(topic: String) -> Array:
	var s = _store()
	if s == null or _self_id.is_empty():
		return []
	var out: Array = []
	var inbox := _inbox_key(topic)
	for _i in range(MAX_DRAIN):
		var raw = s.lpop(inbox)
		if raw == null:
			break
		var env = JSON.parse_string(str(raw))
		if env is Dictionary and env.has("message"):
			out.append(env.get("message"))
	return out
