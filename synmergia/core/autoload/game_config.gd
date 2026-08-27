## GameConfig - Centralized game constants and configuration
## 
## This autoload centralizes all game-wide constants for easy balancing
## and documentation. All values can be tweaked here without hunting
## through multiple files.
##
## Usage:
##   var max_size = GameConfig.Party.MAX_SIZE
##   var msg_limit = GameConfig.Chat.MAX_MESSAGE_LENGTH
class_name GameConfig
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
	## Default respawn timer in seconds
	const DEFAULT_RESPAWN_TIME: float = 30.0
	
	## Minimum respawn time
	const MIN_RESPAWN_TIME: float = 5.0
	
	## Maximum respawn time
	const MAX_RESPAWN_TIME: float = 300.0
	
	## Revive cast time in seconds
	const REVIVE_CAST_TIME: float = 3.0
	
	## Revive range in units
	const REVIVE_RANGE: float = 10.0
	
	## Revive cooldown per healer (seconds)
	const REVIVE_COOLDOWN: float = 30.0
	
	## Karma reward for friendly revive
	const REVIVE_KARMA_REWARD: int = 10

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
class Faction:
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
	
	## Latency compensation interpolation delay
	const INTERPOLATION_DELAY: float = 0.1

## ============================================================================
## EVENT BUS CONFIGURATION
## Event system settings
## ============================================================================
class EventBus:
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

	## Anti-exploit thresholds
	const MAX_SPEED_HACK_MULTIPLIER: float = 2.5  # Max speed allowed (vs normal max)
	const MAX_ITEMS_PER_MINUTE: int = 100        # Suspicious item creation rate
	const MAX_INPUT_VALUE: float = 10000.0        # Max input value before anomaly

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
	Logger.info("GameConfig: Configuration loaded")
	_log_summary()

## Log configuration summary on startup
func _log_summary() -> void:
	Logger.debug("GameConfig: Party size=%d, Guild max=%d, Trade slots=%d" % [
		Party.MAX_SIZE, Guild.MAX_SIZE, Trade.MAX_SLOTS
	])
