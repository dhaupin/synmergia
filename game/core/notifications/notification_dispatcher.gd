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
const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind

const DEFAULT_WINDOW_MS: int = 5000

# Per-kind dedupe window overrides. Kinds that the user must always see
# (bans, admin alerts, circuit transitions, etc.) are mapped to 0, which
# disables dedupe entirely. The constructor's default window applies to
# any kind not listed here.
#
# Why a static const and not a constructor arg? Kind-level policy is
# part of the frame's contract -- callers shouldn't have to remember
# to set it on every dispatcher instance. The single per-instance
# window is for tests and admin overrides.
const KIND_WINDOW_OVERRIDES: Dictionary = {
	NotifKind.SECURITY_BLOCKED: 0,    # ban/unban must always show
	NotifKind.ADMIN_ALERT: 0,         # admins never want a dropped alert
	NotifKind.AUTO_ACTION: 0,         # auto-mute/ban/kick must always show
	NotifKind.CIRCUIT_OPEN: 0,        # rare; always show
	NotifKind.QOS_RECOVERED: 0,       # good news; never collapse
	NotifKind.QOS_DEGRADED: 0,        # bad news; never collapse
	NotifKind.ITEM_FULL: 0,           # inventory is full, the player needs to know
	NotifKind.PLAYER_WARNED: 2000,    # warnings are spammy; 2s is enough
	NotifKind.RATE_LIMITED: 2000,     # QoS fires fast; 2s window
	NotifKind.THROTTLED: 2000,        # bulkhead saturation; 2s window
}

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
	# Per-kind override takes precedence over the instance default.
	# A 0 here disables dedupe for this kind entirely (bans, admin
	# alerts, etc.). If the kind isn't in the table, fall through to
	# the per-instance window.
	var window_ms: int = _window_ms
	if KIND_WINDOW_OVERRIDES.has(ctx.kind):
		window_ms = int(KIND_WINDOW_OVERRIDES[ctx.kind])
	var key := _key_for(ctx)
	var now := Time.get_ticks_msec()
	if window_ms <= 0:
		# Dedupe disabled for this kind; deliver and still record
		# the timestamp so a future kind-level audit can see the
		# flow rate.
		_seen[key] = now
		return true
	if _seen.has(key):
		var last: int = _seen[key]
		if now - last < window_ms:
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
