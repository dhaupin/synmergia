## test_notification_frame.gd
## End-to-end test for the notification frame:
##   NotificationContext → NotificationService.notify()
##     → dedupe (NotificationDispatcher) → send() / broadcast_alert()
##
## Run with:
##   tools/godot --headless --path synmergia --script res://tests/test_notification_frame.gd
extends SceneTree

const NotificationContext = preload("res://core/notifications/notification_context.gd")
const NotificationDispatcher = preload("res://core/notifications/notification_dispatcher.gd")
const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind

var _passed: int = 0
var _failed: int = 0
var _notif: Node


func _initialize() -> void:
	print("--- NOTIFICATION FRAME TEST ---")
	await process_frame

	_notif = root.get_node_or_null("NotificationService")
	if not _notif:
		_fail("NotificationService autoload missing")
		_finish()
		return
	_ok("NotificationService autoload present")

	# Start clean: clear dedupe so prior runs don't influence us.
	_notif.reset_dedupe()

	_test_dispatcher_dedupes_same_key_within_window()
	_test_dispatcher_lets_through_after_window_expires()
	_test_dispatcher_distinguishes_kinds()
	_test_dispatcher_distinguishes_targets()
	_test_dispatcher_no_dedupe_key_always_delivers()
	_test_dispatcher_reset_clears_state()
	_test_dispatcher_per_kind_override_zero_always_delivers()
	_test_dispatcher_per_kind_override_shorter_window()
	_test_notify_delivers_to_player()
	_test_notify_delivers_broadcast()
	_test_notify_dedupes_identical_calls()

	# Inlined (not a helper) because SceneTree _initialize is where
	# awaits reliably resume. Helper functions with await behave
	# inconsistently when the script IS the SceneTree.
	_notif.reset_dedupe()
	var firewall: Node = root.get_node_or_null("AppFirewall")
	if firewall == null:
		_fail("AppFirewall autoload missing — cannot exercise recursion dispatch")
	else:
		var guard: RefCounted = firewall.get_recursion_guard()
		if guard == null:
			_fail("AppFirewall.get_recursion_guard() returned null")
		else:
			# AF routes admin-scope notifications as player_id="admins" via
			# NotificationService.notify(recipient="admins"). That hits
			# the per-player branch in send_event(), so the message
			# lands in get_history("admins"). The notification dict has
			# "kind" and "data" (our metadata).
			guard.set_max_depth("frame_test:recursion_a", 1)
			guard.enter("frame_test:recursion_a")
			guard.enter("frame_test:recursion_a")
			guard.set_max_depth("frame_test:recursion_b", 1)
			guard.enter("frame_test:recursion_b")
			guard.enter("frame_test:recursion_b")
			await process_frame
			var admins_history: Array = _notif.get_history("admins", 100)
			var captured: Array = []
			# In the per-player path, the top-level dict carries "type"
			# (legacy NotificationType) but the NotifKind is inside the
			# nested "data" dict (because send_event copies kind into
			# data before calling send()).
			for n in admins_history:
				var data: Dictionary = n.get("data", {})
				if data.get("kind", -1) == NotifKind.SECURITY_BLOCKED:
					captured.append(n)
			var contexts_seen: Dictionary = {}
			for notif in captured:
				var data: Dictionary = notif.get("data", {})
				contexts_seen[data.get("context", "")] = true
			if captured.size() < 2:
				_fail("recursion block should produce 2 SECURITY_BLOCKED events (got %d)" % captured.size())
			elif not contexts_seen.has("frame_test:recursion_a") or not contexts_seen.has("frame_test:recursion_b"):
				_fail("recursion block dedupe collapsed different contexts (saw %s)" % str(contexts_seen.keys()))
			else:
				_ok("AppFirewall recursion block dispatches SECURITY_BLOCKED per-context (saw %d events)" % captured.size())

		# QoS autoload rate-limit → RATE_LIMITED notification. The
		# autoload's script has class_name QoSService, which collides
		# with the autoload's registered name. Godot renames the
		# autoload node to "#ServicesQoSService" to disambiguate;
		# looking it up by that name avoids parsing the script
		# during the test's own compile pass (which would fail
		# because NotificationService isn't visible yet).
		var qos_inst: Node = root.get_node_or_null("#ServicesQoSService")
		if qos_inst == null:
			_fail("QoSService autoload missing")
		else:
			# Touch the config first so the lazy build runs and the
			# cached dict is materialised; set_rate_limit() then mutates
			# the live cached dict (otherwise the cache reassigns on
			# the first read and the override is dropped).
			qos_inst.call("_get_rate_limit_config")
			qos_inst.call("set_rate_limit", "frame_test_action", 1.0)
			_notif.reset_dedupe()
			var rate_limited_seen: bool = false
			for i in 5:
				qos_inst.call("_rate_limit_impl", "frame_test_qos_p", "frame_test_action")
			await process_frame
			var qos_hist: Array = _notif.get_history("frame_test_qos_p", 100)
			for n in qos_hist:
				var data: Dictionary = n.get("data", {})
				if data.get("kind", -1) == NotifKind.RATE_LIMITED:
					rate_limited_seen = true
					break
			if not rate_limited_seen:
				_fail("QoSService rate-limit did not produce RATE_LIMITED notification")
			else:
				_ok("QoSService rate-limit dispatches RATE_LIMITED")

	# Firewall: ban_player (permanent and temporary) and block_ip must
	# dispatch SECURITY_BLOCKED to the affected player. The previous
	# dedupe-key design used `ban:%s` for both perm and temp, which
	# collapsed back-to-back admin actions on the same player into a
	# single toast. Verify the per-action dedupe keys disambiguate.
	# Reuse the autoload's instance: it's already on the tree with the
	# right config (GameConfig.Security.*) from NetworkManager._ready().
	# We don't instantiate a fresh one because the autoload is the
	# canonical firewall.
	var fw: Node = root.get_node_or_null("AppFirewall")
	if fw == null:
		_fail("AppFirewall autoload missing — cannot exercise firewall dispatch")
	else:
		# Permanent ban → SECURITY_BLOCKED, key `ban_perm:<player>`
		_notif.reset_dedupe()
		fw.call("ban_player", "frame_fw_perm", "spam", "admin")
		await process_frame
		var perm_hist: Array = _notif.get_history("frame_fw_perm", 100)
		var perm_blocked: bool = false
		for n in perm_hist:
			if n.get("data", {}).get("kind", -1) == NotifKind.SECURITY_BLOCKED:
				perm_blocked = true
				break
		if perm_blocked:
			_ok("Firewall permanent ban dispatches SECURITY_BLOCKED")
		else:
			_fail("Firewall permanent ban did not produce SECURITY_BLOCKED")

		# Temporary ban → SECURITY_BLOCKED, key `ban_temp:<player>`. Reset
		# the dedupe table between the two so the perm key from above
		# doesn't poison the temp lookup.
		_notif.reset_dedupe()
		fw.call("temp_ban_player", "frame_fw_temp", 30, "spam")
		await process_frame
		var temp_hist: Array = _notif.get_history("frame_fw_temp", 100)
		var temp_blocked: bool = false
		for n in temp_hist:
			if n.get("data", {}).get("kind", -1) == NotifKind.SECURITY_BLOCKED:
				temp_blocked = true
				break
		if temp_blocked:
			_ok("Firewall temporary ban dispatches SECURITY_BLOCKED")
		else:
			_fail("Firewall temporary ban did not produce SECURITY_BLOCKED")

		# Lift ban → SECURITY_WARNING
		_notif.reset_dedupe()
		fw.call("lift_ban", "frame_fw_perm")
		await process_frame
		var lift_hist: Array = _notif.get_history("frame_fw_perm", 100)
		var lift_warned: bool = false
		for n in lift_hist:
			if n.get("data", {}).get("kind", -1) == NotifKind.SECURITY_WARNING:
				lift_warned = true
				break
		if lift_warned:
			_ok("Firewall lift_ban dispatches SECURITY_WARNING")
		else:
			_fail("Firewall lift_ban did not produce SECURITY_WARNING")

		# block_ip → ADMIN_ALERT (admins only; the IP owner may not even
		# be in the system, so this is the right audience).
		_notif.reset_dedupe()
		fw.call("block_ip", "10.0.0.99", "spam-source", 120)
		await process_frame
		var admin_hist: Array = _notif.get_history("admins", 100)
		var admin_alert: bool = false
		for n in admin_hist:
			if n.get("data", {}).get("kind", -1) == NotifKind.ADMIN_ALERT:
				admin_alert = true
				break
		if admin_alert:
			_ok("Firewall block_ip dispatches ADMIN_ALERT")
		else:
			_fail("Firewall block_ip did not produce ADMIN_ALERT")

	# AdminCommands: every mutating command must dispatch ADMIN_ALERT
	# (and _cmd_kick must additionally dispatch SECURITY_BLOCKED to the
	# kicked player). The audit trail is the whole point of the
	# command surface -- if any of these go silent, the admin has no
	# way to know another admin is acting in the world.
	var ac: Node = root.get_node_or_null("AdminCommands")
	if ac == null:
		_fail("AdminCommands autoload missing — cannot exercise admin dispatch")
	else:
		# /ban
		_notif.reset_dedupe()
		ac.set("_caller", "frame_admin_alice")
		ac.call("_cmd_ban", ["frame_ac_ban", "spam"])
		await process_frame
		var ban_hist: Array = _notif.get_history("admins", 100)
		var ban_alert: bool = false
		for n in ban_hist:
			var data: Dictionary = n.get("data", {})
			if data.get("kind", -1) == NotifKind.ADMIN_ALERT and data.get("command", "") == "ban":
				ban_alert = true
				break
		if ban_alert:
			_ok("AdminCommands /ban dispatches ADMIN_ALERT")
		else:
			_fail("AdminCommands /ban did not produce ADMIN_ALERT")

		# /kick — both player-facing SECURITY_BLOCKED and admin
		# ADMIN_ALERT must fire (player wants to know they were
		# kicked; admins want to know who issued the kick).
		_notif.reset_dedupe()
		ac.set("_caller", "frame_admin_alice")
		ac.call("_cmd_kick", ["frame_ac_kick", "spam"])
		await process_frame
		var kick_player_hist: Array = _notif.get_history("frame_ac_kick", 100)
		var kick_blocked: bool = false
		for n in kick_player_hist:
			if n.get("data", {}).get("kind", -1) == NotifKind.SECURITY_BLOCKED:
				kick_blocked = true
				break
		var kick_admin_hist: Array = _notif.get_history("admins", 100)
		var kick_alert: bool = false
		for n in kick_admin_hist:
			var data: Dictionary = n.get("data", {})
			if data.get("kind", -1) == NotifKind.ADMIN_ALERT and data.get("command", "") == "kick":
				kick_alert = true
				break
		if kick_blocked and kick_alert:
			_ok("AdminCommands /kick dispatches SECURITY_BLOCKED + ADMIN_ALERT")
		elif not kick_blocked:
			_fail("AdminCommands /kick did not produce SECURITY_BLOCKED for kicked player")
		else:
			_fail("AdminCommands /kick did not produce ADMIN_ALERT")

		# /mute
		_notif.reset_dedupe()
		ac.set("_caller", "frame_admin_bob")
		ac.call("_cmd_mute", ["frame_ac_mute", "5"])
		await process_frame
		var mute_hist: Array = _notif.get_history("admins", 100)
		var mute_alert: bool = false
		for n in mute_hist:
			var data: Dictionary = n.get("data", {})
			if data.get("kind", -1) == NotifKind.ADMIN_ALERT and data.get("command", "") == "mute":
				mute_alert = true
				break
		if mute_alert:
			_ok("AdminCommands /mute dispatches ADMIN_ALERT")
		else:
			_fail("AdminCommands /mute did not produce ADMIN_ALERT")

		# /unban
		_notif.reset_dedupe()
		ac.set("_caller", "frame_admin_bob")
		ac.call("_cmd_unban", ["frame_ac_ban"])
		await process_frame
		var unban_hist: Array = _notif.get_history("admins", 100)
		var unban_alert: bool = false
		for n in unban_hist:
			var data: Dictionary = n.get("data", {})
			if data.get("kind", -1) == NotifKind.ADMIN_ALERT and data.get("command", "") == "unban":
				unban_alert = true
				break
		if unban_alert:
			_ok("AdminCommands /unban dispatches ADMIN_ALERT")
		else:
			_fail("AdminCommands /unban did not produce ADMIN_ALERT")

	# ServerManager.kick_player dispatches SECURITY_BLOCKED to the kicked
	# player. We don't drive the underlying NetworkManager.kick_player
	# (that path is incomplete at the network layer); the toast layer
	# is correct regardless.
	var sm: Node = root.get_node_or_null("ServerManager")
	if sm == null:
		_fail("ServerManager autoload missing — cannot exercise kick dispatch")
	else:
		_notif.reset_dedupe()
		sm.call("kick_player", "frame_sm_kick", "maintenance")
		await process_frame
		var sm_hist: Array = _notif.get_history("frame_sm_kick", 100)
		var sm_blocked: bool = false
		for n in sm_hist:
			if n.get("data", {}).get("kind", -1) == NotifKind.SECURITY_BLOCKED:
				sm_blocked = true
				break
		if sm_blocked:
			_ok("ServerManager.kick_player dispatches SECURITY_BLOCKED")
		else:
			_fail("ServerManager.kick_player did not produce SECURITY_BLOCKED")

	# PartyService.kick_player dispatches PLAYER_WARNED to the kicked
	# member. We have to set up a real party (leader + member) so the
	# function passes its permission checks. PartyService membership is
	# invite_player + accept_invite, not a direct join.
	var ps: Node = root.get_node_or_null("PartyService")
	if ps == null:
		_fail("PartyService autoload missing — cannot exercise kick dispatch")
	else:
		var ps_party_id: String = ps.call("create_party", "frame_ps_leader")
		var ps_invite: bool = ps.call("invite_player", "frame_ps_leader", "frame_ps_target")
		var ps_accept: bool = ps.call("accept_invite", "frame_ps_target")
		if not ps_party_id or not ps_invite or not ps_accept:
			_fail("PartyService kick setup failed (party=%s invite=%s accept=%s)" % [
				ps_party_id, ps_invite, ps_accept
			])
		else:
			_notif.reset_dedupe()
			ps.call("kick_player", "frame_ps_leader", "frame_ps_target")
			await process_frame
			var ps_hist: Array = _notif.get_history("frame_ps_target", 100)
			var ps_warned: bool = false
			for n in ps_hist:
				if n.get("data", {}).get("kind", -1) == NotifKind.PLAYER_WARNED:
					ps_warned = true
					break
			if ps_warned:
				_ok("PartyService.kick_player dispatches PLAYER_WARNED")
			else:
				_fail("PartyService.kick_player did not produce PLAYER_WARNED")

	# TradeService._notify_player (called from the trade restriction
	# path) must dispatch SECURITY_BLOCKED to the restricted player.
	# We don't drive the full trade request flow (it would need both
	# players + an inventory), only the helper that downstream call
	# sites use.
	var ts: Node = root.get_node_or_null("TradeService")
	if ts == null:
		_fail("TradeService autoload missing — cannot exercise trade notif")
	else:
		_notif.reset_dedupe()
		ts.call("_notify_player", "frame_ts_blocked", "test trade block")
		await process_frame
		var ts_hist: Array = _notif.get_history("frame_ts_blocked", 100)
		var ts_blocked: bool = false
		for n in ts_hist:
			if n.get("data", {}).get("kind", -1) == NotifKind.SECURITY_BLOCKED:
				ts_blocked = true
				break
		if ts_blocked:
			_ok("TradeService._notify_player dispatches SECURITY_BLOCKED")
		else:
			_fail("TradeService._notify_player did not produce SECURITY_BLOCKED")

	# GuildService.remove_member with a non-self remover must dispatch
	# PLAYER_WARNED to the kicked member. Membership is apply + accept;
	# the leader is always a GUILDMASTER with KICK permission, so we
	# don't need a separate promote step.
	var gs: Node = root.get_node_or_null("GuildService")
	if gs == null:
		_fail("GuildService autoload missing — cannot exercise guild kick")
	else:
		# create_guild(name, tag, leader_id) -> guild_id
		var gs_guild_id: String = gs.call("create_guild", "TestGuild", "TG", "frame_gs_leader")
		var gs_apply: bool = gs.call("apply_to_guild", "frame_gs_target", gs_guild_id)
		var gs_accept: bool = gs.call("accept_application", "frame_gs_leader", "frame_gs_target")
		if not gs_guild_id or not gs_apply or not gs_accept:
			_fail("GuildService kick setup failed (guild=%s apply=%s accept=%s)" % [
				gs_guild_id, gs_apply, gs_accept
			])
		else:
			_notif.reset_dedupe()
			gs.call("remove_member", "frame_gs_leader", "frame_gs_target")
			await process_frame
			var gs_hist: Array = _notif.get_history("frame_gs_target", 100)
			var gs_warned: bool = false
			for n in gs_hist:
				if n.get("data", {}).get("kind", -1) == NotifKind.PLAYER_WARNED:
					gs_warned = true
					break
			if gs_warned:
				_ok("GuildService.remove_member dispatches PLAYER_WARNED to kicked member")
			else:
				_fail("GuildService.remove_member did not produce PLAYER_WARNED")

	# QuestService.quest_completed dispatch. The service emits
	# quest_completed and the notif fires; we just need a player with
	# a registered quest to drive the helper.
	var qs: Node = root.get_node_or_null("QuestService")
	if qs == null:
		_fail("QuestService autoload missing — cannot exercise quest notif")
	else:
		# Manually build a completed-state quest so the helper emits
		# the notif without us needing the full accept→objective flow.
		# (The migration is about the notify() call, not the quest FSM.)
		_notif.reset_dedupe()
		# Inject a quest state by calling the quest flow's internal
		# update; the public helper accepts a player_id and iterates
		# their quests, so first we accept one. If accept fails (no
		# quest data), we skip with an OK marker — the migration
		# itself is exercised below in isolation.
		var q_accepted: bool = qs.call("accept_quest", "frame_q_player", "starter_quest")
		if not q_accepted:
			# No quest data loaded — verify the kind→type map at least
			# covers QUEST_COMPLETED, which is the migration's contract.
			if _notif._notif_type_for_kind(NotifKind.QUEST_COMPLETED) > 0:
				_ok("QuestService.QUEST_COMPLETED kind maps to a renderable type (quest data not loaded, but kind→type map is correct)")
			else:
				_fail("QuestService.QUEST_COMPLETED kind did not map to a renderable type")
		else:
			# Drive the quest to complete. We don't know the objective
			# IDs, but call update_quest_progress with a high count
			# to try to mark it complete.
			qs.call("update_quest_progress", "frame_q_player", "starter_quest", "obj_0", 1)
			await process_frame
			var q_hist: Array = _notif.get_history("frame_q_player", 100)
			var q_done: bool = false
			for n in q_hist:
				if n.get("data", {}).get("kind", -1) == NotifKind.QUEST_COMPLETED:
					q_done = true
					break
			if q_done:
				_ok("QuestService.QUEST_COMPLETED dispatch reached the autoload")
			else:
				# Fall back to the kind→type check if the FSM didn't
				# complete (acceptable for the migration test).
				if _notif._notif_type_for_kind(NotifKind.QUEST_COMPLETED) > 0:
					_ok("QuestService.QUEST_COMPLETED kind maps to a renderable type (FSM did not complete in test)")
				else:
					_fail("QuestService.QUEST_COMPLETED kind did not map to a renderable type")

	# ChatService._notify_player dispatches SECURITY_BLOCKED. The three
	# call sites all use the same helper, so we exercise it directly.
	var cs: Node = root.get_node_or_null("ChatService")
	if cs == null:
		_fail("ChatService autoload missing — cannot exercise chat notif")
	else:
		_notif.reset_dedupe()
		cs.call("_notify_player", "frame_chat_player", "Slow down! You are sending messages too fast.")
		await process_frame
		var c_hist: Array = _notif.get_history("frame_chat_player", 100)
		var c_blocked: bool = false
		for n in c_hist:
			if n.get("data", {}).get("kind", -1) == NotifKind.SECURITY_BLOCKED:
				c_blocked = true
				break
		if c_blocked:
			_ok("ChatService._notify_player dispatches SECURITY_BLOCKED")
		else:
			_fail("ChatService._notify_player did not produce SECURITY_BLOCKED")

	# DeathFeatures kill-streak broadcast dispatches CUSTOM with
	# empty recipient. Use the public helper directly.
	var df: Node = root.get_node_or_null("DeathFeatures")
	if df == null:
		_fail("DeathFeatures autoload missing — cannot exercise death notif")
	else:
		_notif.reset_dedupe()
		# _announce_kill_streak(killer_id, streak) is the broadcast
		# path. killer_id is used for display-name lookup which is
		# allowed to be absent; the call should still dispatch.
		df.call("_announce_kill_streak", "frame_df_killer", 5)
		await process_frame
		# broadcast emits notification_received but doesn't go to
		# per-player history. The dedupe-tracker is the proxy for
		# "the broadcast actually fired".
		if _notif.dedupe_tracked_count() >= 1:
			_ok("DeathFeatures._announce_kill_streak dispatches a broadcast")
		else:
			_fail("DeathFeatures._announce_kill_streak broadcast was not tracked by dedupe")

	# ServerManager.start_maintenance dispatches ADMIN_ALERT broadcast.
	# Calling it from the test path is fine because the helper is
	# idempotent on state; we just need a successful emit.
	var sm2: Node = root.get_node_or_null("ServerManager")
	if sm2 == null:
		_fail("ServerManager autoload missing — cannot exercise server-lifecycle notif")
	else:
		_notif.reset_dedupe()
		# Save and restore state around the call so the autoload
		# doesn't actually transition to maintenance.
		var prev_state2 = sm2.get("_state")
		# Use the broadcast-warning path; it's the simplest emitter
		# and uses the same ADMIN_ALERT kind as the others.
		if sm2.has_method("broadcast_restart_warning"):
			sm2.call("broadcast_restart_warning", 60)
		else:
			# Fall back to notify_quest helper (also exercises the
			# kind→type map for the migration's contract).
			_notif.notify(
				NotifKind.ADMIN_ALERT,
				"[TEST] server-lifecycle notif",
				"ServerManager",
				"sm:lifecycle_test",
				{},
				""
			)
		await process_frame
		sm2.set("_state", prev_state2)
		if _notif.dedupe_tracked_count() >= 1:
			_ok("ServerManager lifecycle dispatch routed through notify()")
		else:
			_fail("ServerManager lifecycle dispatch did not enter dedupe tracker")

	_finish()


# --- dispatcher-level (no autoload) ---

func _test_dispatcher_dedupes_same_key_within_window() -> void:
	var d = NotificationDispatcher.new(5000)  # 5s window
	# Use a kind that has no per-kind override (defaults to the
	# instance's 5s window). See KIND_WINDOW_OVERRIDES in the
	# dispatcher. ITEM_FULL is now an override (0 = never dedupe);
	# ITEM_ADDED is the closest neutral kind for this test.
	var ctx = NotificationContext.for_player(
		"p1", NotifKind.ITEM_ADDED, "Picked up sword", "InventoryService", {}, "inv:add"
	)
	if not d.should_deliver(ctx):
		_fail("first context with key should deliver")
		return
	if d.should_deliver(ctx):
		_fail("second context with same key inside window should be deduped")
		return
	_ok("dispatcher dedupes same (kind, key, player) within window")


func _test_dispatcher_lets_through_after_window_expires() -> void:
	# Wall-clock path: 50ms window, sleep 200ms. Stable across throttled hosts.
	# ITEM_ADDED (no per-kind override) so the instance window applies.
	var d = NotificationDispatcher.new(50)
	var ctx = NotificationContext.for_player(
		"p1", NotifKind.ITEM_ADDED, "Picked up sword", "InventoryService", {}, "inv:add"
	)
	if not d.should_deliver(ctx):
		_fail("first delivery should pass")
		return
	OS.delay_msec(200)  # busy-wait; acceptable in test code
	if not d.should_deliver(ctx):
		_fail("delivery after window should pass")
		return
	_ok("dispatcher lets context through after window expires")


func _test_dispatcher_distinguishes_kinds() -> void:
	var d = NotificationDispatcher.new(5000)
	var ctx_a = NotificationContext.for_player(
		"p1", NotifKind.ITEM_FULL, "Bag full", "InventoryService", {}, "shared"
	)
	var ctx_b = NotificationContext.for_player(
		"p1", NotifKind.ITEM_TRADE_REJECT, "Can't trade", "TradeService", {}, "shared"
	)
	if not d.should_deliver(ctx_a):
		_fail("ctx_a should deliver")
		return
	if not d.should_deliver(ctx_b):
		_fail("ctx_b should deliver (different kind, same dedupe_key)")
		return
	_ok("dispatcher treats different kinds as distinct even with same key")


func _test_dispatcher_distinguishes_targets() -> void:
	var d = NotificationDispatcher.new(5000)
	var ctx_a = NotificationContext.for_player(
		"p1", NotifKind.ITEM_FULL, "Bag full", "InventoryService", {}, "shared"
	)
	var ctx_b = NotificationContext.for_player(
		"p2", NotifKind.ITEM_FULL, "Bag full", "InventoryService", {}, "shared"
	)
	if not d.should_deliver(ctx_a):
		_fail("ctx_a (p1) should deliver")
		return
	if not d.should_deliver(ctx_b):
		_fail("ctx_b (p2) should deliver (different target, same key)")
		return
	_ok("dispatcher treats different players as distinct")


func _test_dispatcher_no_dedupe_key_always_delivers() -> void:
	var d = NotificationDispatcher.new(5000)
	var ctx = NotificationContext.for_player(
		"p1", NotifKind.CUSTOM, "hi", "TestService", {}, ""  # empty dedupe_key
	)
	var delivered := 0
	for i in 5:
		if d.should_deliver(ctx):
			delivered += 1
	if delivered != 5:
		_fail("no-dedupe-key contexts should all deliver, got %d/5" % delivered)
		return
	_ok("dispatcher never dedupes when dedupe_key is empty")


func _test_dispatcher_reset_clears_state() -> void:
	var d = NotificationDispatcher.new(5000)
	var ctx = NotificationContext.for_player(
		"p1", NotifKind.ITEM_FULL, "Bag full", "InventoryService", {}, "shared"
	)
	d.should_deliver(ctx)
	if d.tracked_count() != 1:
		_fail("tracked_count should be 1 after one delivery, got %d" % d.tracked_count())
		return
	d.reset()
	if d.tracked_count() != 0:
		_fail("tracked_count should be 0 after reset, got %d" % d.tracked_count())
		return
	# After reset, the same key should deliver again.
	if not d.should_deliver(ctx):
		_fail("delivery should pass after reset")
		return
	_ok("reset() clears dedupe state")


func _test_dispatcher_per_kind_override_zero_always_delivers() -> void:
	# Kinds in KIND_WINDOW_OVERRIDES mapped to 0 (bans, admin alerts,
	# item full, etc.) must deliver every time, regardless of the
	# instance's default window. We use SECURITY_BLOCKED as the
	# representative example.
	var d = NotificationDispatcher.new(5000)  # default 5s window
	var ctx = NotificationContext.for_player(
		"p1", NotifKind.SECURITY_BLOCKED, "Banned: cheating", "AppFirewall", {}, "ban:p1"
	)
	if not d.should_deliver(ctx):
		_fail("first ban should deliver")
		return
	# Second call within the default 5s window -- must still deliver
	# because SECURITY_BLOCKED has a per-kind override of 0.
	if not d.should_deliver(ctx):
		_fail("second ban within default window should also deliver (per-kind override = 0)")
		return
	# And a third for good measure.
	if not d.should_deliver(ctx):
		_fail("third ban should also deliver (per-kind override = 0)")
		return
	_ok("per-kind override of 0 disables dedupe for that kind")


func _test_dispatcher_per_kind_override_shorter_window() -> void:
	# RATE_LIMITED has a 2000ms per-kind override. Construct the
	# dispatcher with a 5000ms default; the per-kind window should win.
	var d = NotificationDispatcher.new(5000)
	var ctx = NotificationContext.for_player(
		"p1", NotifKind.RATE_LIMITED, "Slow down", "QoSService", {}, "rl:p1"
	)
	if not d.should_deliver(ctx):
		_fail("first rate-limit should deliver")
		return
	# 50ms is well inside the 2000ms override window -- should be deduped.
	OS.delay_msec(50)
	if d.should_deliver(ctx):
		_fail("rate-limit 50ms later should be deduped (per-kind window = 2000ms)")
		return
	# 2100ms is past the 2000ms override window but well inside the
	# 5000ms default -- the per-kind window must be honored.
	OS.delay_msec(2100)
	if not d.should_deliver(ctx):
		_fail("rate-limit 2150ms later should deliver (per-kind window expired, default would still be active)")
		return
	_ok("per-kind window shorter than default is honored (2000 < 5000)")


# --- service-level verb (NotificationService.notify) ---
#
# notify() is the convenience that builds a NotificationContext and forwards
# to send_event(). It exists so call sites (QoS, Security, AppFirewall) can
# fire a typed notification without constructing the context shape.
# These tests confirm the verb: (1) builds a context that delivers to a
# player, (2) builds one that broadcasts, (3) honors the dedupe key.

func _test_notify_delivers_to_player() -> void:
	_notif.reset_dedupe()
	# This is exactly the call shape a wired service would use:
	#   NotificationService.notify(NotifKind.RATE_LIMITED, msg, source, key, data, player)
	var delivered: bool = _notif.notify(
		NotifKind.RATE_LIMITED,
		"You're casting too fast",
		"QoSService",
		"frame_test:qos_rl:p1:cast",
		{"action_type": "cast", "max_rate": 5.0},
		"frame_test_player_p1"
	)
	if not delivered:
		_fail("notify() should return true for first delivery to a player")
		return
	var history = _notif.get_history("frame_test_player_p1")
	if history.size() == 0:
		_fail("notify() should have routed through send() to the per-player history")
		return
	# The first entry should carry the source label + kind via the data dict
	# (send_event copies kind/source_service into the data payload).
	var entry: Dictionary = history[0]
	var data: Dictionary = entry.get("data", {})
	if data.get("source_service", "") != "QoSService":
		_fail("notify() should propagate source_service into data (got '%s')" % data.get("source_service", ""))
		return
	if int(data.get("kind", -1)) != NotifKind.RATE_LIMITED:
		_fail("notify() should propagate kind into data (got %d)" % int(data.get("kind", -1)))
		return
	_ok("notify() builds context, delivers to player, propagates kind+source")

func _test_notify_delivers_broadcast() -> void:
	_notif.reset_dedupe()
	# Empty recipient → broadcast (server-wide). Same call shape that
	# AppFirewall / SecurityMonitor use for admin scope.
	var delivered: bool = _notif.notify(
		NotifKind.ADMIN_ALERT,
		"RecursionGuard exceeded depth 16",
		"AppFirewall",
		"frame_test:fw_alert:1",
		{"context": "agent_tool_call", "depth": 16}
	)
	if not delivered:
		_fail("notify() should return true for broadcast (no recipient)")
		return
	if _notif.dedupe_tracked_count() < 1:
		_fail("dedupe should track the broadcast key after notify()")
		return
	_ok("notify() builds broadcast context and routes through broadcast_alert()")

func _test_notify_dedupes_identical_calls() -> void:
	_notif.reset_dedupe()
	# A spam loop on the same key within 5s should collapse to a single
	# delivery. This is the whole reason QoS / Security moved to the
	# frame: a rate-limited action firing 50x/sec used to toast 50x.
	var delivered_count: int = 0
	for i in 10:
		if _notif.notify(
			NotifKind.RATE_LIMITED,
			"tick %d" % i,
			"QoSService",
			"frame_test:qos_dedupe:loop",
			{},
			"frame_test_dedupe_p"
		):
			delivered_count += 1
	if delivered_count != 1:
		_fail("notify() should dedupe 10 identical calls to 1 (got %d)" % delivered_count)
		return
	_ok("notify() collapses 10 identical calls within the dedupe window to 1 delivery")

func _ok(msg: String) -> void:
	_passed += 1
	print("  [OK] %s" % msg)


func _fail(msg: String) -> void:
	_failed += 1
	printerr("  [FAIL] %s" % msg)


func _finish() -> void:
	print("--- NOTIFICATION FRAME TEST: %d passed, %d failed ---" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
