## GameConfig - Centralized game constants and configuration

##

## This autoload centralizes all game-wide constants for easy balancing

## and documentation. All values can be tweaked here without hunting

## through multiple files.

##

## Usage:

##   var max_size = GameConfig.Party.MAX_SIZE

##   var msg_limit = GameConfig.Chat.MAX_MESSAGE_LENGTH

extends Node

## ============================================================================

## NETWORK CONFIGURATION

## Network-related settings for server/client communication

## ============================================================================

class Network:

	## Default port for game server connections

	const DEFAULT_PORT: int = 9876



	## Maximum players allowed per server instance

	const MAX_PLAYERS: int = 100



	## Maximum concurrent connections (hard limit)

	const MAX_CONNECTIONS: int = 150



	## Connection timeout in seconds

	const CONNECTION_TIMEOUT: float = 30.0



	## Heartbeat interval in seconds (for detecting disconnects)

	const HEARTBEAT_INTERVAL: float = 5.0



	## Max packets per second per client

	const MAX_PACKETS_PER_SECOND: int = 60

## ============================================================================

## PARTY CONFIGURATION

## Party/raid group settings

## ============================================================================

class Party:

	## Maximum players in a standard party (6 for dungeons, raids can expand)

	const MAX_SIZE: int = 6



	## Maximum roster size for raid groups

	const MAX_ROSTER_SIZE: int = 30



	## Invite expiration time in seconds

	const INVITE_TIMEOUT_SECONDS: float = 60.0



	## XP sharing bonus per additional party member (0.1 = 10%)

	const XP_BONUS_PER_MEMBER: float = 0.1



	## Minimum level difference for party XP sharing

	const XP_LEVEL_DIFF_THRESHOLD: int = 10



	## Maximum XP penalty for level difference

	const XP_PENALTY_MAX: float = 0.5

## ============================================================================

## GUILD CONFIGURATION

## Guild/organization settings

## ============================================================================

class Guild:

	## Maximum guild name length in characters

	const MAX_NAME_LENGTH: int = 24



	## Minimum guild name length

	const MIN_NAME_LENGTH: int = 3



	## Maximum guild tag length (3-5 chars typical)

	const MAX_TAG_LENGTH: int = 5



	## Maximum number of members in a guild

	const MAX_SIZE: int = 100



	## Maximum number of guilds in an alliance

	const MAX_ALLIANCE_SIZE: int = 5



	## Days before application expires

	const APPLICATION_EXPIRY_DAYS: int = 7



	## Cooldown between leaving and rejoining (hours)

	const REJOIN_COOLDOWN_HOURS: int = 24

## ============================================================================

## CHAT CONFIGURATION

## Chat system limits and settings

## ============================================================================

class Chat:

	## Maximum message length in characters

	const MAX_MESSAGE_LENGTH: int = 500



	## Maximum history messages stored per channel

	const MAX_HISTORY_PER_CHANNEL: int = 100



	## Maximum whispers per minute per player (spam prevention)

	const MAX_WHISPERS_PER_MINUTE: int = 20



	## Chat command prefix character

	const COMMAND_PREFIX: String = "/"



	## Maximum length for custom channel names

	const MAX_CHANNEL_NAME_LENGTH: int = 32



	## Cooldown between same messages (seconds) to prevent spam

	const MESSAGE_COOLDOWN: float = 2.0



	## Profanity filter settings

	## Note: Word list should be configured via external file or environment variable

	## Set PROFANITY_WORDS_FILE env var to path of word list (one word per line)

	## Example: "res://config/profanity_words.txt"

	const PROFANITY_FILTER_ENABLED: bool = true



	## Path to profanity word list file (loaded at runtime)

	## Format: one word per line, case-insensitive matching

	const PROFANITY_WORDS_FILE: String = "user://config/profanity_words.txt"



	## Replacement character for filtered words (e.g., "*" becomes "****")

	const PROFANITY_REPLACEMENT_CHAR: String = "*"

## ============================================================================

## TRADE CONFIGURATION

## Trading system limits

## ============================================================================

class Trade:

	## Maximum item slots in a trade window

	const MAX_SLOTS: int = 10



	## Maximum gold that can be traded at once

	const MAX_GOLD: int = 999999999



	## Trade request expiration in seconds

	const REQUEST_TIMEOUT_SECONDS: float = 30.0



	## Trade completion timeout (if not confirmed)

	const COMPLETION_TIMEOUT_SECONDS: float = 300.0



	## Cooldown between trades (seconds)

	const TRADE_COOLDOWN_SECONDS: float = 5.0



	## Maximum trade history entries to keep

	const MAX_HISTORY: int = 50

## ============================================================================

## INVENTORY CONFIGURATION

## Inventory and storage limits

## ============================================================================

class Inventory:

	## Default inventory slots (can be expanded)

	const DEFAULT_SLOTS: int = 20



	## Maximum equipment slots

	const MAX_EQUIPMENT_SLOTS: int = 12



	## Maximum expandable bags

	const MAX_BAGS: int = 5



	## Size of each bag

	const BAG_SIZE: int = 20



	## Bank slots (base)

	const BANK_SLOTS: int = 98



	## Bank expansion size

	const BANK_EXPANSION_SIZE: int = 98



	## Maximum bank expansions

	const MAX_BANK_EXPANSIONS: int = 4



	## Default carry weight

	const DEFAULT_MAX_WEIGHT: float = 100.0



	## Speed penalty when encumbered (0.5 = 50% speed)

	const ENCUMBRANCE_PENALTY: float = 0.5

## ============================================================================

## FAIRNESS / ANTI-EXPLOIT CONFIGURATION

## Rate limiting and anti-cheat settings

## ============================================================================

class Fairness:

	## Maximum actions per second (movement, attacks, etc.)

	const MAX_ACTIONS_PER_SECOND: float = 10.0



	## Maximum movement speed per second (units)

	const MAX_MOVEMENT_PER_SECOND: float = 20.0



	## Maximum combat actions per second

	const MAX_COMBAT_ACTIONS_PER_SECOND: float = 5.0



	## Maximum chat messages per minute

	const MAX_CHAT_PER_MINUTE: float = 10.0



	## Suspicion threshold for flagging (0.0 - 1.0)

	const SUSPICION_THRESHOLD: float = 0.7



	## Auto-ban threshold (0.0 - 1.0)

	const AUTO_BAN_THRESHOLD: float = 0.95



	## Decay rate for suspicion per minute

	const SUSPICION_DECAY_RATE: float = 0.05



	## Trust decay per day of inactivity

	const TRUST_DECAY_PER_DAY: float = 0.01



	## Marathon session threshold (hours) before penalties

	const MARATHON_THRESHOLD_HOURS: float = 6.0



	## Movement prediction tolerance for bot detection

	const MOVEMENT_PREDICTION_TOLERANCE: float = 0.5

## ============================================================================

## COMBAT CONFIGURATION

## Combat system tuning

## ============================================================================

class Combat:

	## Global cooldown duration in seconds

	const GCD_DURATION: float = 1.0



	## Default out-of-combat timer in seconds

	const OUT_OF_COMBAT_TIMER: float = 10.0



	## Combat mana regen multiplier

	const COMBAT_MANA_REGEN: float = 0.5



	## Rest mana regen multiplier

	const REST_MANA_REGEN: float = 1.0



	## Combat stamina regen multiplier

	const COMBAT_STAMINA_REGEN: float = 0.3



	## Rest stamina regen multiplier

	const REST_STAMINA_REGEN: float = 1.0



	## Base hit chance (0.0 - 1.0)

	const BASE_HIT_CHANCE: float = 0.95



	## Base crit chance (0.0 - 1.0)

	const BASE_CRIT_CHANCE: float = 0.05



	## Base dodge chance (0.0 - 1.0)

	const BASE_DODGE_CHANCE: float = 0.05



	## Base parry chance (0.0 - 1.0)

	const BASE_PARRY_CHANCE: float = 0.05



	## Base block chance (0.0 - 1.0)

	const BASE_BLOCK_CHANCE: float = 0.05

## ============================================================================

## RESPAWN CONFIGURATION

## Death and respawn settings

## ============================================================================

class Respawn:

	## ============================================================================

	## BASIC RESPAN SETTINGS

	## ============================================================================



	## Default respawn timer in seconds

	const DEFAULT_RESPAWN_TIME: float = 30.0



	## Minimum respawn time

	const MIN_RESPAWN_TIME: float = 5.0



	## Maximum respawn time

	const MAX_RESPAWN_TIME: float = 300.0



	## Time before respawn UI appears (seconds) - 0 = immediate

	const RESPAWN_UI_DELAY: float = 0.0



	## Auto-respawn after UI timeout (seconds) - 0 = no auto-respawn

	const AUTO_RESPAWN_TIMEOUT: float = 0.0



	## Allow player to skip respawn UI and respawn immediately

	const ALLOW_SKIP_RESPAWN_UI: bool = true



	## ============================================================================

	## ANKH/BIND POINT SETTINGS

	## ============================================================================



	## Enable ankh binding system

	const ENABLE_ANHK_BINDING: bool = true



	## Cooldown between binding to new ankh (seconds)

	const ANKH_BIND_COOLDOWN: float = 60.0



	## Maximum ankhs a player can have bound (0 = unlimited)

	const MAX_BOUND_ANKHS: int = 5



	## Default ankh for new players (zone_id)

	const DEFAULT_SPAWN_ZONE: String = "starter_plains"



	## ============================================================================

	## REVIVE (PLAYER-INITIATED) SETTINGS

	## ============================================================================



	## Revive cast time in seconds

	const REVIVE_CAST_TIME: float = 3.0



	## Revive range in units

	const REVIVE_RANGE: float = 10.0



	## Revive cooldown per healer (seconds)

	const REVIVE_COOLDOWN: float = 30.0



	## Karma reward for friendly revive

	const REVIVE_KARMA_REWARD: int = 10



	## Cross-faction bonus karma

	const REVIVE_KARMA_CROSS_FACTION_BONUS: int = 5



	## Revive cost (% of max health lost on revive)

	const REVIVE_HEALTH_COST: float = 0.0



	## Revive cost (% of max mana lost on revive)

	const REVIVE_MANA_COST: float = 0.0



	## Can revive during combat

	const REVIVE_IN_COMBAT: bool = false



	## ============================================================================

	## SELF-REZ (ITEM/SKILL) SETTINGS

	## ============================================================================



	## Enable self-rez items (soul gems, etc.)

	const ENABLE_SELF_REZ: bool = true



	## Self-rez item ID (must exist in item database)

	const SELF_REZ_ITEM_ID: String = "soul_gem"



	## Cooldown between self-rez items (seconds)

	const SELF_REZ_COOLDOWN: float = 300.0



	## Self-rez returns % health (0.0 - 1.0)

	const SELF_REZ_HEALTH_PERCENT: float = 0.5



	## Self-rez returns % mana (0.0 - 1.0)

	const SELF_REZ_MANA_PERCENT: float = 0.5



	## Self-rez casts instantly

	const SELF_REZ_INSTANT: bool = true



	## Self-rez item is consumed on use

	const SELF_REZ_CONSUMES_ITEM: bool = true



	## ============================================================================

	## ARENA/TEAM RESPAN SETTINGS

	## ============================================================================



	## Default respawns per team in arena

	const ARENA_DEFAULT_RESPAWNS: int = 5



	## Maximum respawns per team in arena

	const ARENA_MAX_RESPAWNS: int = 10



	## Arena respawn timer (seconds)

	const ARENA_RESPAWN_TIME: float = 5.0



	## Arena invincibility duration after respawn (seconds)

	const ARENA_INVINCIBILITY_DURATION: float = 3.0



	## Respawn at nearest ally or central point

	const ARENA_SPAWN_AT_ALLIES: bool = true



	## ============================================================================

	## PVP ZONE SETTINGS

	## ============================================================================



	## Default respawns per party in PVP

	const PVP_RESPAWNS_PER_PARTY: int = 10



	## PVP respawn timer (seconds)

	const PVP_RESPAWN_TIME: float = 10.0



	## Can rez teammates in PVP

	const PVP_CAN_REVIVE_TEAMMATES: bool = true



	## Revive limit per hour in PVP (0 = unlimited)

	const PVP_REVIVE_LIMIT_PER_HOUR: int = 50



	## ============================================================================

	## CORPSE/LOOT SETTINGS

	## ============================================================================



	## Corpse duration (seconds) - 0 = permanent until looted

	const CORPSE_DURATION: float = 300.0



	## Corpse despawn if not looted within time (seconds)

	const CORPSE_DESPAWN_TIME: float = 600.0



	## Can loot own corpse

	const CAN_LOOT_OWN_CORPSE: bool = true



	## Corpse loot radius (units)

	const CORPSE_LOOT_RADIUS: float = 5.0



	## Auto-loot quest items from corpse

	const AUTO_LOOT_QUEST_ITEMS: bool = true



	## Corpse decay starts when leaving zone

	const CORPSE_DECAY_ON_ZONE: bool = true



	## ============================================================================

	## DEATH PENALTIES

	## ============================================================================



	## XP loss on death (% of current XP)

	const XP_LOSS_PERCENT: float = 0.0



	## Gold loss on death (% of carried gold)

	const GOLD_LOSS_PERCENT: float = 0.0



	## Durability loss on equipment (%)

	const DURABILITY_LOSS_PERCENT: float = 10.0



	## Karma loss on death (PVP)

	const PVP_KARMA_LOSS: int = 5



	## Death sickness duration (debuff in seconds)

	const DEATH_SICKNESS_DURATION: float = 0.0

	## Equipment repair cost multiplier after death

	const DEATH_REPAIR_COST_MULTIPLIER: float = 1.5



	## ============================================================================

	## INVINCIBILITY AFTER RESPAWN

	## ============================================================================



	## Invincibility duration after respawn (seconds)

	const RESPAWN_INVINCIBILITY_DURATION: float = 5.0



	## Invincibility applies to PvP damage

	const INVINCIBILITY_BLOCKS_PVP: bool = true



	## Invincibility blocks all damage types

	const INVINCIBILITY_BLOCKS_ALL: bool = false



	## Show invincibility indicator to player

	const SHOW_INVINCIBILITY_UI: bool = true



	## ============================================================================

	## GRIEFING PROTECTION

	## ============================================================================



	## Enable griefing protection

	const ENABLE_GRIEFING_PROTECTION: bool = true



	## Number of kills by same player before triggering protection

	const GRIEFING_KILL_THRESHOLD: int = 3



	## Time window for griefing detection (seconds)

	const GRIEFING_TIME_WINDOW: float = 60.0



	## After griefing threshold, redirect to safe zone

	const GRIEFING_SAFE_ZONE_REDIRECT: bool = true



	## Safe zone ankh ID for griefing redirect

	const GRIEFING_SAFE_ZONE_ANKH: String = "safe_zone_main"



	## Duration of griefing protection (seconds)

	const GRIEFING_PROTECTION_DURATION: float = 120.0



	## ============================================================================

	## KILL STREAK BONUSES

	## ============================================================================



	## Enable kill streak bonuses

	const ENABLE_KILL_STREAK_BONUS: bool = true



	## Kill streak thresholds (must be in order)

	const KILL_STREAK_THRESHOLDS: Array[int] = [3, 5, 10, 25, 50]



	## Bonus XP multiplier per streak level

	const KILL_STREAK_XP_MULTIPLIER: float = 0.1



	## Bonus gold per kill at streak level

	const KILL_STREAK_GOLD_BONUS: int = 10



	## Announce kill streaks server-wide

	const ANNOUNCE_KILL_STREAKS: bool = true



	## Kill streak announcement threshold

	const KILL_STREAK_ANNOUNCE_THRESHOLD: int = 5



	## ============================================================================

	## ZONE TRANSFER WHILE DEAD

	## ============================================================================



	## Allow zone transfer while dead

	const ALLOW_ZONE_TRANSFER_WHILE_DEAD: bool = false



	## If dead, only allow transfer to safe zones

	const DEAD_ONLY_SAFE_ZONE_TRANSFER: bool = true



	## Timer before dead players can transfer zones

	const DEAD_ZONE_TRANSFER_DELAY: float = 10.0



	## ============================================================================

	## DEATH STATISTICS

	## ============================================================================



	## Track death statistics per player

	const TRACK_DEATH_STATS: bool = true



	## Reset stats after X days of inactivity

	const STATS_INACTIVITY_DAYS: int = 30



	## Maximum deaths to track in history

	const MAX_DEATH_HISTORY: int = 100





	## ============================================================================

	## CONTEXT-SPECIFIC ABUSE DETECTION (REVIVES PER HOUR)

	## ============================================================================



	const ABUSE_THRESHOLD_OPEN_WORLD: int = 30

	const ABUSE_THRESHOLD_DUNGEON: int = 20

	const ABUSE_THRESHOLD_RAID: int = 15

	const ABUSE_THRESHOLD_PVP_ZONE: int = 25

	const ABUSE_THRESHOLD_ARENA: int = 100

	const ABUSE_THRESHOLD_BATTLEGROUND: int = 50

	const ABUSE_THRESHOLD_CONTESTED: int = 10



	## Abuse detection window (hours)

	const ABUSE_DETECTION_WINDOW: float = 1.0



	## Karma penalty when flagged for abuse

	const ABUSE_KARMA_PENALTY: int = 5



	## Healer cooldown when flagged (minutes)

	const ABUSE_COOLDOWN_MINUTES: float = 5.0

## ============================================================================

## SPAWN CONFIGURATION

## Enemy spawn system settings

## ============================================================================

class Spawn:

	## Maximum spawn points per zone

	const MAX_SPAWN_POINTS_PER_ZONE: int = 50



	## Minimum distance from player for spawn

	const MIN_SPAWN_DISTANCE: float = 50.0



	## Default respawn timer in seconds

	const DEFAULT_RESPAWN_TIME: float = 60.0



	## Maximum enemies per spawn point

	const MAX_ENEMIES_PER_POINT: int = 5



	## Spawn cap per zone

	const ZONE_SPAWN_CAP: int = 100

## ============================================================================

## FACTION CONFIGURATION

## Faction reputation settings

## ============================================================================

class FactionConfig:

	## Maximum reputation level

	const MAX_REPUTATION: int = 100



	## Minimum reputation level

	const MIN_REPUTATION: int = -100



	## Reputation change for killing enemy

	const KILL_REPUTATION_CHANGE: int = 1



	## War declaration cooldown in hours

	const WAR_COOLDOWN_HOURS: int = 24



	## Maximum active wars per faction

	const MAX_ACTIVE_WARS: int = 3

## ============================================================================

## ZONE CONFIGURATION

## World zone settings

## ============================================================================

class Zone:

	## Maximum zones to load simultaneously

	const MAX_ACTIVE_ZONES: int = 20



	## Seamless transition distance in units

	const SEAMLESS_TRANSITION_DISTANCE: float = 100.0



	## Default zone boundary padding

	const BOUNDARY_PADDING: float = 50.0



	## Maximum seamless neighbors per zone

	const MAX_NEIGHBORS: int = 8

## ============================================================================

## LOOT CONFIGURATION

## Loot and drop system settings

## ============================================================================

class Loot:

	## Loot expiration time in seconds

	const LOOT_EXPIRY_SECONDS: float = 120.0



	## Need/Greed roll timeout in seconds

	const ROLL_TIMEOUT_SECONDS: float = 30.0



	## Maximum loot history entries

	const MAX_LOOT_HISTORY: int = 100



	## Auto-loot range in units

	const AUTO_LOOT_RANGE: float = 10.0

## ============================================================================

## QUALITY OF SERVICE CONFIGURATION

## Network quality settings

## ============================================================================

class QoS:

	## Latency thresholds in ms

	class Latency:

		const EXCELLENT: int = 50

		const GOOD: int = 100

		const FAIR: int = 150

		const POOR: int = 250

		const BAD: int = 500



	## Maximum packet loss percentage

	const MAX_PACKET_LOSS: float = 5.0



	## Maximum jitter in ms

	const MAX_JITTER: int = 50

	const MAX_ACTIONS_PER_SECOND: float = 100.0



	## Latency compensation interpolation delay

## ============================================================================

## RATE LIMIT CONFIGURATION

	## Rate limiting thresholds per action type

	## ============================================================================

	class RateLimits:

	## Movement rate limit (per second)

		const MAX_MOVEMENT_PER_SECOND: float = 20.0

	## Combat action rate limit (per second)

		const MAX_COMBAT_PER_SECOND: float = 5.0

	## Chat message rate limit (per minute)

		const MAX_CHAT_PER_MINUTE: float = 60.0

	## Whisper message rate limit (per minute)

		const MAX_WHISPER_PER_MINUTE: float = 20.0

	## Trade request rate limit (per minute)

		const MAX_TRADE_PER_MINUTE: float = 6.0

	## Party action rate limit (per minute)

		const MAX_PARTY_PER_MINUTE: float = 6.0

	## Guild action rate limit (per minute)

		const MAX_GUILD_PER_MINUTE: float = 6.0

	## Item action rate limit (per minute)

		const MAX_ITEM_ACTIONS_PER_MINUTE: float = 30.0

	## General action rate limit (per second)

		const MAX_GENERAL_PER_SECOND: float = 10.0

	## ============================================================================

	## THROTTLE CONFIGURATION

	## Global action throttling

	## ============================================================================

	class Throttle:

	## Maximum chat messages per second globally

		const MAX_GLOBAL_CHAT_PER_SECOND: float = 100.0

	## Maximum combat actions per second globally

		const MAX_GLOBAL_COMBAT_PER_SECOND: float = 50.0

	## ============================================================================

	## Throttle queue settings

	const MAX_QUEUED_ACTIONS: int = 50

	const QUEUE_TIMEOUT_SEC: float = 60.0

	## BULKHEAD CONFIGURATION

	## Concurrency limits

	## ============================================================================

	class Bulkhead:

	## Maximum concurrent global actions

		const MAX_CONCURRENT_GLOBAL: int = 1000

	## Maximum concurrent actions per service

		const MAX_CONCURRENT_PER_SERVICE: int = 100

	## Maximum concurrent actions per player

		const MAX_CONCURRENT_PER_PLAYER: int = 10

	## ============================================================================

	## CIRCUIT BREAKER CONFIGURATION

	## Circuit breaker thresholds

	## ============================================================================

	class CircuitBreakerCfg:

	## Failure threshold to open circuit

		const FAILURE_THRESHOLD: int = 5

	## Success threshold to close circuit

		const SUCCESS_THRESHOLD: int = 2

	## Timeout in seconds to try half-open state

		const RECOVERY_TIMEOUT_SEC: float = 30.0

	## Maximum queued actions per player

		const MAX_QUEUED_ACTIONS: int = 50

	## Queue timeout in seconds

		const QUEUE_TIMEOUT_SEC: float = 60.0

	## ============================================================================

	## DEBOUNCE CONFIGURATION

	## Debounce timing settings

	## ============================================================================

	class Debounce:

		## Default debounce delay in milliseconds

		const DEFAULT_DELAY_MS: int = 100

		## Maximum debounce delay in milliseconds

		const MAX_DELAY_MS: int = 5000

	## ============================================================================

	## RECURSION CONFIGURATION

	## Recursion depth limits

	## ============================================================================

	class Recursion:

		## Default max recursion depth

		const DEFAULT_MAX_DEPTH: int = 100

		## Entity tree max depth

		const ENTITY_TREE_MAX_DEPTH: int = 50

		## Zone neighbor traversal max depth

		const ZONE_NEIGHBOR_MAX_DEPTH: int = 20

		## Aura chain max depth

		const AURA_CHAIN_MAX_DEPTH: int = 10

## EVENT BUS CONFIGURATION

## Event system settings

## ============================================================================

class EventBusConfig:

	## Maximum events to keep in history

	const MAX_HISTORY: int = 1000



	## Enable event logging (can impact performance)

	const ENABLE_LOGGING: bool = true

## ============================================================================

## SECURITY CONFIGURATION

## Security thresholds and limits

## ============================================================================

class Security:

	## Minimum player name length

	const MIN_NAME_LENGTH: int = 3

	## Maximum player name length

	const MAX_NAME_LENGTH: int = 20

	## Reserved names (blocked)

	const RESERVED_NAMES: Array = [

		"admin", "moderator", "system", "server", "null", "undefined"

	]

	## Maximum message length

	const MAX_MESSAGE_LENGTH: int = 500

	## Permission levels

	const PLAYER_LEVEL: int = 0

	const VIP_LEVEL: int = 10

	const MOD_LEVEL: int = 50

	const ADMIN_LEVEL: int = 100



	## ============================================================================

	## SECURITY/QOS ALERT NOTIFICATIONS

	## Toggle whether players receive in-game messages about security and rate limit events

	## Set to false for "silent" servers that only log to admin channels

	## ============================================================================



	## Master toggle: Enable all security/QoS player notifications

	const ENABLE_SECURITY_ALERTS: bool = true



	## Alert when player hits a rate limit (e.g., "Slow down! Wait 0.5s")

	const ALERT_ON_RATE_LIMIT: bool = true



	## Alert when player is restricted/muted/banned (e.g., "You have been muted")

	const ALERT_ON_RESTRICTION: bool = true



	## Alert when restriction expires (e.g., "Your mute has been lifted")

	const ALERT_ON_UNRESTRICTION: bool = true



	## Alert on exploit detection (default off - don't tip off potential hackers)

	const ALERT_ON_EXPLOIT_DETECTED: bool = false

	## Anti-exploit thresholds

	const MAX_SPEED_HACK_MULTIPLIER: float = 2.5  # Max speed allowed (vs normal max)

	const MAX_ITEMS_PER_MINUTE: int = 100        # Suspicious item creation rate

	const MAX_INPUT_VALUE: float = 10000.0        # Max input value before anomaly

	## Teleport detection: max distance in units per second

	const MAX_TELEPORT_DISTANCE: float = 500.0

	## Rapid action threshold (actions per second)

	const RAPID_ACTION_THRESHOLD: float = 10.0

	## Spam detection: repeated characters threshold

	const SPAM_REPEATED_CHARS: int = 5

	## Spam detection: unique character ratio minimum

	const SPAM_UNIQUE_RATIO: float = 0.3

	## Allowed characters in names (regex-style)

	const NAME_ALLOWED_CHARS: String = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 _-.\'"

	## ============================================================================

	## FIREWALL SETTINGS

	## ============================================================================

	## Default IP block duration (seconds)

	const FIREWALL_BLOCK_DURATION: int = 300  # 5 minutes

	## Max failed attempts before temporary block

	const FIREWALL_MAX_ATTEMPTS: int = 5

	## Max connections per IP

	const FIREWALL_MAX_CONNECTIONS_PER_IP: int = 3

	## Cleanup interval for expired blocks (seconds)

	const FIREWALL_CLEANUP_INTERVAL: int = 300

	## ============================================================================

	## SEED CHAIN / HMAC CONFIGURATION

	## ============================================================================

	## Server HMAC key for signing SeedReceipts (hex-encoded 32-byte key)
	## In production, load from secure config file (srv/config/server.key)
	## For dev, this is a deterministic key derived from a constant.
	const SERVER_HMAC_KEY: String = ""

## ============================================================================

## AUTO-RESPONSE CONFIGURATION

## Automated actions when exploits are detected

## ============================================================================

class AutoResponse:

	## Enable/disable auto-response

	const ENABLED: bool = false



	## Auto-mute duration when spam detected (seconds)

	const SPAM_MUTE_DURATION: int = 300  # 5 minutes



	## Auto-kick after N exploit detections

	const AUTO_KICK_THRESHOLD: int = 3



	## Auto-ban for speed hack (requires multiple confirmations)

	const AUTO_BAN_SPEEDHACK: bool = false

	const SPEEDHACK_CONFIRMATIONS_REQUIRED: int = 3



	## Auto-ban for teleport hack

	const AUTO_BAN_TELEPORTHACK: bool = false

	const TELEPORTHACK_CONFIRMATIONS_REQUIRED: int = 2



	## Auto-ban for item duplication

	const AUTO_BAN_ITEM_DUPLICATION: bool = false

	const ITEM_DUP_CONFIRMATIONS_REQUIRED: int = 2



	## Notify admins via in-game message

	const NOTIFY_ADMINS: bool = true



	## Notify via Discord webhook (if configured)

	const NOTIFY_DISCORD: bool = false

## ============================================================================

## WEBHOOK CONFIGURATION

## External notification settings

## ============================================================================

class Webhooks:

	## Enable webhook notifications

	const ENABLED: bool = true



	## Discord webhook URL (for notifications)

	const DISCORD_WEBHOOK_URL: String = ""



	## Notification toggles

	const NOTIFY_ADMIN_ACTIONS: bool = true

	const NOTIFY_REPORTS: bool = true

	const NOTIFY_URGENT: bool = true

	const NOTIFY_EXPLOITS: bool = true

	const NOTIFY_SERVER_STATUS: bool = false



	## Rate limiting

	const MAX_MESSAGES_PER_MINUTE: int = 30

## ============================================================================

## DEBUG CONFIGURATION

## Development and debugging settings

## ============================================================================

class Debug:

	## Enable debug logging

	const ENABLE_DEBUG_LOGGING: bool = true



	## Enable verbose entity logging

	const VERBOSE_ENTITY_LOGGING: bool = false



	## Enable performance metrics

	const ENABLE_METRICS: bool = false



	## Simulated latency for testing (ms)

	const SIMULATED_LATENCY: int = 0



	## Enable cheat commands

	const ALLOW_CHEATS: bool = false

func _ready() -> void:

	pass  # GameLog.info

	_log_summary()

## Runtime-overridable security settings (for admin panel)
static var _security_overrides: Dictionary = {}

## Set a security config value at runtime
static func set_security_value(key: String, value) -> bool:
	if not _is_valid_security_key(key):
		return false
	_security_overrides[key] = value
	return true

## Get a security config value (override or default)
static func get_security_value(key: String, default = null):
	if _security_overrides.has(key):
		return _security_overrides[key]
	return default

## Check if a key is valid for security overrides
static func _is_valid_security_key(key: String) -> bool:
	var valid_keys := [
		"MIN_NAME_LENGTH", "MAX_NAME_LENGTH", "MAX_MESSAGE_LENGTH",
		"PLAYER_LEVEL", "VIP_LEVEL", "MOD_LEVEL", "ADMIN_LEVEL",
		"ENABLE_SECURITY_ALERTS", "ALERT_ON_RATE_LIMIT", "ALERT_ON_RESTRICTION",
		"ALERT_ON_EXPLOIT_DETECTED", "ALERT_ON_UNRESTRICTION",
		"MAX_SPEED_HACK_MULTIPLIER", "MAX_ITEMS_PER_MINUTE", "MAX_INPUT_VALUE",
		"MAX_TELEPORT_DISTANCE", "RAPID_ACTION_THRESHOLD",
		"SPAM_REPEATED_CHARS", "SPAM_UNIQUE_RATIO", "NAME_ALLOWED_CHARS",
		"FIREWALL_BLOCK_DURATION", "FIREWALL_MAX_ATTEMPTS",
		"FIREWALL_MAX_CONNECTIONS_PER_IP", "FIREWALL_CLEANUP_INTERVAL"
	]
	return key in valid_keys

## Log configuration summary on startup

func _log_summary() -> void:

	pass  # GameLog.debug

## Returns the server HMAC key for SeedReceipt signing/verification.
## Returns empty string if not configured (falls back to dev key).
func get_server_hmac_key() -> String:
	return Security.SERVER_HMAC_KEY
