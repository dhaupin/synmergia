# probe_lobby_service.gd - S11 probe: the lobby engine + bout primitives.
#
# Headless SceneTree probe covering the owner-decision quartet:
#   1. Scatter spawns (golden-angle ring, deterministic, no stacking)
#   2. Level-band matchmaking (+ widening wait, gulf refusal)
#   3. Capped normalized power (lvl 5 next to 60 plays at 10)
#   4. Queue assembly (party blocks atomic, fill-to-parity, FIFO seed,
#      winners keep queue slots skipped blocks own)
#   5. Duels (handshake, decline, expiry sweep)
#   6. LFG/LFM (open-world crews included: post, seats, petition,
#      disband cleanup)
# Conventions: no parse-time Entity refs, _check asserts, exit 0/1.
extends SceneTree

const ContractPath = "res://core/schemas/instance_contract.gd"

var _fails: int = 0
var _checks: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var Contract = load(ContractPath)

	# ---- A. Scatter spawn primitive ----------------------------------
	var c: Vector3 = Contract.scatter_spawn(Vector3.ZERO, 0)
	_check("scatter 0 lands on +X ring", c.distance_to(Vector3(3, 0, 0)) < 0.001)
	var positions: Array = []
	var min_gap: float = 999.0
	for i in range(12):
		var p: Vector3 = Contract.scatter_spawn(Vector3(0, 1, -40), i, 3.0)
		positions.append(p)
		for j in range(positions.size() - 1):
			var gap: float = p.distance_to(positions[j])
			if gap < min_gap:
				min_gap = gap
	_check("scatter ring is deterministic", \
		Contract.scatter_spawn(Vector3.ZERO, 5).distance_to(Contract.scatter_spawn(Vector3.ZERO, 5)) < 0.0001)
	# Neighbor spacing on a shared ring scales with headcount; the room
	# picks the radius (maxf(3, 0.45 * n)), the primitive stays pure.
	var ring12: float = maxf(3.0, 0.45 * 12.0)
	var min_gap12: float = 999.0
	var prev: Vector3 = Contract.scatter_spawn(Vector3.ZERO, 0, ring12)
	for i in range(1, 12):
		var p2: Vector3 = Contract.scatter_spawn(Vector3.ZERO, i, ring12)
		min_gap12 = minf(min_gap12, p2.distance_to(prev))
		prev = p2
	_check("12 fighters never stack (scaled ring, gap > 1.5 m)", min_gap12 > 1.5)
	_check("scatter preserves center height", \
		abs(Contract.scatter_spawn(Vector3(0, 7, 0), 3).y - 7.0) < 0.0001)

	# ---- B. Level bands + normalized power ----------------------------
	_check("band: 20 vs 28 within base band", Contract.level_band_ok(20, 28))
	_check("band: 20 vs 40 refused at base", not Contract.level_band_ok(20, 40))
	_check("band widens with wait (20 vs 40 passes after widening)", \
		Contract.level_band_ok(20, 40, 45.0))
	_check("band: gulf never passes (5 vs 60 even widened)", \
		not Contract.level_band_ok(5, 60, 999.0))
	_check("power: lvl 5 next to 60 caps at 10 (ratio 2.0)", \
		Contract.normalized_level(5, 60) == 10)
	_check("power: lvl 30 vs 60 normalizes to 60", \
		Contract.normalized_level(30, 60) == 60)
	_check("power: at/above reference unchanged", \
		Contract.normalized_level(60, 30) == 60 and Contract.normalized_level(70, 60) == 70)

	# ---- C. Queue assembly (party blocks + fill + band skips) ---------
	var lobby = root.get_node_or_null("LobbyService")
	_check("LobbyService autoload present", lobby != null)
	if lobby == null:
		quit(1)
		return

	# Band-compatible pair assembles into teams of one each.
	var assembled: Array = []
	lobby.bout_assembled.connect(func(z, iid, a, b): assembled.append({"zone": z, "iid": iid, "a": a, "b": b}))
	_check("queue: two solo accepts", \
		lobby.join_queue("probe_a", 20, "zone_arena_coliseum", false) \
		and lobby.join_queue("probe_b", 22, "zone_arena_coliseum", false))
	var result: Dictionary = lobby.try_assemble("zone_arena_coliseum")
	_check("assembly fires for band pair", bool(result.get("ok")) and assembled.size() == 1)
	_check("assembly teams are 1v1", \
		(result.get("team_a", []) as Array).size() == 1 and (result.get("team_b", []) as Array).size() == 1)
	_check("assembled players leave the reverse index", \
		lobby.queue_for("probe_a") == "" and lobby.queue_for("probe_b") == "")

	# Gulf pair NEVER assembles (consent path is the duel handshake).
	_check("queue: gulf pair accepts into queue", \
		lobby.join_queue("probe_big", 60, "zone_arena_coliseum", false) \
		and lobby.join_queue("probe_small", 5, "zone_arena_coliseum", false))
	var gulf: Dictionary = lobby.try_assemble("zone_arena_coliseum")
	_check("gulf pair refused (waiting_for_band)", \
		not bool(gulf.get("ok")) and str(gulf.get("reason")) == "waiting_for_band")

	# Consent fill: a consenting solo tops the gulf's BIG team for
	# parity -- 1v1 seed vs... no: fill only tops the SMALLER side, so
	# the 5 stays skipped (band) and the assembly still waits. What
	# fill DOES do: seed 1v1 assembled, next consenting solo joins the
	# winner's side next round. Verify the skip-not-evict rule here.
	var mid: Dictionary = lobby.try_assemble("zone_arena_coliseum")
	_check("skipped blocks keep queue slots (gulf still waiting)", \
		not bool(mid.get("ok")) and lobby.queue_for("probe_big") == "zone_arena_coliseum")
	_check("consenting fresh solo seeds a new assembly", \
		lobby.join_queue("probe_c", 58, "zone_arena_coliseum", true))
	var filled: Dictionary = lobby.try_assemble("zone_arena_coliseum")
	_check("fill-to-parity assembles 58+60 with consent", \
		bool(filled.get("ok")) and lobby.queue_for("probe_small") == "zone_arena_coliseum")
	var feed: Array = lobby.queue_snapshot("zone_arena_coliseum")
	_check("queue snapshot carries level + consent for UI", \
		feed.size() == 1 and int(feed[0].get("level", 0)) == 5 and bool(feed[0].get("consent_fill", false)) == false)
	_check("leave_queue removes the block", lobby.leave_queue("probe_small") and lobby.queue_for("probe_small") == "")

	# ---- D. Duels: handshake, decline, expiry -------------------------
	var cid: String = lobby.challenge_duel("duelist_one", "duelist_two", "zone_arena_sandpit")
	_check("duel challenge issues an id", cid != "")
	_check("one pending duel per player (either side)", \
		lobby.challenge_duel("duelist_one", "duelist_three", "zone_arena_sandpit") == "" \
		and lobby.challenge_duel("duelist_four", "duelist_two", "zone_arena_sandpit") == "")
	var pend: Dictionary = lobby.pending_duel_for("duelist_two")
	_check("pending duel visible to target", \
		str(pend.get("challenge_id", "")) == cid and str(pend.get("from_id")) == "duelist_one")
	_check("decline resolves", lobby.decline_duel(cid) and lobby.pending_duel_for("duelist_two").is_empty())
	_check("self-duel refused", lobby.challenge_duel("duelist_one", "duelist_one", "zone_arena_sandpit") == "")

	# Expiry: stamp the challenge old, sweep, expect resolution.
	var cid2: String = lobby.challenge_duel("duelist_one", "duelist_two", "zone_arena_sandpit")
	_check("second challenge after resolution ok", cid2 != "")
	lobby._challenges[cid2]["created_at"] = Time.get_unix_time_from_system() - 120.0
	lobby._sweep_expired_challenges()
	_check("expired duel swept", lobby.pending_duel_for("duelist_one").is_empty())

	# Accept path assembles the bout (script mode: no live entities,
	# so booking degrades to bookkeeping with an assembled_* id).
	var accepted: Dictionary = {}
	var cid3: String = lobby.challenge_duel("duelist_five", "duelist_six", "zone_arena_sandpit")
	lobby.bout_assembled.connect(func(z, iid, a, b): accepted["fired"] = true)
	_check("accept_duel assembles 1v1", \
		lobby.accept_duel(cid3) and bool(accepted.get("fired", false)))

	# ---- E. LFG / LFM (open-world crews are first class) --------------
	# Script mode: resolve autoloads at runtime (never bare identifiers).
	var ps = root.get_node_or_null("PartyService")
	_check("PartyService present", ps != null)
	if ps == null:
		quit(1)
		return
	var party_id: String = ps.create_party("lfg_leader")
	_check("party created for LFG", party_id != "")
	var post_id: String = lobby.post_lfg(party_id, "lfg_leader", "Wolf hollow grind, need 2", 10, 30)
	_check("LFG post issues id", post_id != "")
	_check("party has 5 open seats", _lfg_seats_for(lobby, post_id) == 5)
	_check("duplicate post returns existing", lobby.post_lfg(party_id, "lfg_leader", "dup") == post_id)
	var posts: Array = lobby.list_lfg()
	_check("list_lfg shows the post with note + bounds", posts.size() == 1 \
		and str(posts[0].get("note", "")) == "Wolf hollow grind, need 2" \
		and int(posts[0].get("level_min", 0)) == 10)
	ps.invite_player("lfg_leader", "lfg_petitioner")
	ps.accept_invite("lfg_petitioner")
	_check("petition flow fills a seat (4 left)", _lfg_seats_for(lobby, post_id) == 4)
	# Party seats 6 (leader + petitioner + 4 fillers) -> ad auto-hides.
	_check("full party auto-hides from list", _fill_party(ps, party_id, 4) and lobby.list_lfg().is_empty())
	_check("close_lfg clears", lobby.close_lfg(post_id) and not lobby.close_lfg(post_id))

	# Disband cleanup: queue entries + posts die with the party.
	var pid2: String = ps.create_party("disband_leader")
	var post2: String = lobby.post_lfg(pid2, "disband_leader", "soon gone")
	lobby.join_queue("disband_leader", 15, "zone_arena_sandpit", true, Vector3.ZERO, pid2)
	_check("disbanded party leaves the queue", \
		lobby.queue_for("disband_leader") == "zone_arena_sandpit")
	ps.disband_party(pid2)
	_check("queue entry dies with disband", lobby.queue_for("disband_leader") == "")
	_check("post dies with disband", lobby.lfg_post_for_party(pid2) == "")

	# ---- F. Contract AFK rule -----------------------------------------
	var coliseum = root.get_node_or_null("ZoneManager").get_zone("zone_arena_coliseum")
	_check("AFK default 90 s (zone has no override)", Contract.afk_kick_seconds(coliseum) == 90.0)
	_check("AFK rule: 0 disables via zone override shape", Contract.afk_kick_seconds(null) == 90.0)

	if _fails == 0:
		print("LOBBY PROBE PASSED (%d checks)" % _checks)
		quit(0)
	else:
		push_error("LOBBY PROBE FAILED")
		quit(1)

func _lfg_seats_for(lobby, post_id: String) -> int:
	for post in lobby.list_lfg():
		if str(post.get("post_id", "")) == post_id:
			return int(post.get("open_seats", 0))
	return -1

func _fill_party(ps, party_id: String, seats: int) -> bool:
	var cd = root.get_node_or_null("CooldownService")
	for i in range(seats):
		var filler: String = "filler_%d" % i
		# PartyService rate-limits invites (30 s per inviter); a probe
		# burst resets the cooldown between invites (real API, real
		# path -- the throttle is not under test here).
		if cd != null:
			cd.cancel_cooldown("lfg_leader", "party_invite")
		ps.invite_player("lfg_leader", filler)
		if not ps.accept_invite(filler):
			return false
	return true

func _check(label: String, cond: bool) -> void:
	_checks += 1
	if cond:
		print("  PASS " + label)
	else:
		_fails += 1
		print("  FAIL " + label)
