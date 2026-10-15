## LobbyUI - the S11 lobby panel (owner decision: the lobby is
## canonical). One panel, three tabs:
##
##   BOUTS - matchmaking: queue for a bout zone (coliseum/sandpit),
##           consent to fill-to-parity, leave queue, live queue feed.
##   DUELS - the challenge handshake: challenge a player id, accept or
##           decline the pending duel (60 s expiry, one per player).
##   LFG   - looking-for-group / looking-for-more. Open-world play is
##           first class here: grinding crews, horde raids, dungeon
##           delves, hunting parties -- a post is how a party fills
##           before it ever walks out of town.
##
## Bindings are read straight from LobbyService on refresh(); signals
## trigger re-reads while open. Registered in MenuManager as "lobby"
## (L key, HudHotkeys). Built in code, ChronicleUI convention.
extends "res://ui/components/ui_panel.gd"

class_name LobbyUI

const Contract = preload("res://core/schemas/instance_contract.gd")

## Queuable bout zones: (zone_id, label). S11 scope: the two live
## arenas; ROYALE appears when its zone ships.
const BOUT_ZONES: Array = [
	["zone_arena_coliseum", "The Coliseum (Elimination)"],
	["zone_arena_sandpit", "The Sandpit (Team Deathmatch)"],
	["zone_royale_valley", "The Sundered Valley (Royale)"],
]

var _tabs: TabContainer
var _queue_zone: OptionButton
var _queue_fill: CheckButton
var _queue_status: Label
var _queue_feed: VBoxContainer
var _duel_target: LineEdit
var _duel_zone: OptionButton
var _duel_status: Label
var _duel_pending: VBoxContainer
var _recent_list: VBoxContainer
var _lfg_note: LineEdit
var _lfg_min: SpinBox
var _lfg_max: SpinBox
var _lfg_status: Label
var _lfg_list: VBoxContainer
var _friends_list: VBoxContainer
var _local_id: String = ""


func _ready() -> void:
	super._ready()
	set_title("The Lobby")
	set_panel_size(Vector2(560, 540))
	_setup_bouts_tab()
	_setup_duels_tab()
	_setup_lfg_tab()
	_local_id = _resolve_local_id()
	_hook_signals()
	refresh()
	# Re-pull service truth every time the panel opens (ChronicleUI
	# convention); _player_id is set by MenuManager's open path.
	panel_opened.connect(_on_panel_opened)


func _resolve_local_id() -> String:
	var pm := get_node_or_null("/root/PlayerManager")
	if pm == null:
		return ""
	var local = pm.get("local_player")
	if local == null or not is_instance_valid(local):
		return ""
	var eid = local.get("entity_id")
	return String(eid) if eid != null else ""


func _hook_signals() -> void:
	var svc = _lobby_service()
	if svc == null:
		return
	if svc.has_signal("queued"):
		svc.queued.connect(func(_p: String, _z: String): refresh())
		svc.dequeued.connect(func(_p: String, _z: String, _r: String): refresh())
		svc.duel_challenged.connect(func(_c: String, _f: String, _t: String): refresh())
		svc.duel_resolved.connect(func(_c: String, _a: bool): refresh())
		svc.lfg_posted.connect(func(_p: String): refresh())
		svc.lfg_closed.connect(func(_p: String): refresh())


# ---- Tab 1: Bouts -------------------------------------------------------

func _setup_bouts_tab() -> void:
	var panel := get_panel()
	if not panel:
		return
	var main: VBoxContainer = panel.get_node_or_null("Main")
	if not main:
		return
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_child(_tabs)

	var bouts := VBoxContainer.new()
	bouts.add_theme_constant_override("separation", 8)
	_tabs.add_child(bouts)
	_tabs.set_tab_title(0, " Bouts ")

	var head := Label.new()
	head.text = "Matchmaking -- queue at any stone, the bout teleports you in and back."
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	bouts.add_child(head)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	bouts.add_child(row)
	var mode_lbl := Label.new()
	mode_lbl.text = "Mode:"
	row.add_child(mode_lbl)
	_queue_zone = OptionButton.new()
	for entry in BOUT_ZONES:
		_queue_zone.add_item(str(entry[1]))
	row.add_child(_queue_zone)

	_queue_fill = CheckButton.new()
	_queue_fill.text = "Allow fill-to-parity"
	_queue_fill.button_pressed = true
	_queue_fill.tooltip_text = "Matchmaking may add solo players to complete even teams."
	row.add_child(_queue_fill)

	var queue_btn := Button.new()
	queue_btn.text = "Queue Up"
	queue_btn.pressed.connect(_on_queue_pressed)
	bouts.add_child(queue_btn)

	var leave_btn := Button.new()
	leave_btn.text = "Leave Queue"
	leave_btn.pressed.connect(_on_leave_queue_pressed)
	bouts.add_child(leave_btn)

	_queue_status = Label.new()
	_queue_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bouts.add_child(_queue_status)

	bouts.add_child(HSeparator.new())
	bouts.add_child(_section_label("Queued now"))
	_queue_feed = VBoxContainer.new()
	_queue_feed.add_theme_constant_override("separation", 4)
	bouts.add_child(_queue_feed)


func _on_queue_pressed() -> void:
	var svc = _lobby_service()
	if svc == null or _local_id == "":
		_queue_status.text = "The lobby hears nothing yet (no local player)."
		return
	var zone_entry: Array = BOUT_ZONES[_queue_zone.selected]
	if svc.leave_queue(_local_id):
		pass  # re-queue below with the new settings
	if svc.join_queue(_local_id, _local_level(), str(zone_entry[0]), _queue_fill.button_pressed):
		_queue_status.text = "Queued for %s. Watch the stone." % str(zone_entry[1])
	else:
		_queue_status.text = "Already queued -- leave first, then re-queue."


func _on_leave_queue_pressed() -> void:
	var svc = _lobby_service()
	if svc != null and svc.leave_queue(_local_id):
		_queue_status.text = "Left the queue."
	else:
		_queue_status.text = "You were not queued."


# ---- Tab 2: Duels -------------------------------------------------------

func _setup_duels_tab() -> void:
	var duels := VBoxContainer.new()
	duels.add_theme_constant_override("separation", 8)
	_tabs.add_child(duels)
	_tabs.set_tab_title(1, " Duels ")

	var head := Label.new()
	head.text = "Challenge one player. Both must accept within 60 s."
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	duels.add_child(head)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	duels.add_child(row)
	row.add_child(_mk_label("Player:"))
	_duel_target = LineEdit.new()
	_duel_target.placeholder_text = "player id"
	_duel_target.custom_minimum_size = Vector2(180, 0)
	row.add_child(_duel_target)
	row.add_child(_mk_label("Where:"))
	_duel_zone = OptionButton.new()
	for entry in BOUT_ZONES:
		_duel_zone.add_item(str(entry[1]))
	row.add_child(_duel_zone)

	var challenge_btn := Button.new()
	challenge_btn.text = "Send Challenge"
	challenge_btn.pressed.connect(_on_challenge_pressed)
	duels.add_child(challenge_btn)

	_duel_status = Label.new()
	_duel_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	duels.add_child(_duel_status)

	duels.add_child(HSeparator.new())
	duels.add_child(_section_label("Incoming challenge"))
	_duel_pending = VBoxContainer.new()
	_duel_pending.add_theme_constant_override("separation", 6)
	duels.add_child(_duel_pending)

	duels.add_child(HSeparator.new())
	duels.add_child(_section_label("Recent rivals"))
	var recent_hint := Label.new()
	recent_hint.text = "The rival list remembers who shared your bouts. One click to a rematch."
	recent_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	recent_hint.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	duels.add_child(recent_hint)
	_recent_list = VBoxContainer.new()
	_recent_list.add_theme_constant_override("separation", 6)
	duels.add_child(_recent_list)


func _on_challenge_pressed() -> void:
	var svc = _lobby_service()
	if svc == null or _local_id == "":
		_duel_status.text = "The lobby hears nothing yet (no local player)."
		return
	var target: String = _duel_target.text.strip_edges()
	if target == "":
		_duel_status.text = "Name a player first."
		return
	var zone_entry: Array = BOUT_ZONES[_duel_zone.selected]
	var cid: String = svc.challenge_duel(_local_id, target, str(zone_entry[0]))
	_duel_status.text = "Challenge sent." if cid != "" else "Challenge blocked (one pending duel per player)."


# ---- Tab 3: LFG / LFM ---------------------------------------------------

func _setup_lfg_tab() -> void:
	var lfg := VBoxContainer.new()
	lfg.add_theme_constant_override("separation", 8)
	_tabs.add_child(lfg)
	_tabs.set_tab_title(2, " LFG ")

	var head := Label.new()
	head.text = "Looking for group, looking for more -- open-world crews included: grinding, hordes, dungeons, hunts."
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	lfg.add_child(head)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	lfg.add_child(row)
	row.add_child(_mk_label("Ad:"))
	_lfg_note = LineEdit.new()
	_lfg_note.placeholder_text = "Need 2 for the wolf hollow, lvl 10+"
	_lfg_note.custom_minimum_size = Vector2(240, 0)
	_lfg_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_lfg_note)
	row.add_child(_mk_label("Lvl"))
	_lfg_min = SpinBox.new()
	_lfg_min.min_value = 1
	_lfg_min.max_value = 999
	_lfg_min.value = 1
	row.add_child(_lfg_min)
	row.add_child(_mk_label("to"))
	_lfg_max = SpinBox.new()
	_lfg_max.min_value = 1
	_lfg_max.max_value = 999
	_lfg_max.value = 999
	row.add_child(_lfg_max)

	var post_btn := Button.new()
	post_btn.text = "Post / Update"
	post_btn.pressed.connect(_on_post_pressed)
	lfg.add_child(post_btn)

	_lfg_status = Label.new()
	_lfg_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lfg.add_child(_lfg_status)

	lfg.add_child(HSeparator.new())
	lfg.add_child(_section_label("Open posts"))
	_lfg_list = VBoxContainer.new()
	_lfg_list.add_theme_constant_override("separation", 6)
	lfg.add_child(_lfg_list)

	# People tab (S12 social): friends with ambient presence and
	# one-click actions -- the queue/bout/party books, joined.
	_setup_people_tab()


## Tab 4: People (friends + presence + actions).
func _setup_people_tab() -> void:
	var people := VBoxContainer.new()
	people.add_theme_constant_override("separation", 8)
	_tabs.add_child(people)
	_tabs.set_tab_title(3, " People ")

	var head := Label.new()
	head.text = "Your people, ambient: queued, in a bout, or out in the party wilds. Actions ride the consent paths."
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	people.add_child(head)

	_friends_list = VBoxContainer.new()
	_friends_list.add_theme_constant_override("separation", 6)
	people.add_child(_friends_list)


func _refresh_people() -> void:
	if _friends_list == null:
		return
	_clear_children(_friends_list)
	var svc = _lobby_service()
	if svc == null or not svc.has_method("get_friend_presence") or _local_id == "":
		return
	var rows: Array = svc.get_friend_presence(_local_id)
	if rows.is_empty():
		var idle := Label.new()
		idle.text = "No friends yet -- rivals met in bouts can be found in the Duels tab."
		idle.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
		_friends_list.add_child(idle)
		return
	for row_data in rows:
		_friends_list.add_child(_build_presence_row(svc, row_data))


func _build_presence_row(svc, p: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	lbl.text = "%s%s" % [str(p.get("player_name", "")), _presence_text(p)]
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not bool(p.get("online", false)):
		lbl.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	row.add_child(lbl)
	var fid: String = str(p.get("player_id", ""))
	var party_id: String = str(p.get("party_id", ""))
	var queue_zone: String = str(p.get("queue_zone", ""))
	if queue_zone != "":
		var jq := Button.new()
		jq.text = "Join queue"
		jq.pressed.connect(_on_join_queue_with.bind(fid, queue_zone))
		row.add_child(jq)
	elif party_id != "":
		var pj := Button.new()
		pj.text = "Ask to join"
		pj.pressed.connect(_on_petition_party.bind(party_id))
		row.add_child(pj)
	elif str(p.get("bout_instance_id", "")) != "":
		var spec := Button.new()
		spec.text = "Spectate"
		spec.disabled = true
		spec.tooltip_text = "Spectating arrives with the scene swap."
		row.add_child(spec)
	return row


func _presence_text(p: Dictionary) -> String:
	if not bool(p.get("online", false)):
		return " -- offline"
	if str(p.get("bout_instance_id", "")) != "":
		return " -- in a bout"
	if str(p.get("queue_zone", "")) != "":
		return " -- queued (%s)" % _zone_label(str(p.get("queue_zone")))
	if str(p.get("party_id", "")) != "":
		return " -- party of %d" % int(p.get("party_size", 1))
	if str(p.get("instance_zone_id", "")) != "":
		return " -- in an instance"
	return " -- online"


func _on_join_queue_with(_fid: String, zone_id: String) -> void:
	var svc = _lobby_service()
	if svc != null and _local_id != "":
		svc.leave_queue(_local_id)
		svc.join_queue(_local_id, _local_level(), zone_id, _queue_fill.button_pressed)


func _on_petition_party(party_id: String) -> void:
	var svc = _lobby_service()
	if svc != null and _local_id != "":
		svc.petition_party(party_id, _local_id)


func _on_post_pressed() -> void:
	var svc = _lobby_service()
	if svc == null or _local_id == "":
		_lfg_status.text = "The lobby hears nothing yet (no local player)."
		return
	var party_id: String = _local_party_id()
	var post_id: String = svc.post_lfg(party_id, _local_id, _lfg_note.text.strip_edges(), int(_lfg_min.value), int(_lfg_max.value))
	_lfg_status.text = "Ad posted (%s)." % post_id if post_id != "" else "Post blocked."


# ---- Refresh (rebuild feeds from service truth) --------------------------

func refresh() -> void:
	var svc = _lobby_service()
	if svc == null or _tabs == null:
		return
	if _local_id == "":
		_local_id = _resolve_local_id()
	_refresh_bouts(svc)
	_refresh_duels(svc)
	_refresh_lfg(svc)
	_refresh_people()


func _refresh_bouts(svc) -> void:
	var zone_id: String = str(BOUT_ZONES[_queue_zone.selected][0])
	var mine: String = svc.queue_for(_local_id)
	if mine != "":
		_queue_status.text = "Queued (%s)." % _zone_label(mine)
	elif _queue_status.text.begins_with("Queued"):
		_queue_status.text = ""
	_clear_children(_queue_feed)
	for entry in svc.queue_snapshot(zone_id):
		var row := Label.new()
		row.text = "%s  (x%d, lvl %d, waited %ds%s)" % [
			_short_id(str(entry.get("leader", ""))),
			int(entry.get("size", 1)),
			int(entry.get("level", 1)),
			int(entry.get("waited_seconds", 0.0)),
			", fill ok" if bool(entry.get("consent_fill", true)) else "",
		]
		row.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
		_queue_feed.add_child(row)


func _refresh_duels(svc) -> void:
	_clear_children(_duel_pending)
	_refresh_recent(svc)
	var pending: Dictionary = svc.pending_duel_for(_local_id) if _local_id != "" else {}
	if pending.is_empty():
		var idle := Label.new()
		idle.text = "No pending duels."
		idle.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
		_duel_pending.add_child(idle)
		return
	var incoming: bool = str(pending.get("to_id", "")) == _local_id
	var info := Label.new()
	info.text = "%s challenges you (%s)!" % [_short_id(str(pending.get("from_id", ""))), _zone_label(str(pending.get("zone_id", "")))] if incoming else "Waiting on %s..." % _short_id(str(pending.get("to_id", "")))
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_duel_pending.add_child(info)
	if not incoming:
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var accept := Button.new()
	accept.text = "Accept"
	var cid: String = str(pending.get("challenge_id", ""))
	accept.pressed.connect(_on_duel_accept.bind(cid))
	row.add_child(accept)
	var decline := Button.new()
	decline.text = "Decline"
	decline.pressed.connect(_on_duel_decline.bind(cid))
	row.add_child(decline)
	_duel_pending.add_child(row)


## The rival book: who shared your last bouts, one-click rematch.
func _refresh_recent(_svc) -> void:
	if _recent_list == null:
		return
	_clear_children(_recent_list)
	var recent = get_node_or_null("/root/RecentPlayersService")
	if recent == null or _local_id == "":
		return
	var entries: Array = recent.list_recent(_local_id, 5)
	if entries.is_empty():
		var idle := Label.new()
		idle.text = "No rivals yet. Finish a bout and they will be remembered."
		idle.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
		_recent_list.add_child(idle)
		return
	for i in range(entries.size()):
		var entry: Dictionary = entries[i]
		var fighters: Array = entry.get("fighters", [])
		if fighters.is_empty():
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var lbl := Label.new()
		lbl.text = "%s -- %s (%s)" % [
			_short_id(str(fighters[0])),
			_zone_label(str(entry.get("zone_id", ""))),
			str(entry.get("result", "loss")),
		]
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var rematch := Button.new()
		rematch.text = "Rematch"
		rematch.pressed.connect(_on_rematch.bind(i))
		row.add_child(rematch)
		_recent_list.add_child(row)


func _on_rematch(entry_index: int) -> void:
	var recent = get_node_or_null("/root/RecentPlayersService")
	if recent == null or _local_id == "":
		return
	var cid: String = str(recent.rematch_last(_local_id, entry_index))
	_duel_status.text = "Rematch sent." if cid != "" else "Rematch blocked (pending duel or throttle)."


func _refresh_lfg(svc) -> void:
	_clear_children(_lfg_list)
	var posts: Array = svc.list_lfg()
	if posts.is_empty():
		var idle := Label.new()
		idle.text = "No open posts. The wilds wait."
		idle.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
		_lfg_list.add_child(idle)
		return
	for post in posts:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var lbl := Label.new()
		lbl.text = "%s -- %s [lvl %d-%d, %d seats]" % [
			_short_id(str(post.get("leader_id", ""))),
			str(post.get("note", "")),
			int(post.get("level_min", 1)),
			int(post.get("level_max", 999)),
			int(post.get("open_seats", 0)),
		]
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var join := Button.new()
		join.text = "Ask to Join"
		var pid: String = str(post.get("post_id", ""))
		join.pressed.connect(_on_petition.bind(pid))
		row.add_child(join)
		_lfg_list.add_child(row)


func _on_panel_opened() -> void:
	_local_id = _player_id if _player_id != "" else _resolve_local_id()
	refresh()


func _on_duel_accept(cid: String) -> void:
	var svc = _lobby_service()
	if svc != null:
		svc.accept_duel(cid)
		refresh()


func _on_duel_decline(cid: String) -> void:
	var svc = _lobby_service()
	if svc != null:
		svc.decline_duel(cid)
		refresh()


func _on_petition(pid: String) -> void:
	var svc = _lobby_service()
	if svc != null and _local_id != "":
		svc.petition_lfg(pid, _local_id)


# ---- Helpers -------------------------------------------------------------

func _lobby_service():
	return get_node_or_null("/root/LobbyService")


func _local_level() -> int:
	var local = _local_player_node()
	if local != null and "level" in local:
		return int(local.level)
	return 1


func _local_party_id() -> String:
	if PartyService == null or _local_id == "":
		return ""
	var party: Dictionary = PartyService.get_player_party(_local_id)
	return str(party.get("id", ""))


func _local_player_node():
	var pm := get_node_or_null("/root/PlayerManager")
	if pm == null:
		return null
	var local = pm.get("local_player")
	if local == null or not is_instance_valid(local):
		return null
	return local


func _section_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	return l


func _mk_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _short_id(pid: String) -> String:
	if pid.length() <= 12:
		return pid
	return pid.substr(0, 9) + "..."


func _zone_label(zone_id: String) -> String:
	for entry in BOUT_ZONES:
		if str(entry[0]) == zone_id:
			return str(entry[1])
	return zone_id


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()
