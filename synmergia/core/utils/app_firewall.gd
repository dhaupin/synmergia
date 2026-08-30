## AppFirewall - Application-level firewall utility
## Tracks connections, blocks suspicious IPs, and manages bans
extends RefCounted

## ============================================================================
## SIGNALS
## ============================================================================

signal ip_blocked(ip: String, reason: String, duration: int)
signal ip_unblocked(ip: String)
signal connection_flagged(ip: String, flag_type: String, count: int)
signal ban_issued(player_id: String, ip: String, reason: String, duration: int)
signal ban_lifted(player_id: String)

## ============================================================================
## CONFIGURATION
## ============================================================================

## Block duration for suspicious activity (seconds)
var _block_duration: int = 300  # 5 minutes default

## Maximum failed attempts before temporary block
var _max_failed_attempts: int = 5

## Maximum connections per IP
var _max_connections_per_ip: int = 3

## Cleanup interval (seconds)
var _cleanup_interval: int = 300

## ============================================================================
## TRACKING DATA
## ============================================================================

## Blocked IPs: ip -> {blocked_until, reason}
var _blocked_ips: Dictionary = {}

## Failed login attempts: ip -> [timestamps]
var _failed_attempts: Dictionary = {}

## Connection count per IP: ip -> count
var _connection_counts: Dictionary = {}

## Player ID to IP mapping: player_id -> ip
var _player_ips: Dictionary = {}

## Permanent bans: player_id -> {reason, banned_by, timestamp}
var _permanent_bans: Dictionary = {}

## Temporary bans: player_id -> {expires, reason}
var _temporary_bans: Dictionary = {}

## Flagged IPs for monitoring: ip -> {flags, last_activity}
var _flagged_ips: Dictionary = {}

## ============================================================================
## LIFECYCLE
## ============================================================================

func _init(
	block_duration: int = -1,
	max_failed_attempts: int = -1,
	max_connections_per_ip: int = -1
) -> void:
	if block_duration > 0:
		_block_duration = block_duration
	if max_failed_attempts > 0:
		_max_failed_attempts = max_failed_attempts
	if max_connections_per_ip > 0:
		_max_connections_per_ip = max_connections_per_ip
	
	GameLog.debug("AppFirewall: Initialized (block=%ds, max_attempts=%d, max_conn=%d)" % [
		_block_duration, _max_failed_attempts, _max_connections_per_ip
	])

## ============================================================================
## CONNECTION MANAGEMENT
## ============================================================================

## Check if an IP is allowed to connect
func can_connect(ip: String) -> Dictionary:
	var now := Time.get_unix_time_from_system()
	
	# Check if permanently banned
	for player_id in _permanent_bans.keys():
		if _player_ips.get(player_id) == ip:
			return {
				"allowed": false,
				"reason": "Permanently banned",
				"duration": -1
			}
	
	# Check temporary bans
	for player_id in _temporary_bans.keys():
		var ban: Dictionary = _temporary_bans[player_id]
		if _player_ips.get(player_id) == ip and ban["expires"] > now:
			return {
				"allowed": false,
				"reason": ban["reason"],
				"duration": int(ban["expires"] - now)
			}
	
	# Check if IP is blocked
	if _blocked_ips.has(ip):
		var block: Dictionary = _blocked_ips[ip]
		if block["blocked_until"] > now:
			return {
				"allowed": false,
				"reason": block["reason"],
				"duration": int(block["blocked_until"] - now)
			}
		else:
			# Block expired, clean up
			_blocked_ips.erase(ip)
	
	# Check connection limit
	var conn_count: int = _connection_counts.get(ip, 0)
	if conn_count >= _max_connections_per_ip:
		_flag_ip(ip, "connection_limit", 1)
		return {
			"allowed": false,
			"reason": "Too many connections from this IP",
			"duration": _block_duration
		}
	
	return {"allowed": true}

## Register a new connection
func register_connection(player_id: String, ip: String) -> void:
	_player_ips[player_id] = ip
	_connection_counts[ip] = _connection_counts.get(ip, 0) + 1
	_clear_failed_attempts(ip)
	GameLog.debug("AppFirewall: %s connected from %s (conns: %d)" % [
		player_id, ip, _connection_counts[ip]
	])

## Unregister a connection
func unregister_connection(player_id: String) -> void:
	var ip = _player_ips.get(player_id)
	if ip:
		_connection_counts[ip] = max(0, _connection_counts.get(ip, 1) - 1)
		if _connection_counts[ip] == 0:
			_connection_counts.erase(ip)
	_player_ips.erase(player_id)

## ============================================================================
## RATE LIMITING & BLOCKING
## ============================================================================

## Record a failed attempt (login, etc.)
func record_failed_attempt(ip: String, attempt_type: String = "login") -> bool:
	var now := Time.get_unix_time_from_system()
	var window := 300.0  # 5 minute window
	
	if not _failed_attempts.has(ip):
		_failed_attempts[ip] = []
	
	# Clean old attempts
	var recent: Array = _failed_attempts[ip].filter(func(t): return now - t < window)
	recent.append(now)
	_failed_attempts[ip] = recent
	
	var count: int = recent.size()
	
	if count >= _max_failed_attempts:
		block_ip(ip, "Too many failed %s attempts" % attempt_type, _block_duration)
		_flag_ip(ip, "failed_attempts", count)
		return true
	
	_flag_ip(ip, "failed_attempts", count)
	return false

## Clear failed attempts for an IP
func _clear_failed_attempts(ip: String) -> void:
	_failed_attempts.erase(ip)

## Block an IP temporarily
func block_ip(ip: String, reason: String, duration: int = -1) -> void:
	if duration < 0:
		duration = _block_duration
	
	var blocked_until := Time.get_unix_time_from_system() + duration
	_blocked_ips[ip] = {
		"blocked_until": blocked_until,
		"reason": reason
	}
	
	ip_blocked.emit(ip, reason, duration)
	GameLog.warn("AppFirewall: Blocked IP %s for %ds: %s" % [ip, duration, reason])

## Unblock an IP
func unblock_ip(ip: String) -> void:
	if _blocked_ips.has(ip):
		_blocked_ips.erase(ip)
		ip_unblocked.emit(ip)
		GameLog.info("AppFirewall: Unblocked IP %s" % ip)

## Check if an IP is blocked
func is_blocked(ip: String) -> bool:
	var status = can_connect(ip)
	return not status["allowed"]

## ============================================================================
## BANNING
## ============================================================================

## Issue a permanent ban
func ban_player(player_id: String, reason: String, banned_by: String = "system") -> void:
	_permanent_bans[player_id] = {
		"reason": reason,
		"banned_by": banned_by,
		"timestamp": Time.get_unix_time_from_system()
	}
	
	var ip = _player_ips.get(player_id, "unknown")
	ban_issued.emit(player_id, ip, reason, -1)
	GameLog.warn("AppFirewall: Permanent ban issued for %s (IP: %s): %s" % [player_id, ip, reason])

## Issue a temporary ban
func temp_ban_player(player_id: String, duration_seconds: int, reason: String) -> void:
	var expires := Time.get_unix_time_from_system() + duration_seconds
	_temporary_bans[player_id] = {
		"expires": expires,
		"reason": reason
	}
	
	var ip = _player_ips.get(player_id, "unknown")
	ban_issued.emit(player_id, ip, reason, duration_seconds)
	GameLog.warn("AppFirewall: Temporary ban for %s (IP: %s, %ds): %s" % [player_id, ip, duration_seconds, reason])

## Lift a ban
func lift_ban(player_id: String) -> void:
	var was_banned := _permanent_bans.has(player_id) or _temporary_bans.has(player_id)
	
	_permanent_bans.erase(player_id)
	_temporary_bans.erase(player_id)
	
	if was_banned:
		ban_lifted.emit(player_id)
		GameLog.info("AppFirewall: Ban lifted for %s" % player_id)

## Check if player is banned
func is_banned(player_id: String) -> bool:
	if _permanent_bans.has(player_id):
		return true
	if _temporary_bans.has(player_id):
		var ban: Dictionary = _temporary_bans[player_id]
		return ban["expires"] > Time.get_unix_time_from_system()
	return false

## Get ban info for a player
func get_ban_info(player_id: String) -> Dictionary:
	if _permanent_bans.has(player_id):
		return {
			"banned": true,
			"permanent": true,
			"reason": _permanent_bans[player_id]["reason"],
			"banned_by": _permanent_bans[player_id]["banned_by"],
			"timestamp": _permanent_bans[player_id]["timestamp"]
		}
	if _temporary_bans.has(player_id):
		var ban: Dictionary = _temporary_bans[player_id]
		return {
			"banned": true,
			"permanent": false,
			"reason": ban["reason"],
			"expires": ban["expires"],
			"remaining": max(0, int(ban["expires"] - Time.get_unix_time_from_system()))
		}
	return {"banned": false}

## ============================================================================
## IP FLAGGING (for monitoring)
## ============================================================================

## Flag an IP for suspicious activity
func _flag_ip(ip: String, flag_type: String, count: int) -> void:
	if not _flagged_ips.has(ip):
		_flagged_ips[ip] = {"flags": {}, "last_activity": Time.get_unix_time_from_system()}
	
	var data: Dictionary = _flagged_ips[ip]
	data["flags"][flag_type] = count
	data["last_activity"] = Time.get_unix_time_from_system()
	
	connection_flagged.emit(ip, flag_type, count)

## Get flagged IPs
func get_flagged_ips(min_flags: int = 1) -> Array:
	var result := []
	for ip in _flagged_ips.keys():
		var data: Dictionary = _flagged_ips[ip]
		var total_flags := 0
		for flag_type in data["flags"].keys():
			total_flags += data["flags"][flag_type]
		if total_flags >= min_flags:
			result.append({
				"ip": ip,
				"flags": data["flags"],
				"total": total_flags,
				"last_activity": data["last_activity"]
			})
	return result

## ============================================================================
## LOOKUP
## ============================================================================

## Get IP for a player ID
func get_player_ip(player_id: String) -> String:
	return _player_ips.get(player_id, "")

## Get player ID for an IP
func get_ip_players(ip: String) -> Array:
	var result := []
	for player_id in _player_ips.keys():
		if _player_ips[player_id] == ip:
			result.append(player_id)
	return result

## ============================================================================
## CLEANUP
## ============================================================================

## Perform cleanup of expired data
func cleanup() -> int:
	var now := Time.get_unix_time_from_system()
	var cleaned := 0
	
	# Clean expired blocks
	for ip in _blocked_ips.keys():
		if _blocked_ips[ip]["blocked_until"] <= now:
			_blocked_ips.erase(ip)
			cleaned += 1
	
	# Clean expired temporary bans
	for player_id in _temporary_bans.keys():
		if _temporary_bans[player_id]["expires"] <= now:
			_temporary_bans.erase(player_id)
			cleaned += 1
	
	# Clean old flagged IPs (no activity for 1 hour)
	for ip in _flagged_ips.keys():
		if now - _flagged_ips[ip]["last_activity"] > 3600:
			_flagged_ips.erase(ip)
			cleaned += 1
	
	# Clean empty connection counts
	for ip in _connection_counts.keys():
		if _connection_counts[ip] <= 0:
			_connection_counts.erase(ip)
	
	if cleaned > 0:
		GameLog.debug("AppFirewall: Cleaned %d expired entries" % cleaned)
	
	return cleaned

## Get firewall statistics
func get_stats() -> Dictionary:
	return {
		"blocked_ips": _blocked_ips.size(),
		"permanent_bans": _permanent_bans.size(),
		"temporary_bans": _temporary_bans.size(),
		"flagged_ips": _flagged_ips.size(),
		"active_connections": _player_ips.size(),
		"tracked_ips": _connection_counts.size()
	}
