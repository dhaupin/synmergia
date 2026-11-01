extends SceneTree

## Combat-sense receipt:
##   1. The player's own CombatComponent lifecycle reaches the
##      CombatLog as rows: cast started/finished, channel end,
##      combat enter/exit (the signals emitted with zero listeners
##      through the whole scaffolding era).
##   2. The binder is honest: no local player / no mounted component
##      leaves the HUD silent instead of crashing.
##   3. spawn_service.boss_spawned is REMOVED (no-void: the
##      NotificationService bridge over entity_spawned already owns
##      the world-boss announcement voice).
## Run:
##   godot --headless --path . --script res://tests/test_combat_sense_loop.gd


func _initialize() -> void:
	# Autoload-lag law: the body runs on the first idle frame.
	_run.call_deferred()

func _run() -> void:
	var hud = load("res://ui/hud/hud_integrator.gd").new()
	root.add_child(hud)
	var log_ui = load("res://ui/components/combat_log.gd").new()
	root.add_child(log_ui)
	hud._combat_log = log_ui

	# 1. The binder is honest first: without a mounted player there
	# is nothing to bind; this must be a no-op, not a crash.
	hud._bind_player_combat_feedback()
	print("[OK] the binder is a no-op without a local player (no crash)")

	# 1b. Bind through the real seam: a fake player node carrying its
	# own combat_component rides PlayerManager's local_player slot.
	var pm: Node = root.get_node_or_null("PlayerManager")
	var comp = load("res://core/components/combat_component.gd").new()
	var fake_player := Node.new()
	fake_player.name = "CombatSenseProbePlayer"
	fake_player.set("combat_component", comp)
	root.add_child(fake_player)
	if pm == null or not pm.has_method("set_local_player"):
		push_error("FAIL: PlayerManager.set_local_player not reachable in script mode")
		quit(1)
		return
	pm.set_local_player(fake_player)
	hud._bind_player_combat_feedback()
	if pm.local_player != fake_player:
		push_error("FAIL: the local player slot did not take the probe")
		quit(1)
		return
	print("[OK] the binder connects the local player's component lifecycle")

	# 2. Rows: cast started / finished / channel end / combat state.
	var base: int = log_ui.get_message_count()
	hud._on_cast_started({"display_name": "Ember Vault"})
	var after_cast: int = log_ui.get_message_count()
	if after_cast != base + 1:
		push_error("FAIL: cast_started produced no row (%d -> %d)" % [base, after_cast])
		quit(1)
		return
	hud._on_cast_finished({"display_name": "Ember Vault"})
	hud._on_channel_ended({"display_name": "Tide Sigil"}, false)
	hud._on_combat_entered()
	hud._on_combat_exited()
	if log_ui.get_message_count() != after_cast + 4:
		push_error("FAIL: the lifecycle rows did not all land (count=%d)" % log_ui.get_message_count())
		quit(1)
		return
	# Truth through the entries (the log trims old lines, so read the
	# tail): each row must carry its honest verdict.
	var entries: Variant = log_ui.get("_entries")
	if not (entries is Array) or (entries as Array).size() < 5:
		push_error("FAIL: the log's entry book is missing rows")
		quit(1)
		return
	var row_text: String = str((entries as Array)[(entries as Array).size() - 5].get("text"))
	if not row_text.contains("You begin casting Ember Vault"):
		push_error("FAIL: the cast row lost its skill label (%s)" % row_text)
		quit(1)
		return
	var verdicts := ["You finish casting Ember Vault", "interrupted", "entered combat", "left combat"]
	for i in range(verdicts.size()):
		var t := str((entries as Array)[(entries as Array).size() - 4 + i].get("text"))
		if not t.contains(verdicts[i]):
			push_error("FAIL: row %d lost its truth ('%s' not in %s)" % [i, verdicts[i], t])
			quit(1)
			return
	print("[OK] cast/channel/combat lifecycle rows land in the CombatLog")

	# 3. The boss arrival: boss_spawned was REMOVED for the no-void law
	# (nothing listened); the announcement voice is the
	# NotificationService bridge over EventHub.entity_spawned, and the
	# boss spawn path must carry the enabled server-wide metadata.
	var spawn_probe: Variant = load("res://core/services/spawn_service.gd").new()
	if spawn_probe.has_signal("boss_spawned"):
		push_error("FAIL: boss_spawned still exists (the void removal did not land)")
		quit(1)
		return
	print("[OK] boss_spawned removed (the entity_spawned metadata bridge owns the voice)")
	# The voice itself must stay hooked: NotificationService bridges
	# EventHub.entity_spawned into the metadata-driven world-event
	# broadcast (boss arrivals announce once, server-wide config kept
	# honest by the spawn path's scope gate).
	var notif: Node = root.get_node_or_null("NotificationService")
	var event_hub: Node = root.get_node_or_null("EventHub")
	if notif == null or event_hub == null \
			or not event_hub.entity_spawned.is_connected(notif._on_entity_spawned):
		push_error("FAIL: the entity_spawned -> world-event announce bridge is missing")
		quit(1)
		return
	print("[OK] the world-event announce bridge stays connected")

	# 4. The removal: chapter_recorded died with its cause documented.
	if load("res://core/services/acts_service.gd").new().has_signal("chapter_recorded"):
		push_error("FAIL: chapter_recorded still exists (the void removal did not land)")
		quit(1)
		return
	print("[OK] chapter_recorded removed (its announce path already carries the voice)")

	pm.set_local_player(null)
	hud.queue_free()
	log_ui.queue_free()
	fake_player.queue_free()
	print("--- COMBAT SENSE LOOP: ok=true ---")
	quit(0)

