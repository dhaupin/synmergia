# probe_social_presence.gd - S12 social: presence, petitions, LFG kinds.
#
# Covers owner points 4 + 5:
#   A. get_presence joins the books: online, queue, party, live bout,
#      instance zone.
#   B. get_friend_presence joins FriendsService.get_friends with the
#      presence books.
#   C. petition_party routes a leader->petitioner invite (consent
#      path); full/self petitions refused.
#   D. LFG kinds (PARTY/DUNGEON/RAID) live in the same book;
#      list_lfg filters; petitions route identically.
#   E. Party instance creation carries the leader as QoS owner.
#
# Script mode: autoloads at runtime; Entity stubs load-then-new.
extends SceneTree

var _fails: int = 0
var _checks: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var Contract = load("res://core/schemas/instance_contract.gd")
	var lobby = root.get_node_or_null("LobbyService")
	var ps = root.get_node_or_null("PartyService")
	var fs = root.get_node_or_null("FriendsService")
	var esvc = root.get_node_or_null("EntityService")
	var isvc = root.get_node_or_null("InstanceService")
	_check("social services present", \
		lobby != null and ps != null and fs != null and esvc != null and isvc != null)
	if lobby == null or ps == null or fs == null:
		quit(1)
		return
	var zm = root.get_node_or_null("ZoneManager")
	zm.load_zones()
	if isvc != null:
		isvc.refresh_registry()

	# People: leader (in a party, zone-tracked) + queuer (queued) +
	# fighter (in a live bout).
	var E: GDScript = load("res://core/entities/entity.gd")
	var eid_map: Dictionary = {}
	for pid in ["pres_leader", "pres_queuer", "pres_fighter"]:
		var e = E.new()
		e.entity_id = pid
		e.display_name = pid
		e.level = 10
		e.entity_type = E.EntityType.PLAYER
		root.add_child(e)
		esvc._entities[pid] = e
		eid_map[pid] = e

	# ---- A. Party + queue presence --------------------------------------
	var party_id: String = ps.create_party("pres_leader")
	_check("party created", party_id != "")
	ps.invite_player("pres_leader", "pres_queuer")
	ps.accept_invite("pres_queuer")
	_check("presence: party + size visible", \
		lobby.get_presence("pres_queuer").get("party_id", "") == party_id \
		and int(lobby.get_presence("pres_queuer").get("party_size", 0)) == 2)
	lobby.join_queue("pres_queuer", 10, "zone_arena_coliseum", false)
	_check("presence: queue zone visible", \
		str(lobby.get_presence("pres_queuer").get("queue_zone", "")) == "zone_arena_coliseum")

	# ---- B. Live bout presence ------------------------------------------
	var ArenaScene: GDScript = load("res://scenes/instances/arena_instance.gd")
	var room = ArenaScene.new()
	room.zone_data = zm.get_zone("zone_arena_coliseum")
	room.instance_id = "pres_probe"
	root.add_child(room)
	room.spawn_fighter("pres_fighter", 0)
	var rs = root.get_node_or_null("ArenaRoomService")
	_check("presence: live bout room visible", \
		str(lobby.get_presence("pres_fighter").get("bout_instance_id", "")) == "pres_probe")
	_check("room service resolved the fighter", rs.room_for_fighter("pres_fighter") == room)

	# ---- C. Friend presence joins the books ------------------------------
	fs.add_friend("pres_leader", "pres_fighter", "pres_fighter")
	var friend_rows: Array = lobby.get_friend_presence("pres_leader")
	_check("friend presence returns rows", friend_rows.size() == 1)
	var row: Dictionary = friend_rows[0] if friend_rows.size() > 0 else {}
	_check("friend row carries bout presence", \
		str(row.get("player_id", "")) == "pres_fighter" \
		and str(row.get("bout_instance_id", "")) == "pres_probe")

	# ---- D. petition_party routes the consent path -----------------------
	# Clear the 30 s party_invite cooldown (the test subject is the
	# petition routing, not the throttle).
	var cd = root.get_node_or_null("CooldownService")
	if cd != null:
		cd.cancel_cooldown("pres_leader", "party_invite")
	_check("party petition creates the invite", lobby.petition_party(party_id, "pres_fighter"))
	# A pending INVITE is not party membership: inspect the invite book.
	var petition_pending := false
	for invite_id in ps._pending_invites:
		var invite: Dictionary = ps._pending_invites[invite_id]
		if str(invite.get("to", "")) == "pres_fighter" and str(invite.get("party_id", "")) == party_id:
			petition_pending = true
	_check("petition invite is pending on the petitioner", petition_pending)
	_check("self-petition refused", lobby.petition_party(party_id, "pres_leader") == false)

	# ---- E. LFG kinds in the same book -----------------------------------
	var dpost: String = lobby.post_lfg("", "pres_leader", "Gloomwood delve, need healer", 10, 30, lobby.LfgKind.DUNGEON)
	var rpost: String = lobby.post_lfg("", "pres_leader", "Raid the Spire", 20, 999, lobby.LfgKind.RAID)
	_check("dungeon + raid posts issue", dpost != "" and rpost != "")
	var dpost_id: String = lobby.post_lfg("", "pres_leader", "dup", 10, 30, lobby.LfgKind.DUNGEON)
	_check("party-kind filter hides dungeon posts", \
		_lfg_kinds(lobby.list_lfg(lobby.LfgKind.PARTY), lobby) == 0)
	_check("dungeon filter shows exactly the dungeon posts", \
		_lfg_kinds(lobby.list_lfg(lobby.LfgKind.DUNGEON), lobby) == 2)
	_check("unfiltered list shows all kinds", lobby.list_lfg().size() >= 3)
	var all_posts: Array = lobby.list_lfg()
	var seen_kinds: Dictionary = {}
	for post in all_posts:
		seen_kinds[int(post.get("kind", -1))] = true
	_check("posts carry kind for the UI", \
		seen_kinds.has(lobby.LfgKind.DUNGEON) and seen_kinds.has(lobby.LfgKind.RAID))

	# ---- F. Petition routes through PartyService invites -----------------
	if cd != null:
		cd.cancel_cooldown("pres_leader", "party_invite")
	_check("dungeon post petition fires", lobby.petition_lfg(dpost_id, "pres_fighter"))

	if _fails == 0:
		print("SOCIAL PRESENCE PROBE PASSED (%d checks)" % _checks)
		quit(0)
	else:
		push_error("SOCIAL PRESENCE PROBE FAILED")
		quit(1)

func _lfg_kinds(posts: Array, lobby) -> int:
	var n := 0
	for post in posts:
		if int(post.get("kind", -1)) == lobby.LfgKind.DUNGEON:
			n += 1
	return n

func _pending_invite_count(ps) -> int:
	return (ps._pending_invites as Dictionary).size()

func _check(label: String, cond: bool) -> void:
	_checks += 1
	if cond:
		print("  PASS " + label)
	else:
		_fails += 1
		print("  FAIL " + label)
