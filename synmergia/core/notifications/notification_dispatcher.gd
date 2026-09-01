## notification_dispatcher.gd — TTL-based dedupe + routing for contexts.
##
## Sits between the game services and NotificationService. Receives a
## NotificationContext, decides whether to drop it (dedupe) or forward
## it, and tracks the last-seen timestamp per (kind, dedupe_key) pair.
##
## Why a separate class? The dedupe policy is something tests want to
## exercise without spinning up the full autoload chain. NotificationService
## owns one of these and delegates to it; tests can construct one directly.
##
## Window semantics:
##   - Two contexts with the same kind and dedupe_key arriving within
##     `window_ms` of each other collapse to one notification.
##   - Different kinds, or different dedupe_keys, never collapse.
##   - Broadcasts (player_id == "") only dedupe against other broadcasts.
extends RefCounted

const NotificationContext = preload("res://core/notifications/notification_context.gd")

const DEFAULT_WINDOW_MS: int = 5000

var _window_ms: int = DEFAULT_WINDOW_MS
# key: "%d:%s:%s" % [kind, player_id, dedupe_key]  →  last-seen tick (ms)
var _seen: Dictionary = {}


func _init(p_window_ms: int = DEFAULT_WINDOW_MS) -> void:
	_window_ms = max(0, p_window_ms)


## Returns true if the context passes the dedupe gate (i.e. it should be
## delivered). Records the timestamp on the way through. Safe to call
## concurrently only if the caller serializes (NotificationService does).
func should_deliver(ctx) -> bool:
	if ctx == null:
		return false
	# No dedupe_key means no dedupe; always deliver.
	if ctx.dedupe_key == "":
		return true
	var key := _key_for(ctx)
	var now := Time.get_ticks_msec()
	if _seen.has(key):
		var last: int = _seen[key]
		if now - last < _window_ms:
			return false
	_seen[key] = now
	return true


## Forget all dedupe state. Useful for tests and for a hard "clear toasts"
## admin command.
func reset() -> void:
	_seen.clear()


## How many distinct dedupe keys are currently tracked. Exposed for tests
## and for a future "show dedupe stats" debug overlay.
func tracked_count() -> int:
	return _seen.size()


## Override the dedupe window at runtime. Pass 0 to disable dedupe entirely.
func set_window_ms(p_ms: int) -> void:
	_window_ms = max(0, p_ms)


func _key_for(ctx) -> String:
	return "%d:%s:%s" % [ctx.kind, ctx.player_id, ctx.dedupe_key]
