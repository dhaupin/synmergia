## FriendsService - Friends, block, and ignore list management
# FriendsService - registered as autoload
extends Node

## Resolve CooldownService autoload safely.
func _cooldown():
	var ml = Engine.get_main_loop()
	if ml == null:
		return null
	if not ml is SceneTree:
		return null
	return (ml as SceneTree).root.get_node_or_null("CooldownService")
const QoSService = preload("res://core/autoload/qos_service.gd")
const CacheWrapper = preload("res://adapters/cache/cache_wrapper.gd")

## ============================================================================
## DATA STRUCTURES
## ============================================================================

class FriendRequest:
	var id: String
	var from_player_id: String
	var from_player_name: String
	var to_player_id: String
	var created_at: float
	var expires_at: float

	func _init(p_from_id: String, p_from_name: String, p_to_id: String):
		id = "fr_%s_%s" % [p_from_id, Time.get_ticks_msec()]
		from_player_id = p_from_id
		from_player_name = p_from_name
		to_player_id = p_to_id
		created_at = Time.get_unix_time_from_system()
		expires_at = created_at + (7 * 24 * 3600)  # 7 days

	func is_expired() -> bool:
		return Time.get_unix_time_from_system() > expires_at

class FriendData:
	var player_id: String
	var player_name: String
	var added_at: float
	var note: String

	func _init(p_id: String, p_name: String):
		player_id = p_id
		player_name = p_name
		added_at = Time.get_unix_time_from_system()
		note = ""

## ============================================================================
## SIGNALS
## ============================================================================

signal friend_request_sent(request: FriendRequest)
signal friend_request_received(request: FriendRequest)
signal friend_request_accepted(friend_id: String)
signal friend_request_declined(from_id: String, to_id: String)
signal friend_request_expired(request: FriendRequest)
signal friend_added(player_id: String, friend_id: String)
signal friend_removed(player_id: String, friend_id: String)
signal player_status_changed(player_id: String, online: bool)
signal player_blocked(blocker_id: String, blocked_id: String)
signal player_unblocked(blocker_id: String, blocked_id: String)
signal player_ignored(ignorer_id: String, ignored_id: String)
signal player_unignored(ignorer_id: String, ignored_id: String)

## ============================================================================
## PRIVATE VARIABLES
## ============================================================================

var _friends: Dictionary = {}  # player_id -> Array[FriendData]
var _pending_requests: Dictionary = {}  # request_id -> FriendRequest
var _player_requests: Dictionary = {}  # player_id -> Array[FriendRequest] (sent)
var _player_requests_received: Dictionary = {}  # player_id -> Array[FriendRequest] (received)
var _blocked: Dictionary = {}  # blocker_id -> Array[blocked_id]
var _ignored: Dictionary = {}  # ignorer_id -> Array[ignored_id]
var _online_players: Dictionary = {}  # player_id -> {name, last_seen, zone}

## CacheWrapper key prefix for online status
const _kv_online_prefix := "online_player:"
var _friend_recommendations: Dictionary = {}  # player_id -> Array[recommended_id]

const MAX_FRIENDS: int = 100
const MAX_BLOCKED: int = 50
const MAX_IGNORED: int = 50
const REQUEST_EXPIRY_HOURS: int = 168  # 7 days

## Security limits
const MAX_REQUESTS_SENT_PER_HOUR: int = 20
const MAX_BLOCKS_PER_DAY: int = 10

## ============================================================================
## LIFECYCLE
## ============================================================================

func _ready() -> void:
	GameLog.info("FriendsService: Initialized")
	_load_online_status()
	set_process(true)

func _check_rate_limit(player_id: String, action_type: String) -> Dictionary:
	# Use CooldownService for unified cooldown management
	if _cooldown() and not _cooldown().try_start(player_id, action_type):
		return {"success": false, "message": "Action on cooldown. Please slow down."}

	# Check via QoSService if available
	if QoSService:
		if not QoSService.rate_limit(player_id, action_type):
			return {"success": false, "message": "Rate limited. Please slow down."}

	# Check custom limits
	match action_type:
		"friend_request":
			if _player_requests.get(player_id, []).size() >= MAX_REQUESTS_SENT_PER_HOUR:
				return {"success": false, "message": "Too many friend requests. Try again later."}
		"block":
			if _blocked.get(player_id, []).size() >= MAX_BLOCKS_PER_DAY:
				return {"success": false, "message": "Too many blocks today. Try again tomorrow."}

	return {"success": true}

func _check_player_restricted(player_id: String, action: String) -> Dictionary:
	# Check via SecurityService if available
	if SecurityService:
		if SecurityService.is_restricted(player_id, action):
			return {"success": false, "message": "You are temporarily restricted from this action."}
	return {"success": true}

func _process(delta: float) -> void:
	_check_request_expiry()

## ============================================================================
## FRIEND REQUESTS
## ============================================================================

func send_friend_request(from_id: String, from_name: String, to_id: String) -> Dictionary:
	if from_id == to_id:
		return {"success": false, "message": "Cannot send friend request to yourself"}

	# Security checks
	var rate_check := _check_rate_limit(from_id, "friend_request")
	if not rate_check.success:
		return rate_check

	var restrict_check := _check_player_restricted(from_id, "friend")
	if not restrict_check.success:
		return restrict_check

	if is_friend(from_id, to_id):
		return {"success": false, "message": "Already friends"}

	if is_blocked(to_id, from_id):
		return {"success": false, "message": "Cannot send request to this player"}

	if is_ignored(to_id, from_id):
		return {"success": false, "message": "This player has ignored you"}

	var existing := _find_pending_request(from_id, to_id)
	if existing:
		return {"success": false, "message": "Request already pending"}

	var request := FriendRequest.new(from_id, from_name, to_id)
	_pending_requests[request.id] = request

	if not _player_requests.has(from_id):
		_player_requests[from_id] = []
	_player_requests[from_id].append(request)

	if not _player_requests_received.has(to_id):
		_player_requests_received[to_id] = []
	_player_requests_received[to_id].append(request)

	friend_request_sent.emit(request)
	friend_request_received.emit(request)

	GameLog.debug("FriendsService: Friend request from %s to %s" % [from_id, to_id])

	return {"success": true, "request_id": request.id}

func accept_friend_request(to_id: String, request_id: String) -> Dictionary:
	if not _pending_requests.has(request_id):
		return {"success": false, "message": "Request not found"}

	var request: FriendRequest = _pending_requests[request_id]

	if request.to_player_id != to_id:
		return {"success": false, "message": "Request not for you"}

	if request.is_expired():
		_expire_request(request)
		return {"success": false, "message": "Request has expired"}

	_add_friend(request.from_player_id, request.from_player_name, request.to_player_id)
	_add_friend(request.to_player_id, "", request.from_player_id)  # Name resolved on next login

	_cancel_request(request)

	friend_request_accepted.emit(request.from_player_id)
	friend_request_declined.emit(request.from_player_id, request.to_player_id)

	return {"success": true, "friend_id": request.from_player_id, "friend_name": request.from_player_name}

func decline_friend_request(to_id: String, request_id: String) -> Dictionary:
	if not _pending_requests.has(request_id):
		return {"success": false, "message": "Request not found"}

	var request: FriendRequest = _pending_requests[request_id]

	if request.to_player_id != to_id:
		return {"success": false, "message": "Request not for you"}

	_cancel_request(request)

	friend_request_declined.emit(request.from_player_id, request.to_player_id)

	return {"success": true}

func cancel_friend_request(from_id: String, request_id: String) -> Dictionary:
	if not _pending_requests.has(request_id):
		return {"success": false, "message": "Request not found"}

	var request: FriendRequest = _pending_requests[request_id]

	if request.from_player_id != from_id:
		return {"success": false, "message": "Request not from you"}

	_cancel_request(request)

	return {"success": true}

func _cancel_request(request: FriendRequest) -> void:
	_pending_requests.erase(request.id)

	if _player_requests.has(request.from_player_id):
		var arr: Array = _player_requests[request.from_player_id]
		arr.erase(request)

	if _player_requests_received.has(request.to_player_id):
		var arr: Array = _player_requests_received[request.to_player_id]
		arr.erase(request)

func _expire_request(request: FriendRequest) -> void:
	_cancel_request(request)
	friend_request_expired.emit(request)

func _find_pending_request(from_id: String, to_id: String) -> FriendRequest:
	for request_id in _pending_requests.keys():
		var request: FriendRequest = _pending_requests[request_id]
		if request.from_player_id == from_id and request.to_player_id == to_id:
			return request
	return null

func _check_request_expiry() -> void:
	var now := Time.get_unix_time_from_system()
	var expired: Array = []

	for request_id in _pending_requests.keys():
		var request: FriendRequest = _pending_requests[request_id]
		if request.is_expired():
			expired.append(request)

	for request in expired:
		_expire_request(request)

## ============================================================================
## FRIEND MANAGEMENT
## ============================================================================

func add_friend(player_id: String, friend_id: String, friend_name: String = "") -> Dictionary:
	if player_id == friend_id:
		return {"success": false, "message": "Cannot add yourself as friend"}

	if not _friends.has(player_id):
		_friends[player_id] = []

	var friends: Array = _friends[player_id]

	if friends.size() >= MAX_FRIENDS:
		return {"success": false, "message": "Friend list is full (%d/%d)" % [MAX_FRIENDS, MAX_FRIENDS]}

	for friend_data in friends:
		if friend_data.player_id == friend_id:
			return {"success": false, "message": "Already friends"}

	var data := FriendData.new(friend_id, friend_name)
	friends.append(data)
	_friends[player_id] = friends

	friend_added.emit(player_id, friend_id)

	return {"success": true}

func _add_friend(player_id: String, player_name: String, friend_id: String) -> void:
	add_friend(player_id, friend_id, player_name)

func remove_friend(player_id: String, friend_id: String) -> Dictionary:
	if not _friends.has(player_id):
		return {"success": false, "message": "No friends list found"}

	var friends: Array = _friends[player_id]

	for i in range(friends.size()):
		if friends[i].player_id == friend_id:
			friends.remove_at(i)
			friend_removed.emit(player_id, friend_id)

			# Remove reciprocal friendship
			if _friends.has(friend_id):
				var reciprocal: Array = _friends[friend_id]
				for j in range(reciprocal.size()):
					if reciprocal[j].player_id == player_id:
						reciprocal.remove_at(j)
						break

			return {"success": true}

	return {"success": false, "message": "Friend not found"}

func is_friend(player_id: String, other_id: String) -> bool:
	if not _friends.has(player_id):
		return false

	for friend_data in _friends[player_id]:
		if friend_data.player_id == other_id:
			return true

	return false

func get_friends(player_id: String) -> Array:
	if not _friends.has(player_id):
		return []

	var result: Array = []
	var friends: Array = _friends[player_id]

	for friend_data in friends:
		var status := _get_player_status(friend_data.player_id)
		result.append({
			"player_id": friend_data.player_id,
			"player_name": friend_data.player_name,
			"added_at": friend_data.added_at,
			"note": friend_data.note,
			"online": status.online,
			"last_seen": status.last_seen,
			"zone": status.zone
		})

	return result

func set_friend_note(player_id: String, friend_id: String, note: String) -> Dictionary:
	if not _friends.has(player_id):
		return {"success": false, "message": "No friends list found"}

	var friends: Array = _friends[player_id]

	for friend_data in friends:
		if friend_data.player_id == friend_id:
			friend_data.note = note.substr(0, 100)  # Max 100 chars
			return {"success": true}

	return {"success": false, "message": "Friend not found"}

## ============================================================================
## BLOCK LIST
## ============================================================================

func block_player(blocker_id: String, blocked_id: String, reason: String = "") -> Dictionary:
	if blocker_id == blocked_id:
		return {"success": false, "message": "Cannot block yourself"}

	# Security checks
	var rate_check := _check_rate_limit(blocker_id, "block")
	if not rate_check.success:
		return rate_check

	var restrict_check := _check_player_restricted(blocker_id, "block")
	if not restrict_check.success:
		return restrict_check

	if is_blocked(blocker_id, blocked_id):
		return {"success": false, "message": "Already blocked"}

	if not _blocked.has(blocker_id):
		_blocked[blocker_id] = []

	var blocked: Array = _blocked[blocker_id]

	if blocked.size() >= MAX_BLOCKED:
		return {"success": false, "message": "Block list is full (%d/%d)" % [MAX_BLOCKED, MAX_BLOCKED]}

	blocked.append(blocked_id)
	_blocked[blocker_id] = blocked

	# Auto-unfriend when blocking
	if is_friend(blocker_id, blocked_id):
		remove_friend(blocker_id, blocked_id)

	# Cancel any pending friend requests
	var pending := _find_pending_request(blocker_id, blocked_id)
	if pending:
		_cancel_request(pending)
	pending = _find_pending_request(blocked_id, blocker_id)
	if pending:
		_cancel_request(pending)

	player_blocked.emit(blocker_id, blocked_id)

	return {"success": true}

func unblock_player(blocker_id: String, blocked_id: String) -> Dictionary:
	if not _blocked.has(blocker_id):
		return {"success": false, "message": "No block list found"}

	var blocked: Array = _blocked[blocker_id]
	blocked.erase(blocked_id)
	_blocked[blocker_id] = blocked

	player_unblocked.emit(blocker_id, blocked_id)

	return {"success": true}

func is_blocked(blocker_id: String, blocked_id: String) -> bool:
	if not _blocked.has(blocker_id):
		return false
	return _blocked[blocker_id].has(blocked_id)

func get_blocked_players(blocker_id: String) -> Array:
	if not _blocked.has(blocker_id):
		return []
	return _blocked[blocker_id]

## ============================================================================
## IGNORE LIST
## ============================================================================

func ignore_player(ignorer_id: String, ignored_id: String, reason: String = "") -> Dictionary:
	if ignorer_id == ignored_id:
		return {"success": false, "message": "Cannot ignore yourself"}

	# Security checks
	var restrict_check := _check_player_restricted(ignorer_id, "ignore")
	if not restrict_check.success:
		return restrict_check

	if is_ignored(ignorer_id, ignored_id):
		return {"success": false, "message": "Already ignored"}

	if not _ignored.has(ignorer_id):
		_ignored[ignorer_id] = []

	var ignored: Array = _ignored[ignorer_id]

	if ignored.size() >= MAX_IGNORED:
		return {"success": false, "message": "Ignore list is full (%d/%d)" % [MAX_IGNORED, MAX_IGNORED]}

	ignored.append(ignored_id)
	_ignored[ignorer_id] = ignored

	player_ignored.emit(ignorer_id, ignored_id)

	return {"success": true}

func unignore_player(ignorer_id: String, ignored_id: String) -> Dictionary:
	if not _ignored.has(ignorer_id):
		return {"success": false, "message": "No ignore list found"}

	var ignored: Array = _ignored[ignorer_id]
	ignored.erase(ignored_id)
	_ignored[ignorer_id] = ignored

	player_unignored.emit(ignorer_id, ignored_id)

	return {"success": true}

func is_ignored(ignorer_id: String, ignored_id: String) -> bool:
	if not _ignored.has(ignorer_id):
		return false
	return _ignored[ignorer_id].has(ignored_id)

func get_ignored_players(ignorer_id: String) -> Array:
	if not _ignored.has(ignorer_id):
		return []
	return _ignored[ignorer_id]

## ============================================================================
## ONLINE STATUS
## ============================================================================

func set_player_online(player_id: String, player_name: String, zone_id: String = "") -> void:
	_online_players[player_id] = {
		"name": player_name,
		"online": true,
		"last_seen": 0,
		"zone": zone_id,
		"last_update": Time.get_unix_time_from_system()
	}
	_persist_online_status(player_id)

	player_status_changed.emit(player_id, true)
	GameLog.debug("FriendsService: Player %s online in zone %s" % [player_name, zone_id])

func set_player_offline(player_id: String) -> void:
	if _online_players.has(player_id):
		_online_players[player_id].online = false
		_online_players[player_id].last_seen = Time.get_unix_time_from_system()
		_persist_online_status(player_id)
		player_status_changed.emit(player_id, false)
		GameLog.debug("FriendsService: Player %s offline" % _online_players[player_id].name)

func update_player_zone(player_id: String, zone_id: String) -> void:
	if _online_players.has(player_id):
		_online_players[player_id].zone = zone_id
		_online_players[player_id].last_update = Time.get_unix_time_from_system()

func _get_player_status(player_id: String) -> Dictionary:
	if _online_players.has(player_id):
		var status: Dictionary = _online_players[player_id]
		return {
			"online": status.online,
			"last_seen": status.get("last_seen", 0),
			"zone": status.get("zone", "")
		}
	return {"online": false, "last_seen": 0, "zone": ""}

func is_online(player_id: String) -> bool:
	if _online_players.has(player_id):
		return _online_players[player_id].online
	return false

func get_online_friends(player_id: String) -> Array:
	var friends := get_friends(player_id)
	var online: Array = []

	for friend in friends:
		if friend.online:
			online.append(friend)

	return online

func get_online_count(player_id: String) -> int:
	return get_online_friends(player_id).size()

## ============================================================================
## PENDING REQUESTS
## ============================================================================

func get_pending_requests_sent(player_id: String) -> Array:
	if not _player_requests.has(player_id):
		return []

	var result: Array = []
	for request in _player_requests[player_id]:
		var r: FriendRequest = request
		result.append({
			"id": r.id,
			"to_player_id": r.to_player_id,
			"created_at": r.created_at,
			"expires_at": r.expires_at,
			"expired": r.is_expired()
		})

	return result

func get_pending_requests_received(player_id: String) -> Array:
	if not _player_requests_received.has(player_id):
		return []

	var result: Array = []
	for request in _player_requests_received[player_id]:
		var r: FriendRequest = request
		result.append({
			"id": r.id,
			"from_player_id": r.from_player_id,
			"from_player_name": r.from_player_name,
			"created_at": r.created_at,
			"expires_at": r.expires_at,
			"expired": r.is_expired()
		})

	return result

## ============================================================================
## RECOMMENDATIONS
## ============================================================================

func get_friend_recommendations(player_id: String) -> Array:
	# Placeholder for social graph analysis
	# Could be based on: mutual friends, same guild, same zone, etc.
	if _friend_recommendations.has(player_id):
		return _friend_recommendations[player_id]
	return []

func add_recommendation(player_id: String, recommended_id: String, score: float) -> void:
	if not _friend_recommendations.has(player_id):
		_friend_recommendations[player_id] = []

	var recs: Array = _friend_recommendations[player_id]
	recs.append({
		"player_id": recommended_id,
		"score": score,
		"added_at": Time.get_unix_time_from_system()
	})

	# Sort by score descending and keep top 10
	recs.sort_custom(func(a, b): return a.score > b.score)
	if recs.size() > 10:
		recs.resize(10)

	_friend_recommendations[player_id] = recs

## ============================================================================
## UTILITY
## ============================================================================

func can_interact_with(player_id: String, other_id: String) -> bool:
	# Returns false if blocked or ignored
	return not is_blocked(other_id, player_id) and not is_ignored(other_id, player_id)

func get_social_summary(player_id: String) -> Dictionary:
	return {
		"friends_count": _friends.get(player_id, []).size() if _friends.has(player_id) else 0,
		"online_friends": get_online_count(player_id),
		"blocked_count": _blocked.get(player_id, []).size() if _blocked.has(player_id) else 0,
		"ignored_count": _ignored.get(player_id, []).size() if _ignored.has(player_id) else 0,
		"pending_sent": get_pending_requests_sent(player_id).size(),
		"pending_received": get_pending_requests_received(player_id).size()
	}

## == Persistence ============================================================

func _load_online_status() -> void:
	var cache := CacheWrapper.new()
	_online_players = {}
	for key in cache._store.keys():
		if key.begins_with(_kv_online_prefix):
			var player_id = key.substr(_kv_online_prefix.length())
			var data: Dictionary = cache.get(key)
			if not data.is_empty():
				_online_players[player_id] = data

func _persist_online_status(player_id: String) -> void:
	var cache := CacheWrapper.new()
	if _online_players.has(player_id):
		var data: Dictionary = _online_players[player_id]
		if data.get("online", false):
			cache.set(_kv_online_prefix + player_id, data, 300)  # 5 min TTL
		else:
			cache.set(_kv_online_prefix + player_id, data, 60)  # 1 min TTL for offline
	else:
		cache.delete(_kv_online_prefix + player_id)
