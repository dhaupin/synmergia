extends SceneTree

## End-to-end Skyward Concord loop probe (labs/prd-psy.md):
## record insights -> tribal reveal -> code assembles -> tomorrow's
## Ancient unlocks -> the world's AncientDoor physically opens and its
## prompt flips; sky renderer + almanac panel are wired and honest.
## Run: godot --headless --path . --script res://tests/probe_ancient_loop.gd
##
## _initialize() + ensure_initialized(): autoload _ready may lag the
## first probes in script mode.

func _initialize() -> void:
	var ok := true

	var ds = root.get_node_or_null("DataService")
	var svc = root.get_node_or_null("SignService")
	if ds == null or svc == null:
		push_error("FAIL: DataService/SignService autoload missing")
		quit(1)
		return
	if not ds._loaded:
		ds.load_all_data()
	if svc.has_method("ensure_initialized"):
		svc.ensure_initialized()

	# 1. The GLOBE scene carries the Ancient Door + Sky Signs renderer
	#    (planar-retirement Step 5: the planar world is retired; the globe is
	#    the open world). Build it through the world's own content builder --
	#    the Concord loop is one of its declared families.
	ProjectSettings.set_setting("synmergia/world/planet_radius", 100.0)
	var world: PackedScene = load("res://scenes/worlds/globe_world.tscn")
	if world == null:
		push_error("FAIL: globe_world.tscn did not load")
		quit(1)
		return
	var _globe := world.instantiate()
	root.add_child(_globe)
	# Wait for the boot waves (the Concord loop is one of them).
	var _boot_deadline: int = Time.get_ticks_msec() + 60000
	while not _globe.has_meta("boot_waves_done_ms") and Time.get_ticks_msec() < _boot_deadline:
		await process_frame
	await process_frame

	var world_root: Node = _globe.get("world_root")
	var door: Node3D = world_root.get_node_or_null("AncientDoor")
	if door == null:
		push_error("FAIL: AncientDoor not placed in world")
		_globe.free()
		quit(1)
		return
	var sky: Node3D = _globe.get("player").get_node_or_null("SkySigns")
	if sky == null:
		push_error("FAIL: SkySigns renderer not placed in world")
		_globe.free()
		quit(1)
		return
	if world_root.get_node_or_null("ConcordStone") == null:
		push_error("FAIL: ConcordStone not placed in world")
		_globe.free()
		quit(1)
		return
	print("[OK] world carries AncientDoor + SkySigns + ConcordStone")

	# 1b. Concord Chronicle consumer: ActsService must be listening, and
	#    this run owns a fresh ledger (earlier suite runs persist theirs).
	var acts = root.get_node_or_null("ActsService")
	if acts == null:
		push_error("FAIL: ActsService autoload missing")
		_globe.free()
		quit(1)
		return
	acts.ensure_initialized()
	acts._recorded.clear()
	acts._rebuild_next_fill()
	acts._scan_doors()
	var opened_fired: Dictionary = {"day": -1}
	var spy := func(day_index: int) -> void:
		opened_fired["day"] = day_index
	door.door_opened.connect(spy)

	# 2. Sealed door: prompt says READ, interact refuses with a glyph count.
	var prompt: String = door.get_interaction_prompt()
	if not prompt.contains("Read"):
		push_error("FAIL: sealed prompt wrong: %s" % prompt)
		_globe.free()
		quit(1)
		return
	var sealed: Dictionary = door.try_interact(null)
	if bool(sealed["ok"]) or str(sealed["reason"]) != "sealed":
		push_error("FAIL: sealed interact result: %s" % str(sealed))
		_globe.free()
		quit(1)
		return
	if not str(sealed["message"]).contains("of 4 glyphs"):
		push_error("FAIL: sealed message lacks glyph count: %s" % str(sealed["message"]))
		_globe.free()
		quit(1)
		return
	print("[OK] sealed door refuses with tribal progress (%s)" % str(sealed["message"]).substr(0, 48))

	# 2b. Concord Stone: the player-facing insight trigger. Records for
	#	a test observer; a second press is idempotent (one gaze per window
	#	per player -- the stone cannot be spammed).
	var stone: Node3D = world_root.get_node_or_null("ConcordStone")
	if stone == null:
		push_error("FAIL: ConcordStone not placed in world")
		_globe.free()
		quit(1)
		return
	var stone_prompt: String = stone.get_interaction_prompt()
	if not stone_prompt.contains("Watch the sky"):
		push_error("FAIL: stone prompt wrong: %s" % stone_prompt)
		_globe.free()
		quit(1)
		return
	var stone_r1: Dictionary = stone.try_interact({"entity_id": "loop_tribe_a"})
	if not bool(stone_r1["ok"]):
		push_error("FAIL: stone record failed: %s" % str(stone_r1))
		_globe.free()
		quit(1)
		return
	var stone_r2: Dictionary = stone.try_interact({"entity_id": "loop_tribe_a"})
	if not bool(stone_r2["ok"]) or str(stone_r2["reason"]) != "already":
		push_error("FAIL: stone repeat not idempotent: %s" % str(stone_r2))
		_globe.free()
		quit(1)
		return
	print("[OK] Concord Stone records insights (E), repeat gaze idempotent")

	# 3. Run the actual tribal loop on the door's day: tribe_a already
	#    gazed at the stone above (their insight IS the E-press), so
	#    two more observers cross the threshold of 3.
	#    reveal window 0, force-reveal the rest -> door must open.
	var day: int = door._resolve_day()
	var win: int = svc.window_index_for(float(Time.get_unix_time_from_system()))
	var r1: Dictionary = svc.record_insight("loop_tribe_a")
	var r2: Dictionary = svc.record_insight("loop_tribe_b")
	if bool(r1["revealed_now"]) or bool(r2["revealed_now"]):
		push_error("FAIL: revealed below threshold")
		_globe.free()
		quit(1)
		return
	var r3: Dictionary = svc.record_insight("loop_tribe_c")
	if not bool(r3["revealed_now"]):
		push_error("FAIL: 3rd observer did not reveal")
		_globe.free()
		quit(1)
		return
	# The door tracks TOMORROW (for_day_offset=1): completing TODAY's
	# code turns its key. Reveal the remaining windows of TODAY.
	var now_day: int = svc.day_index_for(float(Time.get_unix_time_from_system()))
	for w in svc.WINDOWS_PER_DAY:
		svc.force_reveal_window(now_day, w)
	# Await a frame so the door's _process/_refresh_state sees the flip.
	await process_frame
	await process_frame
	if not door._is_open:
		push_error("FAIL: door did not open after full day reveal")
		_globe.free()
		quit(1)
		return
	print("[OK] tribal loop: 3 observers -> code assembled -> DOOR OPEN")

	# 3b. S16.5 world-state law: the door's open is a WORLD DELTA in
	#	the shared StateTree -- provenance (actor = door, epoch = the
	#	sky clock), readable by any citizen through the one chain.
	var proj = root.get_node_or_null("WorldStateProjection")
	if proj == null:
		push_error("FAIL: WorldStateProjection autoload missing")
		_globe.free()
		quit(1)
		return
	var ws = proj.world_state()
	var delta: Dictionary = ws.get_world_state("main", "gates/%s" % str(door.name))
	var dpl: Dictionary = delta.get("payload", {}) if delta.get("payload", {}) is Dictionary else {}
	if int(dpl.get("opened_for_day", -1)) != door._resolve_day():
		push_error("FAIL: door delta missing/ wrong day: %s" % str(delta))
		_globe.free()
		quit(1)
		return
	if str(delta.get("actor", "")) != str(door.name):
		push_error("FAIL: door delta provenance wrong: %s" % str(delta))
		_globe.free()
		quit(1)
		return
	print("[OK] world delta recorded: gates/%s (actor=%s, epoch=%.2f)" % [str(door.name), str(delta.get("actor", "")), float(delta.get("epoch", 0.0))])

	# 3d. Payoff spectacle (batch 14): the open erupts a light pillar
	#	and a light flash at the door, and the sky renderer owns the
	#	shard-wide amber flash API.
	if door.get_node_or_null("PayoffPillar") == null:
		push_error("FAIL: no PayoffPillar after door open")
		_globe.free()
		quit(1)
		return
	if door.get_node_or_null("PayoffFlash") == null:
		push_error("FAIL: no PayoffFlash after door open")
		_globe.free()
		quit(1)
		return
	if not sky.has_method("flash_payoff"):
		push_error("FAIL: sky renderer missing flash_payoff")
		_globe.free()
		quit(1)
		return
	print("[OK] payoff spectacle: pillar + light flash + sky flash wired")

	# 3c. Concord Chronicle (labs/prd-psy.md section 5): the door open
	#    advanced the acts. The real-clock unlock day is today + 1 (the
	#    door tracks tomorrow), which matches NO authored gate day -- so
	#    the FILL-IN chapters advance (act 2 is past its day-3 fence,
	#    act 3 is open-ended) while the day-specific gate chapters stay
	#    sealed. The gates only open when the tribe earns THOSE days.
	var probe_day: int = door._resolve_day()
	if int(opened_fired["day"]) != probe_day:
		push_error("FAIL: door_opened fired with day %s, expected %d" % [str(opened_fired["day"]), probe_day])
		_globe.free()
		quit(1)
		return
	if not acts.is_chapter_recorded("act_3_the_trust_audit", 1):
		push_error("FAIL: fill-in act did not advance on the door open")
		_globe.free()
		quit(1)
		return
	if not acts.is_chapter_recorded("act_2_the_unpaid_debt", 1):
		push_error("FAIL: unfenced fill-in act did not advance")
		_globe.free()
		quit(1)
		return
	if acts.is_chapter_recorded("act_1_the_first_vault", 1) \
			or acts.is_chapter_recorded("act_2_the_unpaid_debt", 2):
		push_error("FAIL: gate chapter recorded while its day was never earned")
		_globe.free()
		quit(1)
		return
	print("[OK] Chronicle advanced on door open (fill-ins recorded, day gates held)")

	# 3b. Daily Class Blessing: the solved code earned TOMORROW, so the
	# blessing for tomorrow is live and names exactly one class.
	var blessed_day: int = now_day + 1
	if not svc.is_blessing_active(blessed_day):
		push_error("FAIL: blessing not live for earned day %d" % blessed_day)
		_globe.free()
		quit(1)
		return
	var blessed_class: String = svc.get_blessed_class_id(blessed_day)
	if blessed_class.is_empty():
		push_error("FAIL: no blessed class named for day %d" % blessed_day)
		_globe.free()
		quit(1)
		return
	# The blessed class pays; a different one does not.
	if not svc.is_class_blessed(blessed_class, blessed_day):
		push_error("FAIL: named class did not pay on its own day")
		_globe.free()
		quit(1)
		return
	var control_day: int = blessed_day + 1
	if svc.is_class_blessed(blessed_class, control_day) and svc.get_blessed_class_id(control_day) == blessed_class:
		push_error("FAIL: same class blessed on consecutive days (hydration broke)")
		_globe.free()
		quit(1)
		return
	print("[OK] class blessing live: '%s' for day %d (+20%%/+5lvls), hydration intact" % [blessed_class, blessed_day])

	# 4. Prompt flips on the open door.
	var open_prompt: String = door.get_interaction_prompt()
	if not open_prompt.contains("open"):
		push_error("FAIL: open prompt wrong: %s" % open_prompt)
		_globe.free()
		quit(1)
		return
	var open_res: Dictionary = door.try_interact(null)
	if not bool(open_res["ok"]) or str(open_res["reason"]) != "already_open":
		push_error("FAIL: open interact result: %s" % str(open_res))
		_globe.free()
		quit(1)
		return
	print("[OK] open door prompt + interact readback")

	# 5. Sky renderer built its star pool and reacts to reveal state.
	var stars: Array = sky._stars
	if stars.size() < 7:
		push_error("FAIL: sky star pool too small: %d" % stars.size())
		_globe.free()
		quit(1)
		return
	var any_visible := false
	for s in stars:
		if s.visible:
			any_visible = true
			break
	if not any_visible:
		push_error("FAIL: sky shows no stars for the current window")
		_globe.free()
		quit(1)
		return
	print("[OK] sky constellation visible (%d-star pool)" % stars.size())

	# 6. Almanac panel builds and honors the tribal rule.
	var ui_script = load("res://ui/components/sky_almanac_ui.gd")
	if ui_script == null:
		push_error("FAIL: sky_almanac_ui.gd missing")
		_globe.free()
		quit(1)
		return
	var panel = ui_script.new()
	root.add_child(panel)
	await process_frame
	var rows: VBoxContainer = panel._rows
	if rows == null or rows.get_child_count() != svc.WINDOWS_PER_DAY:
		push_error("FAIL: almanac rows != window count")
		panel.free()
		_globe.free()
		quit(1)
		return
	# Tribal-rule honesty: collect all Label text; every window the tribe
	# has NOT revealed must render as unknown ("glyph unknown"), never as
	# a revealed glyph quote.
	var revealed_glyphs: Array[String] = svc.get_revealed_glyphs()
	var sealed_glyphs: Array[String] = []
	for i in svc.WINDOWS_PER_DAY:
		if i >= revealed_glyphs.size() or revealed_glyphs[i] == "?":
			var s = svc.sign_for_window(day, i)
			if s != null:
				sealed_glyphs.append(str(s.glyph))
	var leak := false
	var unknown_count := 0
	for c in rows.get_children():
		for sub in c.get_children():
			if sub is Label:
				var t := str(sub.text)
				if t.contains("glyph unknown"):
					unknown_count += 1
				for sg in sealed_glyphs:
					if t.contains("'%s'" % sg):
						leak = true
	if leak or unknown_count != sealed_glyphs.size():
		push_error("FAIL: almanac tribal-rule leak (unknown=%d sealed=%d leak=%s)" % [unknown_count, sealed_glyphs.size(), str(leak)])
		panel.free()
		_globe.free()
		quit(1)
		return
	print("[OK] almanac renders 4 windows, honors the tribal rule (%d unknown, %d revealed)" % [unknown_count, 4 - unknown_count])

	# 6b. The far-gaze: the almanac's Watch-the-sky button records a
	#    real insight for the local player (who is NOT at the stone).
	if panel._watch_btn == null or not panel._watch_btn.pressed.is_connected(panel._on_watch_pressed):
		push_error("FAIL: almanac Watch-the-sky button missing or unwired")
		panel.free()
		_globe.free()
		quit(1)
		return
	var pre_watch: int = svc._observer_count(now_day, win)
	panel._on_watch_pressed()
	if svc._observer_count(now_day, win) <= pre_watch:
		push_error("FAIL: watch button did not record an insight")
		panel.free()
		_globe.free()
		quit(1)
		return
	print("[OK] almanac Watch-the-sky button records a remote insight")

	if is_instance_valid(panel):
		panel.free()
	# 7. Dawn re-seal: the door closes when its day's unlock disappears
	#    from under it (the next dawn), and a re-earned unlock reopens
	#    it -- the daily heartbeat that keeps door_opened firing.
	svc._unlocked_days.erase(probe_day)
	door._refresh_state()
	if door._is_open:
		push_error("FAIL: door did not re-seal when its day was unearned")
		_globe.free()
		quit(1)
		return
	svc._unlocked_days[probe_day] = true
	door._refresh_state()
	if not door._is_open:
		push_error("FAIL: door did not reopen after its day was re-earned")
		_globe.free()
		quit(1)
		return
	print("[OK] dawn re-seal + reopen (door_opened stays a daily event)")
	if is_instance_valid(_globe):
		# Drain the async mesh lane before freeing (the globe probe law): a
		# queued clipmap callback would otherwise fire on a freed instance.
		var _clipmap = _globe.get("clipmap")
		var _drain_deadline: int = Time.get_ticks_msec() + 60000
		while _clipmap != null and _clipmap.mesh_pending() > 0 and Time.get_ticks_msec() < _drain_deadline:
			await process_frame
		await process_frame
		_globe.free()
	print("--- ANCIENT LOOP PROBE: ok=true ---")
	quit(0)
