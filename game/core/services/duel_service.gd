## DuelService - Honorable 1v1 challenge flow.
##
## Flow: challenge_duel(A, B) -> B accepts/declines/ignores (timeout) ->
## active duel stamps BOTH participants with the _duel_death meta flag.
## On death, DeathFeatures._resolve_drop_mode() reads that flag and drops
## nothing, and apply_death_penalties skips the karma loss -- a duel kill
## is honorable combat, not murder. The loser keeps their gear.
##
## Chat integration: /duel <player> and /concede via ChatService hooks.
extends Node

const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind

signal duel_challenged(challenger_id: String, target_id: String)
signal duel_declined(challenger_id: String, target_id: String)
signal duel_started(duel_id: String, player_a: String, player_b: String)
signal duel_ended(duel_id: String, winner_id: String, loser_id: String, reason: String)

## Challenge expires if unanswered.
const CHALLENGE_TIMEOUT_SECONDS: float = 30.0
## Duel range: if the duelists drift this far apart, the duel breaks off.
const DUEL_RANGE: float = 60.0

var _pending_challenges: Dictionary = {}   # challenge_id -> {from, to, expires_at}
var _active_duels: Dictionary = {}         # duel_id -> {a, b, started_at}
var _duel_of_player: Dictionary = {}       # player_id -> duel_id
var _next_id: int = 1

## Registered players: test seam and headless registries. Checked
## before EntityService resolution.
var _registered_players: Dictionary = {}   # player_id -> Node


func register_player(player) -> void:
	if player != null and "entity_id" in player:
		_registered_players[str(player.entity_id)] = player

func _ready() -> void:
	# Cleanup loop for expired challenges and out-of-range duels.
	set_process(true)
	GameLog.info("DuelService: Ready")

func _process(_delta: float) -> void:
	var now := Time.get_unix_time_from_system()

	for cid in _pending_challenges.keys():
		var ch: Dictionary = _pending_challenges[cid]
		if now > float(ch.get("expires_at", 0.0)):
			_pending_challenges.erase(cid)
			_toast(str(ch.get("from", "")), "Your duel challenge expired.", "duel_expired:%s" % str(cid))
			_toast(str(ch.get("to", "")), "Duel challenge expired.", "duel_expired_to:%s" % str(cid))

	for did in _active_duels.keys():
		var duel: Dictionary = _active_duels[did]
		var a = _find_player(str(duel.get("a", "")))
		var b = _find_player(str(duel.get("b", "")))
		if a == null or b == null:
			continue  # players logged off; end_duel handles cleanup elsewhere
		var dist: float = a.global_position.distance_to(b.global_position) \
			if ("global_position" in a and "global_position" in b) else 0.0
		if dist > DUEL_RANGE:
			end_duel(did, "", "", "out_of_range")


## ---------------------------------------------------------------------------
## CHALLENGE FLOW
## ---------------------------------------------------------------------------

## A challenges B. Returns the challenge id ("" on rejection).
func challenge_duel(challenger_id: String, target_id: String) -> String:
	if challenger_id == "" or target_id == "" or challenger_id == target_id:
		return ""
	if _duel_of_player.has(challenger_id):
		_toast(challenger_id, "You are already in a duel.", "duel_busy:%s" % challenger_id)
		return ""
	if _duel_of_player.has(target_id):
		_toast(challenger_id, "That player is already in a duel.", "duel_target_busy:%s" % target_id)
		return ""

	# Replace any earlier challenge in either direction (re-challenge = refresh).
	for cid in _pending_challenges.keys():
		var ch: Dictionary = _pending_challenges[cid]
		if str(ch.get("from")) == challenger_id and str(ch.get("to")) == target_id:
			_pending_challenges.erase(cid)

	var challenge_id := "duel_ch_%d_%d" % [Time.get_unix_time_from_system(), _next_id]
	_next_id += 1
	_pending_challenges[challenge_id] = {
		"from": challenger_id,
		"to": target_id,
		"expires_at": Time.get_unix_time_from_system() + CHALLENGE_TIMEOUT_SECONDS,
	}
	duel_challenged.emit(challenger_id, target_id)
	_toast(target_id, "%s challenges you to a duel! (/accept or /decline)" % _name_of(challenger_id),
		"duel_ch_to:%s:%s" % [challenger_id, target_id])
	_toast(challenger_id, "Duel challenge sent to %s." % _name_of(target_id),
		"duel_ch_from:%s:%s" % [challenger_id, target_id])
	return challenge_id


func accept_duel(target_id: String) -> String:
	# Find the newest challenge addressed to this player.
	var found_id := ""
	var newest: float = -1.0
	for cid in _pending_challenges:
		var ch: Dictionary = _pending_challenges[cid]
		if str(ch.get("to")) == target_id and float(ch.get("expires_at", 0.0)) > newest:
			newest = float(ch.get("expires_at"))
			found_id = cid
	if found_id == "":
		_toast(target_id, "No pending duel challenge.", "duel_none:%s" % target_id)
		return ""

	var ch: Dictionary = _pending_challenges[found_id]
	_pending_challenges.erase(found_id)

	var a := str(ch["from"])
	var b := target_id
	if _duel_of_player.has(a) or _duel_of_player.has(b):
		return ""

	var duel_id := "duel_%d_%d" % [Time.get_unix_time_from_system(), _next_id]
	_next_id += 1
	_active_duels[duel_id] = {"a": a, "b": b, "started_at": Time.get_unix_time_from_system()}
	_duel_of_player[a] = duel_id
	_duel_of_player[b] = duel_id

	# Stamp BOTH duelists: DeathFeatures reads this meta on death to
	# drop nothing, and karma transfer is suppressed for duel kills.
	for pid in [a, b]:
		var player = _find_player(pid)
		if player != null:
			player.set_meta("_duel_death", true)

	duel_started.emit(duel_id, a, b)
	_toast(a, "Duel with %s begins!" % _name_of(b), "duel_go:%s" % duel_id)
	_toast(b, "Duel with %s begins!" % _name_of(a), "duel_go_b:%s" % duel_id)
	return duel_id


func decline_duel(target_id: String) -> bool:
	for cid in _pending_challenges.keys():
		var ch: Dictionary = _pending_challenges[cid]
		if str(ch.get("to")) == target_id:
			var challenger_id := str(ch["from"])
			_pending_challenges.erase(cid)
			duel_declined.emit(challenger_id, target_id)
			_toast(challenger_id, "%s declined your duel." % _name_of(target_id), "duel_dec:%s" % target_id)
			return true
	return false


## End a duel. winner_id may be "" (draw / out of range). reason:
## "death" | "concede" | "out_of_range" | "cancel"
func end_duel(duel_id: String, winner_id: String, loser_id: String, reason: String) -> void:
	var duel: Dictionary = _active_duels.get(duel_id, {})
	if duel.is_empty():
		return
	_active_duels.erase(duel_id)
	var a := str(duel.get("a", ""))
	var b := str(duel.get("b", ""))
	_duel_of_player.erase(a)
	_duel_of_player.erase(b)

	# Clear the duel flags.
	for pid in [a, b]:
		var player = _find_player(pid)
		if player != null and player.has_meta("_duel_death"):
			player.remove_meta("_duel_death")

	# Death reason: the death flow already resolved the kill; here we
	# only announce. Concede: the loser conceded live.
	if winner_id != "":
		_toast(winner_id, "You win the duel%s" % (" (%s)" % reason if reason != "" else ""),
			"duel_win:%s" % duel_id)
		_toast(loser_id, "You lose the duel%s" % (" (%s)" % reason if reason != "" else ""),
			"duel_lose:%s" % duel_id)
	elif reason == "out_of_range":
		_toast(a, "Duel ended: out of range.", "duel_oor:%s" % duel_id)
		_toast(b, "Duel ended: out of range.", "duel_oor_b:%s" % duel_id)

	duel_ended.emit(duel_id, winner_id, loser_id, reason)


## Concede the live duel.
func concede_duel(player_id: String) -> bool:
	var duel_id: String = str(_duel_of_player.get(player_id, ""))
	if duel_id == "":
		return false
	var duel: Dictionary = _active_duels.get(duel_id, {})
	var a := str(duel.get("a", ""))
	var b := str(duel.get("b", ""))
	var winner := b if player_id == a else a
	end_duel(duel_id, winner, player_id, "concede")
	return true


## ---------------------------------------------------------------------------
## DEATH HOOK (called by DeathFeatures on player death)
## ---------------------------------------------------------------------------

## Was this player's death a duel kill? If so, resolve the duel and tell
## the caller to skip karma. Called BEFORE drop-mode resolution so the
## flag is still present.
func resolve_duel_death(victim_id: String, killer_id: String) -> bool:
	var duel_id: String = str(_duel_of_player.get(victim_id, ""))
	if duel_id == "":
		return false
	end_duel(duel_id, killer_id, victim_id, "death")
	return true


func is_in_duel(player_id: String) -> bool:
	return _duel_of_player.has(player_id)


func get_duel_opponent(player_id: String) -> String:
	var duel: Dictionary = _active_duels.get(str(_duel_of_player.get(player_id, "")), {})
	if duel.is_empty():
		return ""
	var a := str(duel.get("a", ""))
	return str(duel.get("b", "")) if player_id == a else a


# --- helpers ---------------------------------------------------------------

func _find_player(player_id: String):
	if _registered_players.has(player_id):
		return _registered_players[player_id]
	var es = _resolve("EntityService")
	if es != null and es.has_method("get_entity"):
		var found = es.get_entity(player_id)
		if found != null:
			return found
	var pm = _resolve("PlayerManager")
	if pm != null and "local_player" in pm and pm.local_player != null:
		if "entity_id" in pm.local_player and str(pm.local_player.entity_id) == player_id:
			return pm.local_player
	return null


func _name_of(player_id: String) -> String:
	var player = _find_player(player_id)
	if player != null and "display_name" in player:
		return str(player.display_name)
	return player_id


func _toast(player_id: String, message: String, dedupe_key: String) -> void:
	if not is_instance_valid(NotificationService):
		return
	NotificationService.notify(
		NotifKind.AUTO_ACTION,
		message,
		"DuelService",
		dedupe_key,
		{},
		player_id
	)


func _resolve(autoload_name: String):
	var ml := Engine.get_main_loop()
	if ml == null or not (ml is SceneTree):
		return null
	var tree := ml as SceneTree
	if tree.root == null:
		return null
	return tree.root.get_node_or_null(NodePath(autoload_name))
