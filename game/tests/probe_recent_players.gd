# probe_recent_players.gd - S12: the rival book end to end.
#
# Chain under test:
#   hosted real bout (2 players) -> host records recent entries ->
#   each fighter's ring buffer holds the rival + zone + result ->
#   rematch_last sends a REAL duel challenge (LobbyService rules:
#   one-pending, QoS) -> trial bouts do NOT record -> ring cap 20 ->
#   privacy opt-out keeps a hidden player out of others' books.
extends SceneTree

var _fails: int = 0
var _checks: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var lobby = root.get_node_or_null("LobbyService")
	var host = root.get_node_or_null("BoutHostService")
	var recent = root.get_node_or_null("RecentPlayersService")
	var esvc = root.get_node_or_null("EntityService")
	_check("recent service + loop present", \
		recent != null and host != null and lobby != null and esvc != null)
	if recent == null or host == null or lobby == null:
		quit(1)
		return

	# ---- 1. Record through the REAL host path --------------------------
	# Two fighters finish a hosted coliseum bout; team 0 (rival_a) wins.
	var ArenaScene: GDScript = load("res://scenes/instances/arena_instance.gd")
	var zm = root.get_node_or_null("ZoneManager")
	zm.load_zones()
	var coliseum: Resource = zm.get_zone("zone_arena_coliseum")
	var isvc = root.get_node_or_null("InstanceService")
	if isvc != null:
		isvc.refresh_registry()
	var room = ArenaScene.new()
	room.zone_data = coliseum
	room.instance_id = "recent_probe"
	root.add_child(room)
	room.spawn_fighter("rival_a", 0)
	room.spawn_fighter("rival_b", 1)
	room.set_fighter_level("rival_a", 10)
	room.set_fighter_level("rival_b", 10)
	room.origin_stones = {"rival_a": Vector3(1, 1, 1), "rival_b": Vector3(2, 1, 2)}
	# The probe seats fighters directly; register the host book so the
	# ended path records the bout (production assembles via the host).
	host._hosted["recent_probe"] = {
		"zone_id": "zone_arena_coliseum", "room": room,
		"participants": ["rival_a", "rival_b"], "started": true,
	}
	# The host wires bout_ended in its assembly path; the probe seeds
	# the book directly, so bind the handler the same way here.
	room.bout_ended.connect(host._on_bout_ended.bind("recent_probe"))
	room.start_bout()
	room.report_death("rival_b", "rival_a")
	_check("bout resolved for the record", room.is_over())
	await process_frame
	await process_frame

	var book_a: Array = recent.list_recent("rival_a")
	_check("winner's book remembers the rival", book_a.size() >= 1 \
		and (book_a[0].get("fighters", []) as Array).has("rival_b"))
	_check("result recorded as a win", str(book_a[0].get("result", "")) == "win")
	_check("zone recorded for the rematch", \
		str(book_a[0].get("zone_id", "")) == "zone_arena_coliseum")
	var book_b: Array = recent.list_recent("rival_b")
	_check("loser's book remembers the rival as a loss", book_b.size() >= 1 \
		and str(book_b[0].get("result", "")) == "loss")

	# ---- 2. Rematch: one click, real duel handshake ---------------------
	var cid: String = recent.rematch_last("rival_b", 0)
	_check("rematch issues a real challenge id", cid != "")
	_check("challenge routed through LobbyService (one-pending)", \
		str(lobby.pending_duel_for("rival_a").get("challenge_id", "")) == cid)
	_check("decline clears so the next rematch can fly", \
		lobby.decline_duel(cid) and recent.rematch_last("rival_a", 0) != "")

	# ---- 3. Trial bouts never record ------------------------------------
	var book_before: int = recent.list_recent("rival_a").size()
	var dummy_book: Dictionary = {
		"zone_id": "zone_arena_coliseum", "room": null,
		"participants": ["rival_a"], "trial": true,
	}
	host._record_recent(0, dummy_book, "trial_check")
	_check("trial bouts leave the rival book alone", \
		recent.list_recent("rival_a").size() == book_before)

	# ---- 4. Ring cap + privacy ------------------------------------------
	for i in range(25):
		recent.record_entry_for("cap_test", {
			"fighters": ["rival_%d" % i], "zone_id": "zone_arena_coliseum",
			"mode": 0, "result": "win", "when": i,
		})
	_check("ring buffer capped at 20", recent.list_recent("cap_test").size() == 20)
	recent.set_recent_hidden("ghost", true)
	host._record_recent(0, {
		"zone_id": "zone_arena_coliseum", "room": null, "trial": false,
		"participants": ["rival_a", "ghost"],
	}, "ghost_check")
	_check("hidden player never lands in others' books", \
		(list_has_fighter(recent.list_recent("rival_a"), "ghost")) == false)

	if _fails == 0:
		print("RECENT PLAYERS PROBE PASSED (%d checks)" % _checks)
		quit(0)
	else:
		push_error("RECENT PLAYERS PROBE FAILED")
		quit(1)

func list_has_fighter(entries: Array, pid: String) -> bool:
	for entry in entries:
		if (entry.get("fighters", []) as Array).has(pid):
			return true
	return false

func _check(label: String, cond: bool) -> void:
	_checks += 1
	if cond:
		print("  PASS " + label)
	else:
		_fails += 1
		print("  FAIL " + label)
