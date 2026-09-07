## notification_kind.gd — coarse-grained "why" for a notification.
##
## Lives next to the rest of the typed-event primitives under
## core/notifications/. Pairs with notification_context.gd.
##
## The NotifKind is the dispatch key for the toast pipeline and the
## dedupe layer: a context with the same dedupe_key and same kind
## within the dedupe window collapses to a single toast. Different
## kinds never collapse.
##
## Use a fine-grained value (RESPAWNED, ITEM_FULL) over a broad one
## (SYSTEM) so dashboards can subscribe to one kind without parsing
## free-form messages.
extends RefCounted

enum NotifKind {
	# Lifecycle
	RESPAWNED,
	RESPAWN_FAILED,
	RESPAWN_PENALTY_APPLIED,

	# Inventory
	ITEM_ADDED,
	ITEM_REMOVED,
	ITEM_FULL,
	ITEM_REPAIRED,
	ITEM_SOULBOUND_REJECT,
	ITEM_TRADE_REJECT,
	ITEM_TRANSFERRED,
	GOLD_TRANSFERRED,

	# Skills
	SKILL_UPGRADED,
	SKILL_RESPEC,
	SKILL_SIGNATURE_CHANGED,

	# Faction
	FACTION_CHANGED,
	FACTION_REP_CHANGED,
	FACTION_PVP_MODE_CHANGED,

	# Quest
	QUEST_ACCEPTED,
	QUEST_UPDATED,
	QUEST_COMPLETED,
	QUEST_FAILED,
	QUEST_TURNED_IN,
	QUEST_REWARDED,

	# Security / moderation
	SECURITY_WARNING,
	SECURITY_BLOCKED,
	ADMIN_ALERT,
	PLAYER_WARNED,
	AUTO_ACTION,

	# QoS / network
	QOS_DEGRADED,
	QOS_RECOVERED,
	THROTTLED,
	RATE_LIMITED,
	CIRCUIT_OPEN,

	# Free-form escape hatch
	ACHIEVEMENT_UNLOCKED,
	ACHIEVEMENT_PROGRESSED,
	LOOT_DROPPED,
	SAME_ACCOUNT_TRANSFER_COOLDOWN,
	TRADE_COOLDOWN,
	TRADE_CANCELLED,
	ZONE_CHANGED,
	VOTE_CREATED,
	VOTE_ENDED,
	LEVEL_UP,
	KARMA_CHANGED,
	KILL_STREAK,
	CONNECTION_QUALITY,
	CUSTOM,
}
