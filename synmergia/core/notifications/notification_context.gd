## notification_context.gd — single dispatch payload for the toast pipeline.
##
## Every game service that wants to surface something to the player (or to
## admins) constructs a NotificationContext and hands it to
## NotificationService.send_event(ctx). The context carries enough structure
## for the dispatcher to: route to the right scope, dedupe, and pick a
## severity tier.
##
## Fields:
##   player_id      Who the notification is FOR. Empty string means
##                  "scope determines recipients" (zone, server-wide, etc).
##   kind           One of NotifKind. The dispatch + dedupe key.
##   message        Human-readable text shown in the toast panel / log.
##   source_service Who emitted it. Used for the source chip in the toast UI
##                  and for admin audit trails. e.g. "AutoResponseService".
##   data           Free-form metadata. Pass structured info (item_id, rep_delta,
##                  exploit_type) so dashboards can react without parsing
##                  the message string.
##   dedupe_key     Optional grouping key. Two contexts with the same
##                  (kind, dedupe_key) inside the dedupe window collapse to
##                  one toast. If empty, no dedupe is applied.
##
## NotifKind is in a separate file to avoid a load-order cycle between
## the context and any future kind-specific helpers.
extends RefCounted

const NotifKind = preload("res://core/notifications/notification_kind.gd").Kind

var player_id: String = ""
var kind: int = NotifKind.CUSTOM
var message: String = ""
var source_service: String = ""
var data: Dictionary = {}
var dedupe_key: String = ""


## Convenience constructor for the common case: a single player.
static func for_player(
	p_player_id: String,
	p_kind: int,
	p_message: String,
	p_source_service: String,
	p_data: Dictionary = {},
	p_dedupe_key: String = ""
) -> RefCounted:
	var ctx = load("res://core/notifications/notification_context.gd").new()
	ctx.player_id = p_player_id
	ctx.kind = p_kind
	ctx.message = p_message
	ctx.source_service = p_source_service
	ctx.data = p_data
	ctx.dedupe_key = p_dedupe_key
	return ctx


## Convenience constructor for a broadcast (no single player).
static func broadcast(
	p_kind: int,
	p_message: String,
	p_source_service: String,
	p_data: Dictionary = {},
	p_dedupe_key: String = ""
) -> RefCounted:
	return for_player("", p_kind, p_message, p_source_service, p_data, p_dedupe_key)


## True when two contexts should be considered the same toast for
## dedupe purposes. Same kind + same dedupe_key + same target player
## (or both empty, meaning broadcast).
func is_duplicate_of(other) -> bool:
	if other == null:
		return false
	if kind != other.kind:
		return false
	if dedupe_key == "" or other.dedupe_key == "":
		return false
	if dedupe_key != other.dedupe_key:
		return false
	return player_id == other.player_id
