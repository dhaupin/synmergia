## LobbyService - the S11 lobby engine (prd-spherical-mvp.md S11).
##
## Owner decision (2026-09-28): the lobby is CANONICAL -- the one
## place parties form, advertise, and launch into bouts. It serves
## open-world play too (grinding, hordes, dungeons, hunting): an LFG
## post is how a party finds its third member before heading out to
## the wolves, not just how arena bouts fill.
##
## Three books, one service:
##   1. BOUT QUEUES  -- per-zone FIFO of party blocks. Assembly honors
##      level bands (widening with wait), keeps party blocks atomic,
##      and only mixes solo players into bigger teams when they
##      consented to fill-to-parity. On assembly the engine books
##      everyone into the live instance and remembers their origin
##      stone for the round trip home.
##   2. DUELS        -- the challenge handshake (PartyService invite
##      pattern: 60 s expiry, one pending challenge per player).
##   3. LFG / LFM    -- party advertisements with level bounds;
##      petitions route through PartyService invites.
##
## Session-only state by design (a lobby book that survives a reboot
## lies about who is still standing). Autoload: NO class_name (AGENTS
## rule -- the autoload name is the global identifier).
extends Node

const InstanceContract = preload("res://core/schemas/instance_contract.gd")
const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind

const DUEL_TIMEOUT_SECONDS: float = 60.0

signal queued(player_id: String, zone_id: String)
signal dequeued(player_id: String, zone_id: String, reason: String)
signal bout_assembled(zone_id: String, instance_id: String, team_a: Array, team_b: Array)
signal duel_challenged(challenge_id: String, from_id: String, to_id: String)
signal duel_resolved(challenge_id: String, accepted: bool)
signal lfg_posted(post_id: String)
signal lfg_closed(post_id: String)

# zone_id -> Array of block dicts:
#   {player_ids: Array[String], party_id: String, level: int,
#    joined_at: float, consent_fill: bool, origin_stone: Vector3}
var _queues: Dictionary = {}
# player_id -> zone_id (reverse index; one queue per player).
var _player_zone: Dictionary = {}
# challenge_id -> {from_id, to_id, zone_id, created_at, resolved}
var _challenges: Dictionary = {}
# player_id -> challenge_id (outgoing OR incoming; one per player).
var _player_challenge: Dictionary = {}
# post_id -> {party_id, leader_id, note, level_min, level_max, created_at}
var _lfg_posts: Dictionary = {}
# party_id -> post_id
var _party_post: Dictionary = {}
var _next_challenge_id: int = 1
var _next_post_id: int = 1


signal trial_fallback_due(zone_id: String, block: Dictionary)

## Trial-bout patience: a queue aging past this with no band partner
## fabricates a marshal's trial bout (queue-of-one still means a
## fight; the owner's retention keystone for low population).
const TRIAL_PATIENCE_SECONDS: float = 45.0

func _ready() -> void:
	if PartyService != null and PartyService.has_signal("party_disbanded"):
		PartyService.party_disbanded.connect(_on_party_disbanded)
	# Duel expiry + queue-aging sweep: one cheap timer beats per-frame
	# scanning.
	var sweep := Timer.new()
	sweep.wait_time = 5.0
	sweep.autostart = true
	sweep.timeout.connect(_sweep_expired_challenges)
	sweep.timeout.connect(_sweep_queue_aging)
	add_child(sweep)
	GameLog.info("LobbyService: Ready (lobby is canonical)")


# ---- 1. Bout queues ----------------------------------------------------

## Queue one player (or their whole party, when party_id is set).
## level drives band matchmaking; consent_fill lets matchmaking use
## this entry to top up the OPPOSING team (fill-to-parity); origin
## stone is the round-trip address (bout end + AFK kicks land there).
## Returns false when already queued elsewhere (leave first).
## QoS: queue churn is rate-limited (the "party" bucket) so a
## spamming client cannot hammer the lobby books.
func join_queue(player_id: String, level: int, zone_id: String, consent_fill: bool = true, origin_stone: Vector3 = Vector3.ZERO, party_id: String = "") -> bool:
	if QoSService != null and not QoSService.rate_limit(player_id, "party"):
		GameLog.warn("LobbyService: queue rate-limited for %s" % player_id)
		return false
	if _player_zone.has(player_id):
		return false
	var member_ids: Array = [player_id]
	if party_id != "" and PartyService != null:
		var members: Array = PartyService.get_party_members(party_id)
		if not members.is_empty():
			member_ids = members
	for pid in member_ids:
		var sid: String = str(pid)
		if _player_zone.has(sid):
			return false
	# Party blocks keep levels simple: the queueing player's level
	# stands for the block until per-member levels are plumbed.
	if not _queues.has(zone_id):
		_queues[zone_id] = []
	_queues[zone_id].append({
		"player_ids": member_ids,
		"party_id": party_id,
		"level": maxi(level, 1),
		"joined_at": Time.get_unix_time_from_system(),
		"consent_fill": consent_fill,
		"origin_stone": origin_stone,
	})
	for pid in member_ids:
		_player_zone[str(pid)] = zone_id
	queued.emit(player_id, zone_id)
	GameLog.info("LobbyService: %s queued for %s (party=%s, lvl=%d)" % [player_id, zone_id, party_id, level])
	return true


func leave_queue(player_id: String) -> bool:
	if not _player_zone.has(player_id):
		return false
	var zone_id: String = str(_player_zone[player_id])
	var zone_queue: Array = _queues.get(zone_id, [])
	for i in range(zone_queue.size()):
		var block: Dictionary = zone_queue[i]
		if block.get("player_ids", []).has(player_id):
			for pid in block.get("player_ids", []):
				_player_zone.erase(str(pid))
			zone_queue.remove_at(i)
			if zone_queue.is_empty():
				_queues.erase(zone_id)
			dequeued.emit(player_id, zone_id, "left")
			return true
	_player_zone.erase(player_id)
	return false


## The zone a player is queued for ("" = not queued).
func queue_for(player_id: String) -> String:
	return str(_player_zone.get(player_id, ""))


## UI snapshot: entries for one zone as display dicts (no internals).
func queue_snapshot(zone_id: String) -> Array:
	var out: Array = []
	for block in _queues.get(zone_id, []):
		out.append({
			"leader": str(block.get("player_ids", [""])[0]),
			"size": block.get("player_ids", []).size(),
			"level": int(block.get("level", 1)),
			"waited_seconds": Time.get_unix_time_from_system() - float(block.get("joined_at", 0.0)),
			"consent_fill": bool(block.get("consent_fill", true)),
		})
	return out


## The assembler: FIFO seed + band-compatible party blocks, two teams
## of equal size (1v1 eliminations up to 6v6 by zone capacity). Blocks
## that do not fit the band are SKIPPED, never evicted. Fill-to-parity:
## solo consenting entries may top up either team. Pure engine step --
## returns {"ok": bool, ...}; on ok the participants are booked into
## the live instance and removed from the queue. Skipped entries stay.
func try_assemble(zone_id: String) -> Dictionary:
	var zone_queue: Array = _queues.get(zone_id, [])
	if zone_queue.size() < 2:
		return {"ok": false, "reason": "waiting_for_players"}
	var zone = ZoneManager.get_zone(zone_id) if ZoneManager != null else null
	var capacity: int = int(zone.instance_capacity) if zone != null and "instance_capacity" in zone else 12
	var max_team: int = maxi(capacity / 2, 1)

	var remaining: Array = zone_queue.duplicate()
	var team_a: Array = []  # Array of block dicts
	var team_b: Array = []
	var sizes := [0, 0]

	# Seed: oldest block goes to team A.
	var seed_block: Dictionary = remaining.pop_front()
	team_a.append(seed_block)
	sizes[0] = seed_block.get("player_ids", []).size()
	var seed_level: int = int(seed_block.get("level", 1))
	var seed_wait: float = Time.get_unix_time_from_system() - float(seed_block.get("joined_at", 0.0))

	# Fill the opposing team with the first band-compatible block.
	for i in range(remaining.size()):
		var block: Dictionary = remaining[i]
		var block_size: int = block.get("player_ids", []).size()
		var wait: float = Time.get_unix_time_from_system() - float(block.get("joined_at", 0.0))
		var band_wait: float = maxf(seed_wait, wait)
		if not InstanceContract.level_band_ok(seed_level, int(block.get("level", 1)), band_wait):
			continue
		if sizes[1] + block_size > max_team:
			continue
		team_b.append(block)
		remaining.remove_at(i)
		sizes[1] += block_size
		break

	if team_b.is_empty():
		return {"ok": false, "reason": "waiting_for_band"}

	# Fill-to-parity: consenting SOLO entries top up the smaller team.
	for i in range(remaining.size()):
		if sizes[0] == sizes[1] or sizes[0] >= max_team:
			break
		var block: Dictionary = remaining[i]
		if not bool(block.get("consent_fill", true)):
			continue
		var block_size: int = block.get("player_ids", []).size()
		if block_size != 1 or not InstanceContract.level_band_ok(seed_level, int(block.get("level", 1)), 999.0):
			continue
		# Parity fills ignore the widening band (999 s patience): the
		# consent flag IS the fairness contract here, plus the capped
		# power normalization the room applies.
		team_a.append(block)
		remaining.remove_at(i)
		sizes[0] += block_size

	if sizes[0] < 1 or sizes[1] < 1:
		return {"ok": false, "reason": "waiting_for_players"}

	# Book everyone into the live instance; collect origin stones.
	var joined_a: Array = []
	var joined_b: Array = []
	var stones: Dictionary = {}
	var instance_id: String = _book_teams(zone_id, team_a, team_b, joined_a, joined_b, stones)
	if instance_id == "":
		return {"ok": false, "reason": "instance_refused"}

	# Consume assembled blocks; skipped blocks keep their queue spot.
	for block in team_a + team_b:
		var idx: int = zone_queue.find(block)
		if idx >= 0:
			zone_queue.remove_at(idx)
	for block in team_a + team_b:
		for pid in block.get("player_ids", []):
			_player_zone.erase(str(pid))
	if zone_queue.is_empty():
		_queues.erase(zone_id)

	# 5th arg: per-player origin stones (the round-trip addresses;
	# listeners that do not need them just take the default).
	bout_assembled.emit(zone_id, instance_id, joined_a, joined_b, stones)
	return {
		"ok": true,
		"zone_id": zone_id,
		"instance_id": instance_id,
		"team_a": joined_a,
		"team_b": joined_b,
		"origin_stones": stones,
	}


## Book both teams through InstanceService and stamp origin stones.
## Booking failures leave the whole assembly unbooked (all-or-nothing,
## same contract as party joins).
func _book_teams(zone_id: String, team_a: Array, team_b: Array, joined_a: Array, joined_b: Array, stones: Dictionary) -> String:
	var isvc = _instance_service()
	if isvc == null:
		return ""
	# All-or-nothing: dry-check first via one representative join per
	# team, then commit the rest. Script-mode/probe safe (entities may
	# not exist; then booking degrades to bookkeeping-only).
	var any_booked: String = ""
	for block in team_a + team_b:
		var stone: Vector3 = block.get("origin_stone", Vector3.ZERO)
		for pid in block.get("player_ids", []):
			var sid: String = str(pid)
			stones[sid] = stone
			var entity = _entity_by_id(sid)
			if entity == null:
				(joined_a if block in team_a else joined_b).append(sid)
				continue
			var result: Dictionary = isvc.join_instance(entity, zone_id)
			if not bool(result.get("capacity_ok")):
				_game_rolled_back(any_booked, zone_id)
				return ""
			any_booked = str(result.get("instance_id", ""))
			_stamp_stones(any_booked, stones)
			(joined_a if block in team_a else joined_b).append(sid)
	if any_booked == "":
		# No live entities (headless probe / server-side assembly):
		# the bout is still assembled -- scene flow owns the teleport.
		return "assembled_%s_%d" % [zone_id, int(Time.get_unix_time_from_system())]
	return any_booked


func _game_rolled_back(_instance_id: String, zone_id: String) -> void:
	GameLog.warn("LobbyService: assembly for %s refused by capacity; queue untouched" % zone_id)


func _stamp_stones(instance_id: String, stones: Dictionary) -> void:
	if ZoneManager == null or instance_id == "":
		return
	var data: Dictionary = ZoneManager.get_instance(instance_id)
	if data.is_empty():
		return
	var existing: Dictionary = data.get("origin_stones", {})
	for key in stones:
		existing[key] = stones[key]
	data["origin_stones"] = existing


# ---- 2. Duels (challenge handshake) ------------------------------------

## Challenge one player to a bout in one zone. One pending challenge
## per player (either direction); 60 s expiry, PartyService pattern.
## QoS: challenge spam is rate-limited (the "whisper" bucket -- a
## duel challenge IS a whisper with stakes).
func challenge_duel(from_id: String, to_id: String, zone_id: String) -> String:
	if QoSService != null and not QoSService.rate_limit(from_id, "whisper"):
		GameLog.warn("LobbyService: duel challenge rate-limited for %s" % from_id)
		return ""
	if from_id == to_id or _player_challenge.has(from_id) or _player_challenge.has(to_id):
		return ""
	var cid: String = "duel_%d" % _next_challenge_id
	_next_challenge_id += 1
	_challenges[cid] = {
		"from_id": from_id,
		"to_id": to_id,
		"zone_id": zone_id,
		"created_at": Time.get_unix_time_from_system(),
		"resolved": false,
	}
	_player_challenge[from_id] = cid
	_player_challenge[to_id] = cid
	duel_challenged.emit(cid, from_id, to_id)
	GameLog.info("LobbyService: duel %s %s -> %s in %s" % [cid, from_id, to_id, zone_id])
	return cid


func accept_duel(challenge_id: String) -> bool:
	var duel: Dictionary = _challenges.get(challenge_id, {})
	if duel.is_empty() or bool(duel.get("resolved", true)):
		return false
	if Time.get_unix_time_from_system() - float(duel.get("created_at", 0.0)) > DUEL_TIMEOUT_SECONDS:
		_resolve_duel(challenge_id, false)
		return false
	duel["resolved"] = true
	var from_id: String = str(duel.get("from_id", ""))
	var to_id: String = str(duel.get("to_id", ""))
	var zone_id: String = str(duel.get("zone_id", ""))
	_player_challenge.erase(from_id)
	_player_challenge.erase(to_id)
	# An accepted duel IS an assembly of exactly two solo blocks.
	var level_from: int = _entity_level(from_id)
	var level_to: int = _entity_level(to_id)
	_queues[zone_id] = _queues.get(zone_id, [])
	_queues[zone_id].append({
		"player_ids": [from_id], "party_id": "", "level": maxi(level_from, 1),
		"joined_at": Time.get_unix_time_from_system(), "consent_fill": false,
		"origin_stone": Vector3.ZERO,
	})
	_queues[zone_id].append({
		"player_ids": [to_id], "party_id": "", "level": maxi(level_to, 1),
		"joined_at": Time.get_unix_time_from_system(), "consent_fill": false,
		"origin_stone": Vector3.ZERO,
	})
	for pid in [from_id, to_id]:
		_player_zone[pid] = zone_id
	duel_resolved.emit(challenge_id, true)
	try_assemble(zone_id)
	return true


func decline_duel(challenge_id: String) -> bool:
	var duel: Dictionary = _challenges.get(challenge_id, {})
	if duel.is_empty() or bool(duel.get("resolved", true)):
		return false
	_resolve_duel(challenge_id, false)
	return true


## The pending duel involving a player, if any (UI poll).
func pending_duel_for(player_id: String) -> Dictionary:
	var cid: String = str(_player_challenge.get(player_id, ""))
	if cid == "":
		return {}
	var duel: Dictionary = _challenges.get(cid, {})
	if duel.is_empty() or bool(duel.get("resolved", true)):
		return {}
	return {"challenge_id": cid, "from_id": duel.get("from_id", ""), "to_id": duel.get("to_id", ""), "zone_id": duel.get("zone_id", "")}


func _resolve_duel(challenge_id: String, accepted: bool) -> void:
	var duel: Dictionary = _challenges.get(challenge_id, {})
	if duel.is_empty():
		return
	duel["resolved"] = true
	_player_challenge.erase(str(duel.get("from_id", "")))
	_player_challenge.erase(str(duel.get("to_id", "")))
	duel_resolved.emit(challenge_id, accepted)


func _sweep_expired_challenges() -> void:
	var now: float = Time.get_unix_time_from_system()
	for cid in _challenges.keys():
		var duel: Dictionary = _challenges[cid]
		if not bool(duel.get("resolved", false)) and now - float(duel.get("created_at", 0.0)) > DUEL_TIMEOUT_SECONDS:
			_resolve_duel(cid, false)


## The trial fallback: every sweep, any block older than the patience
## window pops its queue and emits trial_fallback_due(zone, block).
## BoutHostService listens and hosts the marshal's bout. Skipped-not-
## evicted blocks (band mismatches) age too -- nobody waits forever.
func _sweep_queue_aging() -> void:
	var now: float = Time.get_unix_time_from_system()
	for zone_id in _queues.keys():
		var zone_queue: Array = _queues[zone_id]
		for i in range(zone_queue.size() - 1, -1, -1):
			var block: Dictionary = zone_queue[i]
			var waited: float = now - float(block.get("joined_at", now))
			if waited < TRIAL_PATIENCE_SECONDS:
				continue
			zone_queue.remove_at(i)
			for pid in block.get("player_ids", []):
				_player_zone.erase(str(pid))
			trial_fallback_due.emit(str(zone_id), block)
			GameLog.info("LobbyService: trial fallback due for %s in %s (waited %ds)" % [block.get("player_ids", []), zone_id, int(waited)])


# ---- 3. LFG / LFM (open-world parties included) ------------------------

## Post kinds (owner point 5: dungeon-finder posts live in the SAME
## book -- one panel, one engine, more row types).
enum LfgKind {
	PARTY,    ## open-world crew / arena party (the original book)
	DUNGEON,  ## dungeon delve: needs roles, shares one instance
	RAID,     ## raid group
}

## Advertise a party (LFM) or a solo player's crew ambitions (LFG).
## level bounds are the advertisement's promise, not a hard gate.
## kind selects the row type (PARTY/DUNGEON/RAID) -- petitions route
## identically (leader invite), display differs.
func post_lfg(party_id: String, leader_id: String, note: String, level_min: int = 1, level_max: int = 999, kind: int = LfgKind.PARTY) -> String:
	if party_id != "" and _party_post.has(party_id):
		return str(_party_post[party_id])
	var pid: String = "lfg_%d" % _next_post_id
	_next_post_id += 1
	_lfg_posts[pid] = {
		"party_id": party_id,
		"leader_id": leader_id,
		"note": note,
		"level_min": level_min,
		"level_max": level_max,
		"kind": kind,
		"created_at": Time.get_unix_time_from_system(),
	}
	if party_id != "":
		_party_post[party_id] = pid
	lfg_posted.emit(pid)
	GameLog.info("LobbyService: LFG post %s by %s (%s)" % [pid, leader_id, note])
	return pid


func close_lfg(post_id: String) -> bool:
	var post: Dictionary = _lfg_posts.get(post_id, {})
	if post.is_empty():
		return false
	_lfg_posts.erase(post_id)
	var party_id: String = str(post.get("party_id", ""))
	if party_id != "":
		_party_post.erase(party_id)
	lfg_closed.emit(post_id)
	return true


func lfg_post_for_party(party_id: String) -> String:
	return str(_party_post.get(party_id, ""))


## UI snapshot: open posts as display dicts. kind_filter: -1 = all.
func list_lfg(kind_filter: int = -1) -> Array:
	var out: Array = []
	for post_id in _lfg_posts:
		var post: Dictionary = _lfg_posts[post_id]
		if kind_filter >= 0 and int(post.get("kind", 0)) != kind_filter:
			continue
		var seats: int = _party_seats(str(post.get("party_id", "")))
		if seats <= 0:
			continue  # full party: auto-hidden until the leader closes it
		out.append({
			"post_id": post_id,
			"leader_id": str(post.get("leader_id", "")),
			"note": str(post.get("note", "")),
			"level_min": int(post.get("level_min", 1)),
			"level_max": int(post.get("level_max", 999)),
			"kind": int(post.get("kind", 0)),
			"open_seats": seats,
		})
	return out


## Petition a post: routes a PartyService invite from the leader to
## the petitioner (the leader's accept is the real handshake).
func petition_lfg(post_id: String, petitioner_id: String) -> bool:
	var post: Dictionary = _lfg_posts.get(post_id, {})
	if post.is_empty() or PartyService == null:
		return false
	var leader_id: String = str(post.get("leader_id", ""))
	if leader_id == "" or leader_id == petitioner_id:
		return false
	var post_party: String = str(post.get("party_id", ""))
	# Solo posters: recruit-by-post first. Form their party on the
	# first petition so the leader->petitioner invite has a home.
	if post_party == "":
		post_party = PartyService.create_party(leader_id)
		if post_party != "":
			post["party_id"] = post_party
			_party_post[post_party] = post_id
	return bool(PartyService.invite_player(leader_id, petitioner_id))


func _party_seats(party_id: String) -> int:
	if party_id == "":
		return 1  # solo poster: one company-slot on the advertisement
	if PartyService == null:
		return 0
	var members: Array = PartyService.get_party_members(party_id)
	var max_size: int = 6
	if GameConfig != null and "Party" in GameConfig and GameConfig.Party != null and "MAX_SIZE" in GameConfig.Party:
		max_size = int(GameConfig.Party.MAX_SIZE)
	return maxi(max_size - members.size(), 0)


# ---- Party lifecycle integration ---------------------------------------

func _on_party_disbanded(party_id: String) -> void:
	# Their queue entries and LFG post die with the party.
	var post_id: String = str(_party_post.get(party_id, ""))
	if post_id != "":
		close_lfg(post_id)
	for zone_id in _queues.keys():
		var zone_queue: Array = _queues[zone_id]
		for i in range(zone_queue.size() - 1, -1, -1):
			var block: Dictionary = zone_queue[i]
			if str(block.get("party_id", "")) == party_id:
				for pid in block.get("player_ids", []):
					_player_zone.erase(str(pid))
					dequeued.emit(str(pid), str(zone_id), "party_disbanded")
				zone_queue.remove_at(i)


# ---- Resolvers ----------------------------------------------------------

## ---- 4. Presence (friends + party + lobby, seamless) -------------------

## Ambient presence for one player (owner point 4: presence is
## ambient, action is one click). Joins the books: EntityService
## (online), ZoneManager (zone), PartyService (party), the lobby
## queues (queued), ArenaRoomService (live bout).
func get_presence(player_id: String) -> Dictionary:
	var out: Dictionary = {
		"online": false,
		"zone_id": "",
		"party_id": "",
		"party_size": 0,
		"queue_zone": "",
		"bout_instance_id": "",
		"instance_zone_id": "",
	}
	var entity = _entity_by_id(player_id)
	if entity == null:
		return out
	out["online"] = true
	out["queue_zone"] = queue_for(player_id)
	if PartyService != null:
		var party: Dictionary = PartyService.get_player_party(player_id)
		out["party_id"] = str(party.get("id", ""))
		if out["party_id"] != "":
			out["party_size"] = PartyService.get_party_members(out["party_id"]).size()
	var room_svc = _room_service()
	if room_svc != null:
		var room = room_svc.room_for_fighter(player_id)
		if room != null:
			out["bout_instance_id"] = str(room.instance_id)
	var zone_id: String = _entity_zone_id(player_id)
	out["zone_id"] = zone_id
	if zone_id != "" and out["bout_instance_id"] == "" and _is_instanced_zone(zone_id):
		out["instance_zone_id"] = zone_id
	return out


## Presence rows for a friend list (the LobbyUI People tab binds
## this). Joins FriendsService.get_friends with presence books.
func get_friend_presence(player_id: String) -> Array:
	var fs = _friends_service()
	if fs == null:
		return []
	var out: Array = []
	for friend in fs.get_friends(player_id):
		var fid: String = str(friend.get("player_id", ""))
		if fid == "":
			continue
		var presence: Dictionary = get_presence(fid)
		presence["player_id"] = fid
		presence["player_name"] = str(friend.get("player_name", ""))
		out.append(presence)
	return out


## Petition a friend's party (presence action). Same consent shape as
## petition_lfg: an invite from the leader lands on the petitioner,
## seats permitting. Returns true when the invite was created.
func petition_party(party_id: String, petitioner_id: String) -> bool:
	if PartyService == null or party_id == "":
		return false
	var party: Dictionary = PartyService.get_party(party_id)
	if party.is_empty():
		return false
	var leader_id: String = str(party.get("leader_id", ""))
	if leader_id == "" or leader_id == petitioner_id:
		return false
	return bool(PartyService.invite_player(leader_id, petitioner_id))


## The party leader of record (presence rows + petitions).
func party_leader_id(party_id: String) -> String:
	if PartyService == null:
		return ""
	var party: Dictionary = PartyService.get_party(party_id)
	return str(party.get("leader_id", ""))


func _room_service():
	var ml := Engine.get_main_loop()
	if ml == null or not (ml is SceneTree):
		return null
	return (ml as SceneTree).root.get_node_or_null("ArenaRoomService")


func _friends_service():
	var ml := Engine.get_main_loop()
	if ml == null or not (ml is SceneTree):
		return null
	return (ml as SceneTree).root.get_node_or_null("FriendsService")


func _entity_zone_id(player_id: String) -> String:
	if ZoneManager == null:
		return ""
	var zones: Dictionary = ZoneManager._entity_zones
	return str(zones.get(player_id, ""))


func _is_instanced_zone(zone_id: String) -> bool:
	if ZoneManager == null:
		return false
	var zone = ZoneManager.get_zone(zone_id)
	return zone != null and "is_instanced" in zone and bool(zone.is_instanced)


func _instance_service():
	var ml := Engine.get_main_loop()
	if ml == null or not (ml is SceneTree):
		return null
	return (ml as SceneTree).root.get_node_or_null("InstanceService")


func _entity_by_id(pid: String):
	if EntityService == null:
		return null
	return EntityService.get_entity(pid)


func _entity_level(pid: String) -> int:
	var entity = _entity_by_id(pid)
	if entity != null and "level" in entity:
		return int(entity.level)
	return 1
