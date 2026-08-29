## PermissionManager - Central permission and audit system
## All admin operations MUST go through this system
extends Node

## Permission levels (must match GameConfig.Security)
enum Level {
	PLAYER = 0,
	VIP = 10,
	MOD = 50,
	ADMIN = 100,
	OWNER = 200
}

## Audit log entry
class AuditEntry:
	var timestamp: float
	var admin_id: String
	var admin_level: int
	var action: String
	var target_id: String
	var details: Dictionary
	var success: bool
	var ip_address: String
	
	func _init(p_admin_id: String, p_action: String, p_target: String = "", p_details: Dictionary = {}, p_success: bool = true, p_ip: String = ""):
		timestamp = Time.get_unix_time_from_system()
		admin_id = p_admin_id
		admin_level = get_player_level(p_admin_id)
		action = p_action
		target_id = p_target
		details = p_details
		success = p_success
		ip_address = p_ip
	
	func to_dict() -> Dictionary:
		return {
			"timestamp": timestamp,
			"admin_id": admin_id,
			"admin_level": admin_level,
			"action": action,
			"target_id": target_id,
			"details": details,
			"success": success,
			"ip_address": ip_address
		}
	
	func to_string() -> String:
		var time_str := Time.get_datetime_string_from_unix_time(timestamp)
		var status := "[color=green]SUCCESS[/color]" if success else "[color=red]DENIED[/color]"
		return "[%s] %s (Lvl %d) %s -> %s %s" % [time_str, admin_id, admin_level, action, target_id, status]

## Player permission cache: player_id -> level
var _player_levels: Dictionary = {}

## Audit log
var _audit_log: Array = []
const MAX_AUDIT_LOG_SIZE: int = 1000

## Admin command rate limiting: admin_id -> {timestamp, count}
var _admin_command_log: Dictionary = {}
const ADMIN_RATE_LIMIT: int = 30  # Max admin commands per minute
const ADMIN_RATE_WINDOW: int = 60000  # 1 minute in ms

## Last validation time cache
var _validation_cache: Dictionary = {}  # player_id -> {time, level}
const VALIDATION_CACHE_TTL: int = 5000  # 5 seconds

func _ready() -> void:
	GameLogger.info("PermissionManager: Initialized")

## ============================================================================
## CORE PERMISSION CHECKS
## ============================================================================

## Check if a player has required permission level
func has_permission(player_id: String, required_level: int) -> bool:
	if player_id == "":
		return false
	
	# Always deny empty player IDs
	if player_id.strip_edges() == "":
		_log_deny(player_id, "has_permission", "", {"reason": "empty_id"}, "")
		return false
	
	# Check cache first
	var cached := _get_cached_level(player_id)
	if cached != -1:
		return cached >= required_level
	
	# Get level from source (SecurityService or database)
	var level := _get_player_level_internal(player_id)
	
	# Cache it
	_validation_cache[player_id] = {
		"time": Time.get_ticks_msec(),
		"level": level
	}
	
	return level >= required_level

## Check if player is at least MOD level
func is_moderator(player_id: String) -> bool:
	return has_permission(player_id, Level.MOD)

## Check if player is at least ADMIN level
func is_admin(player_id: String) -> bool:
	return has_permission(player_id, Level.ADMIN)

## Check if player is OWNER level
func is_owner(player_id: String) -> bool:
	return has_permission(player_id, Level.OWNER)

## Get player's permission level
func get_player_level(player_id: String) -> int:
	if player_id == "":
		return Level.PLAYER
	
	var cached := _get_cached_level(player_id)
	if cached != -1:
		return cached
	
	return _get_player_level_internal(player_id)

## ============================================================================
## SECURED ADMIN OPERATIONS
## All admin commands MUST use these methods
## ============================================================================

## Execute a secured admin operation
func execute_secured(admin_id: String, action: String, target_id: String = "", 
		details: Dictionary = {}, ip_address: String = "") -> Dictionary:
	
	# Step 1: Validate admin session
	var validation := _validate_admin_session(admin_id, ip_address)
	if not validation.success:
		_log_deny(admin_id, action, target_id, validation, ip_address)
		return validation
	
	# Step 2: Rate limit check
	var rate_check := _check_admin_rate_limit(admin_id)
	if not rate_check.success:
		_log_deny(admin_id, action, target_id, rate_check, ip_address)
		return rate_check
	
	# Step 3: Execute the action (caller must implement actual logic)
	_log_action(admin_id, action, target_id, details, true, ip_address)
	
	return {"success": true, "message": "Action allowed"}

## Validate admin session is legitimate
func _validate_admin_session(admin_id: String, ip_address: String) -> Dictionary:
	# Check for empty/invalid admin ID
	if admin_id.strip_edges() == "":
		return {"success": false, "message": "Invalid admin session", "code": "INVALID_SESSION"}
	
	# Check permission level
	var level := get_player_level(admin_id)
	if level < Level.MOD:
		return {"success": false, "message": "Insufficient permissions", "code": "INSUFFICIENT_PERMS"}
	
	# Check if player is online (if PlayerManager exists)
	if PlayerManager and not PlayerManager.is_player_online(admin_id):
		# Admins should be online to use admin tools
		return {"success": false, "message": "Admin must be online", "code": "NOT_ONLINE"}
	
	# Check if admin is restricted themselves
	if SecurityService and SecurityService.is_restricted(admin_id, "admin"):
		return {"success": false, "message": "Admin tools suspended", "code": "ADMIN_SUSPENDED"}
	
	return {"success": true}

## Check rate limit for admin commands
func _check_admin_rate_limit(admin_id: String) -> Dictionary:
	var now := Time.get_ticks_msec()
	
	if not _admin_command_log.has(admin_id):
		_admin_command_log[admin_id] = {"count": 0, "window_start": now}
	
	var log: Dictionary = _admin_command_log[admin_id]
	
	# Reset window if expired
	if now - log["window_start"] > ADMIN_RATE_WINDOW:
		log["count"] = 0
		log["window_start"] = now
	
	# Check limit
	if log["count"] >= ADMIN_RATE_LIMIT:
		return {
			"success": false, 
			"message": "Too many admin commands. Wait %d seconds." % ((ADMIN_RATE_WINDOW - (now - log["window_start"])) / 1000),
			"code": "RATE_LIMITED"
		}
	
	# Increment counter
	log["count"] += 1
	
	return {"success": true}

## ============================================================================
## RESTRICTION OPERATIONS (Secured)
## ============================================================================

## Restrict a player (requires ADMIN level)
func restrict(admin_id: String, target_id: String, restriction_type: String, 
		duration_seconds: int, reason: String = "") -> Dictionary:
	
	var check := execute_secured(admin_id, "restrict", target_id, {
		"type": restriction_type,
		"duration": duration_seconds,
		"reason": reason
	})
	
	if not check.success:
		return check
	
	# Execute restriction
	if SecurityService:
		SecurityService.restrict_player(target_id, restriction_type, duration_seconds)
	
	# Log success
	_audit(admin_id, "RESTRICT", target_id, {
		"type": restriction_type,
		"duration": duration_seconds,
		"reason": reason
	}, true)
	
	return {"success": true, "message": "Player restricted"}

## Unrestrict a player (requires ADMIN level)
func unrestrict(admin_id: String, target_id: String, restriction_type: String = "") -> Dictionary:
	var check := execute_secured(admin_id, "unrestrict", target_id, {
		"type": restriction_type
	})
	
	if not check.success:
		return check
	
	if SecurityService:
		SecurityService.unrestrict_player(target_id, restriction_type)
	
	_audit(admin_id, "UNRESTRICT", target_id, {
		"type": restriction_type
	}, true)
	
	return {"success": true, "message": "Player unrestricted"}

## Mute a player (requires MOD level)
func mute(admin_id: String, target_id: String, duration_seconds: int = 300) -> Dictionary:
	if not has_permission(admin_id, Level.MOD):
		return {"success": false, "message": "MOD level required", "code": "INSUFFICIENT_PERMS"}
	
	if SecurityService:
		SecurityService.restrict_player(target_id, "chat", duration_seconds)
	
	_audit(admin_id, "MUTE", target_id, {"duration": duration_seconds}, true)
	
	return {"success": true, "message": "Player muted"}

## Unmute a player (requires MOD level)
func unmute(admin_id: String, target_id: String) -> Dictionary:
	if not has_permission(admin_id, Level.MOD):
		return {"success": false, "message": "MOD level required", "code": "INSUFFICIENT_PERMS"}
	
	if SecurityService:
		SecurityService.unrestrict_player(target_id, "chat")
	
	_audit(admin_id, "UNMUTE", target_id, {}, true)
	
	return {"success": true, "message": "Player unmuted"}

## Kick a player (requires MOD level)
func kick(admin_id: String, target_id: String, reason: String = "") -> Dictionary:
	if not has_permission(admin_id, Level.MOD):
		return {"success": false, "message": "MOD level required", "code": "INSUFFICIENT_PERMS"}
	
	# Cannot kick higher-level players
	if get_player_level(target_id) > get_player_level(admin_id):
		return {"success": false, "message": "Cannot kick higher-level player", "code": "HIERARCHY_VIOLATION"}
	
	_audit(admin_id, "KICK", target_id, {"reason": reason}, true)
	
	# Emit kick signal
	player_kicked.emit(target_id, reason, admin_id)
	
	return {"success": true, "message": "Player kicked"}

## Ban a player (requires ADMIN level)
func ban(admin_id: String, target_id: String, duration_seconds: int = -1, 
		reason: String = "") -> Dictionary:
	
	if not has_permission(admin_id, Level.ADMIN):
		return {"success": false, "message": "ADMIN level required", "code": "INSUFFICIENT_PERMS"}
	
	# Cannot ban higher-level players
	if get_player_level(target_id) >= get_player_level(admin_id):
		return {"success": false, "message": "Cannot ban equal or higher-level player", "code": "HIERARCHY_VIOLATION"}
	
	var actual_duration := 31536000 if duration_seconds == -1 else duration_seconds  # 1 year default
	
	if SecurityService:
		SecurityService.restrict_player(target_id, "all", actual_duration)
	
	_audit(admin_id, "BAN", target_id, {
		"duration": duration_seconds,
		"reason": reason
	}, true)
	
	# Emit ban signal
	player_banned.emit(target_id, duration_seconds, reason, admin_id)
	
	return {"success": true, "message": "Player banned"}

## ============================================================================
## PLAYER MANAGEMENT (Secured)
## ============================================================================

## Look up player info (requires MOD level to view others, any level for self)
func lookup_player(admin_id: String, target_id: String) -> Dictionary:
	# Can always lookup self, but need MOD for others
	if admin_id != target_id and not has_permission(admin_id, Level.MOD):
		return {"success": false, "message": "MOD level required", "code": "INSUFFICIENT_PERMS"}
	
	# Execute secured check
	var check := execute_secured(admin_id, "lookup", target_id)
	if not check.success:
		return check
	
	# Build player info
	var info := _get_player_info(target_id)
	
	_audit(admin_id, "LOOKUP", target_id, {}, true)
	
	return {"success": true, "info": info}

## ============================================================================
## CONFIGURATION (Secured)
## ============================================================================

## Modify security config (requires ADMIN level)
func set_config(admin_id: String, key: String, value) -> Dictionary:
	if not has_permission(admin_id, Level.ADMIN):
		return {"success": false, "message": "ADMIN level required", "code": "INSUFFICIENT_PERMS"}
	
	# Verify key exists
	if not GameConfig.Security.has(key):
		return {"success": false, "message": "Invalid config key", "code": "INVALID_KEY"}
	
	# Check for dangerous keys
	var dangerous_keys := ["ADMIN_PASSWORD", "SECRET_KEY", "ENCRYPTION_KEY", "DATABASE_URL"]
	if dangerous_keys.any(func(k): return key.to_lower().contains(k.to_lower())):
		_audit(admin_id, "CONFIG_CHANGE_DENIED", "", {"key": key}, false)
		return {"success": false, "message": "Cannot modify security-sensitive key", "code": "FORBIDDEN"}
	
	# Apply change
	GameConfig.Security.set(key, value)
	
	_audit(admin_id, "CONFIG_CHANGE", "", {"key": key, "value": value}, true)
	
	return {"success": true, "message": "Config updated"}

## ============================================================================
## AUDIT LOGGING
## ============================================================================

## Get recent audit log
func get_audit_log(limit: int = 100, admin_filter: String = "", 
		action_filter: String = "") -> Array:
	
	var results: Array = []
	
	for entry: AuditEntry in _audit_log:
		if admin_filter != "" and entry.admin_id != admin_filter:
			continue
		if action_filter != "" and entry.action != action_filter:
			continue
		results.append(entry.to_dict())
		if results.size() >= limit:
			break
	
	return results

## Get audit log as formatted string
func get_audit_log_string(limit: int = 50) -> String:
	var output := "[color=yellow]=== Recent Admin Actions ===[/color]\n\n"
	
	var count := 0
	for entry: AuditEntry in _audit_log:
		output += entry.to_string() + "\n"
		count += 1
		if count >= limit:
			break
	
	if count == 0:
		output += "[color=gray]No admin actions recorded[/color]"
	
	return output

func _audit(admin_id: String, action: String, target_id: String = "", 
		details: Dictionary = {}, success: bool = true) -> void:
	var entry := AuditEntry.new(admin_id, action, target_id, details, success)
	_audit_log.push_front(entry)
	
	# Trim log
	while _audit_log.size() > MAX_AUDIT_LOG_SIZE:
		_audit_log.pop_back()
	
	# Log to file/console
	var entry_str := entry.to_string()
	GameLogger.info("AUDIT: " + entry_str)
	
	# Emit signal for external logging (Discord, etc.)
	admin_action.emit(entry)

func _log_deny(admin_id: String, action: String, target_id: String, 
		details: Dictionary, ip_address: String) -> void:
	var entry := AuditEntry.new(admin_id, action, target_id, details, false, ip_address)
	_audit_log.push_front(entry)
	
	GameLogger.warn("AUDIT_DENIED: " + entry.to_string())

## ============================================================================
## INTERNAL HELPERS
## ============================================================================

func _get_player_level_internal(player_id: String) -> int:
	# Check SecurityService first
	if SecurityService:
		return SecurityService.get_player_permission_level(player_id)
	
	# Fallback to config defaults
	return GameConfig.Security.PLAYER_LEVEL

func _get_cached_level(player_id: String) -> int:
	if _validation_cache.has(player_id):
		var cached: Dictionary = _validation_cache[player_id]
		if Time.get_ticks_msec() - cached["time"] < VALIDATION_CACHE_TTL:
			return cached["level"]
	return -1

func _get_player_info(player_id: String) -> Dictionary:
	var info := {
		"id": player_id,
		"level": get_player_level(player_id),
		"level_name": _get_level_name(get_player_level(player_id))
	}
	
	# Add restriction info
	if SecurityService:
		info["restricted_chat"] = SecurityService.is_restricted(player_id, "chat")
		info["restricted_trade"] = SecurityService.is_restricted(player_id, "trade")
		info["active_restrictions"] = SecurityService.get_active_restrictions(player_id)
	
	# Add online status
	if PlayerManager:
		info["online"] = PlayerManager.is_player_online(player_id)
	
	return info

func _get_level_name(level: int) -> String:
	match level:
		Level.PLAYER: return "Player"
		Level.VIP: return "VIP"
		Level.MOD: return "Moderator"
		Level.ADMIN: return "Admin"
		Level.OWNER: return "Owner"
		_: return "Unknown"

## ============================================================================
## MAINTENANCE
## ============================================================================

func _process(delta: float) -> void:
	# Cleanup old validation cache entries
	var now := Time.get_ticks_msec()
	var expired: Array = []
	
	for player_id in _validation_cache.keys():
		if now - _validation_cache[player_id]["time"] > VALIDATION_CACHE_TTL * 10:
			expired.append(player_id)
	
	for player_id in expired:
		_validation_cache.erase(player_id)
	
	# Cleanup rate limit logs for inactive admins
	var inactive_admins: Array = []
	for admin_id in _admin_command_log.keys():
		if now - _admin_command_log[admin_id]["window_start"] > ADMIN_RATE_WINDOW * 5:
			inactive_admins.append(admin_id)
	
	for admin_id in inactive_admins:
		_admin_command_log.erase(admin_id)

## ============================================================================
## SIGNALS
## ============================================================================

signal admin_action(entry: AuditEntry)
signal player_kicked(player_id: String, reason: String, admin_id: String)
signal player_banned(player_id: String, duration: int, reason: String, admin_id: String)
