# probe_bout_host.gd - S12 golden path: the whole loop through the
# REAL services, no probe-driven room setup.
#
# Chain under test:
#   stone enqueue (LobbyService) -> try_assemble -> BoutHostService
#   hosts the room + seats LINKED fighters -> start -> bridge applies
#   power normalization -> CombatSystem-routed kill -> bout ends ->
#   payout (PlayerManager ledger) -> return map home to the stones.
#
# Owner clarifier under test: seats bind the LIVE entity (real level
# in the room's power book; no loaner forms -- stats restore after).
#
# Script mode: autoloads at runtime; Entity stubs load-then-new.
extends SceneTree

var _fails: int = 0
var _checks: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var Contract = load("res://core/schemas/instance_contract.gd")
	var ach = root.get_node_or_null("AchievementService")
	var zm = root.get_node_or_null("ZoneManager")
	var esvc = root.get_node_or_null("EntityService")
	var cs = root.get_node_or_null("CombatSystem")
	var lobby = root.get_node_or_null("LobbyService")
	var host = root.get_node_or_null("BoutHostService")
	var tele = root.get_node_or_null("BoutTeleportService")
	var room_svc = root.get_node_or_null("ArenaRoomService")
	var pm = root.get_node_or_null("PlayerManager")
	var bridge = root.get_node_or_null("ArenaCombatBridge")
	_check("all loop services present", \
		zm != null and esvc != null and cs != null and lobby != null \
		and host != null and tele != null and room_svc != null and pm != null \
		and bridge != null)
	if host == null or lobby == null or esvc == null or zm == null:
		quit(1)
		return
	zm.load_zones()

	# Two players at their stones (real Node3D stubs in the tree).
	var E: GDScript = load("res://core/entities/entity.gd")
	var p1 = E.new()
	p1.entity_id = "gold_p1"
	p1.display_name = "gold_p1"
	p1.level = 8
	p1.entity_type = E.EntityType.PLAYER
	p1.stats["strength"] = 12
	p1.stats["vitality"] = 12
	var p2 = E.new()
	p2.entity_id = "gold_p2"
	p2.display_name = "gold_p2"
	p2.level = 12
	p2.entity_type = E.EntityType.PLAYER
	p2.stats["strength"] = 12
	p2.stats["vitality"] = 12
	root.add_child(p1)
	root.add_child(p2)
	esvc._entities["gold_p1"] = p1
	esvc._entities["gold_p2"] = p2

	var stone_a: Vector3 = Vector3(14, 2.5, 0)
	var stone_b: Vector3 = Vector3(14, 2.5, 4)
	var base_strength: int = int(p1.stats["strength"])

	# ---- 1. Stone enqueue ---------------------------------------------
	_check("p1 queues at their stone", \
		lobby.join_queue("gold_p1", 8, "zone_arena_coliseum", false, stone_a))
	_check("p2 queues at their stone", \
		lobby.join_queue("gold_p2", 12, "zone_arena_coliseum", false, stone_b))

	# ---- 2. Assembly -> HOST (the keystone moment) ----------------------
	# Script-mode boot order: InstanceService built its zone registry
	# before load_zones() ran -- refresh it (the service's own seam).
	# Script-mode boot order: InstanceService built its zone registry
	# before load_zones() ran -- refresh it (the service's own seam).
	var isvc = root.get_node_or_null("InstanceService")
	if isvc != null:
		isvc.refresh_registry()
	var result: Dictionary = lobby.try_assemble("zone_arena_coliseum")
	if not bool(result.get("ok")):
		print("  DEBUG assembly reason: " + str(result.get("reason")))
	_check("assembly ok", bool(result.get("ok")))
	if not bool(result.get("ok")):
		quit(1)
		return
	var iid: String = str(result.get("instance_id"))
	_check("host took the booking", host.is_hosting(iid))
	var room = room_svc.room_by_id(iid)
	_check("host spawned a real room", room != null)
	_check("seats are LINKED (fighter id == entity id)", \
		room.has_fighter("gold_p1") and room.has_fighter("gold_p2"))
	_check("no loaner forms (real levels in the power book)", \
		int(room._levels.get("gold_p1", 0)) == 8 and int(room._levels.get("gold_p2", 0)) == 12)
	_check("origin stones carried into the room", \
		(room.origin_stones.get("gold_p1", Vector3.ZERO) as Vector3).distance_to(stone_a) < 0.01)

	# ---- 3. Teleport-in (BoutTeleportService on the same signal) --------
	var coliseum: Resource = zm.get_zone("zone_arena_coliseum")
	var spawns: Array = coliseum.spawn_points
	_check("p1 staged at team A ring", \
		(p1.global_position as Vector3).distance_to(Contract.scatter_spawn(spawns[0], 0)) < 0.01)
	_check("p2 staged at team B ring", \
		(p2.global_position as Vector3).distance_to(Contract.scatter_spawn(spawns[1], 0)) < 0.01)

	# ---- 4. Start (host start path) + power normalization ---------------
	host._start_if_live(iid)
	await process_frame
	await process_frame
	_check("bout started by the host", room.is_started())
	# p2 (lvl 12) is the reference; p1 (lvl 8) scales 12/8 = 1.5.
	_check("power normalization applied to the weaker fighter", \
		int(p1.stats["strength"]) == int(round(float(base_strength) * 1.5)) \
		and int(p2.stats["strength"]) == 12)

	# ---- 5. The kill (CombatSystem signal, bridge routes it) ------------
	var xp_before: int = int(pm.experience)
	var gold_before: int = int(pm.gold)
	cs.entity_died.emit(p2, p1)
	_check("bridged kill ends the bout", room.is_over())
	await process_frame

	# ---- 6. Payout (duck-typed progression ledger) -----------------------
	_check("payout landed on the ledger (120 win + 40 consolation)", \
		int(pm.experience) == xp_before + 160)
	_check("winner gold landed", int(pm.gold) == gold_before + 25)
	_check("host book released", not host.is_hosting(iid))
	await process_frame
	_check("room torn down", room_svc.room_by_id(iid) == null)

	# ---- 7. Home to the stones ------------------------------------------
	_check("p1 walked home to their stone", \
		(p1.global_position as Vector3).distance_to(stone_a) < 0.01)
	_check("p2 walked home to their stone", \
		(p2.global_position as Vector3).distance_to(stone_b) < 0.01)
	_check("stats restored after the bout (no permanent form)", \
		int(p1.stats["strength"]) == base_strength)

	# ---- 8. S12 hardening: clock + streaks ------------------------------
	# The clock: a trial room (AFK-exempt) still ends on its window.
	# start_bout stamps _bout_start_time, so the backdate lands after.
	var ArenaScene: GDScript = load("res://scenes/instances/arena_instance.gd")
	var clock_room = ArenaScene.new()
	clock_room.zone_data = coliseum
	clock_room.instance_id = "clock_probe"
	clock_room._trial = true
	root.add_child(clock_room)
	clock_room.spawn_fighter("clock_a", 0)
	clock_room.spawn_fighter("clock_b", 1)
	clock_room.start_bout()
	clock_room._bout_start_time = Time.get_unix_time_from_system() - 400.0
	await process_frame
	await process_frame
	_check("trial clock caps the bout (draw at -1)", clock_room.is_over())
	var draw_book: Dictionary = {"room": clock_room, "participants": ["clock_a", "clock_b"], "trial": true}
	host._pay_draw(draw_book)
	_check("draw pays consolation, not a win", int(pm.experience) >= 40)
	clock_room.queue_free()
	await process_frame

	# Streaks: TDM room (respawn keeps the bout alive), manual revive
	# between kills (the real timer will not wait out in headless).
	var sandpit: Resource = zm.get_zone("zone_arena_sandpit")
	var streak_room = ArenaScene.new()
	streak_room.zone_data = sandpit
	streak_room.instance_id = "streak_probe"
	root.add_child(streak_room)
	streak_room.spawn_fighter("streaker", 0)
	streak_room.spawn_fighter("victim", 1)
	streak_room.start_bout()
	for i in range(3):
		var victim_f = streak_room._fighters.get("victim")
		victim_f.alive = true
		victim_f.shielded_until = 0.0
		streak_room.report_death("victim", "streaker")
	_check("streak book counts 3", streak_room.best_streak_for("streaker") == 3)
	var streak_book: Dictionary = {"room": streak_room, "participants": ["streaker", "victim"]}
	host._credit_streak_achievements(streak_book)
	_check("kill_streak_3 unlocked via the tracker", \
		ach != null and bool(ach.has_unlocked("streaker", "kill_streak_3")))
	streak_room.queue_free()
	await process_frame

	# ---- 9. S12 hardening: QoS refusal paths ----------------------------
	# Instance creation is rate-limited (capacity 1 token at 0.05/s):
	# gold_p1 spent their token creating the coliseum instance in the
	# golden path, so a fresh-zone create is refused for them -- but
	# a fresh player still gets through (per-player buckets).
	var spammer2 = E.new()
	spammer2.entity_id = "qos_fresh"
	spammer2.display_name = "qos_fresh"
	spammer2.level = 5
	spammer2.entity_type = E.EntityType.PLAYER
	root.add_child(spammer2)
	esvc._entities["qos_fresh"] = spammer2
	var refused: Dictionary = isvc.join_instance(p1, "zone_arena_sandpit")
	var allowed: Dictionary = isvc.join_instance(spammer2, "zone_arena_sandpit")
	_check("instance create rate-limited for the spent owner", \
		not bool(refused.get("capacity_ok")) and str(refused.get("instance_id")) == "")
	_check("fresh owner still creates (per-player buckets)", bool(allowed.get("capacity_ok")))

	# Queue churn is rate-limited: after leaving, an immediate re-join
	# flood exhausts the party bucket -- the refusal is the LIMIT (the
	# player is NOT queued anymore, so a plain already-queued refusal
	# cannot explain it).
	lobby.leave_queue("gold_p1")
	for i in range(30):
		lobby.join_queue("gold_p1", 8, "zone_arena_coliseum", false, stone_a)
	_check("queue flood rate-limited (not queued, refused anyway)", \
		lobby.queue_for("gold_p1") == "")
	lobby.leave_queue("gold_p1")

	# Duel challenge spam is rate-limited (whisper bucket = 20/min =
	# 0.33/s; bucket capacity is maxf(1.0, rate) = 1 token). One
	# challenge lands, the flood stops until the bucket refills.
	var sent: int = 0
	for i in range(14):
		if lobby.challenge_duel("qos_dueler", "qos_target_%d" % i, "zone_arena_coliseum") != "":
			sent += 1
	_check("duel challenge flood capped by QoS (burst of 1)", sent == 1)

	if _fails == 0:
		print("BOUT HOST PROBE PASSED (%d checks)" % _checks)
		quit(0)
	else:
		push_error("BOUT HOST PROBE FAILED")
		quit(1)

func _check(label: String, cond: bool) -> void:
	_checks += 1
	if cond:
		print("  PASS " + label)
	else:
		_fails += 1
		print("  FAIL " + label)
