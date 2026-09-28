## RecentPlayersService - the "heated unknown rival" book (S12 social).
##
## Every real (non-trial) bout records a ring-buffer entry per
## participant: who else fought, where, the mode, the result, when.
## Surfaced in LobbyUI's Duels tab; the one-click REMATCH sends the
## duel challenge with the same zone. Entries are ids + metadata only
## (no chat, no location beyond zone) and consent paths stay the
## existing ones (duel accept, party/friend invites).
##
## Ring buffer: capped at RECENT_CAP per player (oldest evicted).
## Persisted through DictStore (adapter layer -- AGENTS persistence
## rule), JSON-friendly dicts only. Load is lazy on first touch.
## Autoload: NO class_name (AGENTS rule).
extends Node

const DictStore = preload("res://adapters/persistence/dict_store.gd")

const RECENT_CAP: int = 20
const _kv_prefix := "recent_players:"

# player_id -> Array of entry dicts (newest first)
var _recent: Dictionary = {}
var _loaded: Dictionary = {}
# Privacy opt-out (prd-social-instances.md): hidden players never
# land in OTHERS' books; they still keep their own record.
var _hidden: Dictionary = {}


func _ready() -> void:
	GameLog.info("RecentPlayersService: Ready (the rival list remembers)")


## Record a finished bout for one participant. participants: all
## fighter ids; the loop strips the subject per book. team_of maps
## participant id -> team; winner_team decides the result line.
func record_bout(participants: Array, zone_id: String, mode: int, winner_team: int, team_of: Dictionary) -> void:
	if participants.size() < 2:
		return
	var when: int = int(Time.get_unix_time_from_system())
	for pid in participants:
		var sid: String = str(pid)
		var others: Array = []
		for other in participants:
			var oid: String = str(other)
			if oid != sid:
				others.append(oid)
		if others.is_empty():
			continue
		var result: String = "win"
		if int(team_of.get(sid, -1)) != winner_team:
			result = "loss"
		var entry: Dictionary = {
			"fighters": others,
			"zone_id": zone_id,
			"mode": int(mode),
			"result": result,
			"when": when,
		}
		_push(sid, entry)


## One entry per BOUT (not per pair) -- probe seam for exact inserts.
func record_entry_for(sid: String, entry: Dictionary) -> void:
	_push(sid, entry)


func _push(sid: String, entry: Dictionary) -> void:
	var book: Array = _book_for(sid)
	book.push_front(entry)
	if book.size() > RECENT_CAP:
		book.resize(RECENT_CAP)
	_recent[sid] = book
	_save(sid)


## The display list (newest first), capped.
func list_recent(player_id: String, limit: int = RECENT_CAP) -> Array:
	var book: Array = _book_for(player_id)
	return book.slice(0, mini(limit, book.size()))


## Book a rematch: duel challenge against the entry's most recent
## rival with their zone. Returns the challenge id ("" = refused).
func rematch_last(player_id: String, entry_index: int = 0) -> String:
	var book: Array = _book_for(player_id)
	if entry_index >= book.size():
		return ""
	var entry: Dictionary = book[entry_index]
	var fighters: Array = entry.get("fighters", [])
	if fighters.is_empty():
		return ""
	var lobby = _lobby_service()
	if lobby == null:
		return ""
	return str(lobby.challenge_duel(player_id, str(fighters[0]), str(entry.get("zone_id", ""))))


func set_recent_hidden(player_id: String, hidden: bool) -> void:
	_hidden[player_id] = hidden


func is_recent_hidden(player_id: String) -> bool:
	return bool(_hidden.get(player_id, false))


# ---- Persistence (DictStore; lazy load) -----------------------------------

func _book_for(player_id: String) -> Array:
	if not _loaded.has(player_id):
		var store := DictStore.new()
		var raw = store.get_kv(_kv_prefix + player_id, [])
		var book: Array = []
		if raw is Array:
			for entry in raw:
				if entry is Dictionary:
					book.append(entry)
		_recent[player_id] = book
		_loaded[player_id] = true
	return _recent.get(player_id, [])


func _save(player_id: String) -> void:
	var store := DictStore.new()
	store.set_kv(_kv_prefix + player_id, _recent.get(player_id, []))


# ---- Resolvers ------------------------------------------------------------

func _lobby_service():
	var ml := Engine.get_main_loop()
	if ml == null or not (ml is SceneTree):
		return null
	return (ml as SceneTree).root.get_node_or_null("LobbyService")
