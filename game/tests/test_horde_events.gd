## test_horde_events.gd - HordeEventService end-to-end.
## Run headless:
##
##   cd game && godot --headless --path . --script res://tests/test_horde_events.gd
##
## Covers:
##   1. start_horde with a REAL template (slime) produces real Enemy
##      mobs (full data path: stats, HP, AI attach, EntityService reg).
##   2. Wave engine: spawning -> fighting -> wave clear on kills ->
##      inter_wave -> next wave -> boss finale -> completed(success).
##   3. Progress signal fires on count change only.
##   4. stop_horde sweeps every living horde mob from EntityService.
##   5. Zone conflict guard: second horde in the same zone is rejected.
##   6. HordeBar widget: signal-driven transitions + id guard.
##
## Exit 0 = all pass.
extends SceneTree

var _pass := 0
var _fail := 0

func _initialize() -> void:
	await process_frame
	await _run()
	quit(0 if _fail == 0 else 1)

func _run() -> void:
	var HordeScript = load("res://core/services/horde_event_service.gd")
	var horde = HordeScript.new()
	horde.name = "HordeEventService"
	get_root().add_child(horde)
	await process_frame

	var ds = root.get_node_or_null("DataService")
	var template = null
	if ds != null and ds.has_method("get_enemy"):
		template = ds.get_enemy("slime")
	_assert(template != null, "slime template loads from DataService")
	if template == null:
		return _finish()

	# Signal capture. Every entry carries horde_id so assertions can
	# scope to the main horde (the guard-test horde emits too).
	var sig := {"started": [], "wave_started": [], "progress": [], "wave_cleared": [], "boss": [], "completed": []}
	horde.horde_started.connect(func(hid, _z, _w): sig["started"].append(hid))
	horde.horde_wave_started.connect(func(hid, _w, _t): sig["wave_started"].append(hid))
	horde.horde_wave_progress.connect(func(hid, _w, remaining): sig["progress"].append([hid, remaining]))
	horde.horde_wave_cleared.connect(func(hid, _w): sig["wave_cleared"].append(hid))
	horde.horde_boss_spawned.connect(func(hid, _b): sig["boss"].append(hid))
	horde.horde_completed.connect(func(hid, success): sig["completed"].append([hid, success]))

	var es = root.get_node_or_null("EntityService")
	_assert(es != null, "EntityService present")
	if es == null:
		return _finish()

	# --- 5. Zone conflict guard ------------------------------------------
	var first_id: String = horde.start_horde("unzoned", {"template_id": "slime", "waves": 1, "mobs_per_wave": 1})
	var second_id: String = horde.start_horde("unzoned", {"template_id": "slime"})
	_assert(first_id != "" and second_id == "", "second horde in same zone rejected")
	horde.stop_horde(first_id)
	await process_frame

	# --- 1-4. Full lifecycle: 2 waves x 4 slimes + boss -------------------
	var boss_template := "slime"
	var boss_probe = ds.get_enemy("slime_king")
	if boss_probe != null:
		boss_template = "slime_king"

	var horde_id: String = horde.start_horde("unzoned", {
		"template_id": "slime",
		"waves": 2,
		"mobs_per_wave": 4,
		"inter_wave_delay": 0.2,
		"boss_template_id": boss_template,
	})
	_assert(horde_id != "", "start_horde returns an id")
	if horde_id == "":
		return _finish()
	var started_for_horde := 0
	for hid in sig["started"]:
		if str(hid) == horde_id:
			started_for_horde += 1
	_assert(started_for_horde == 1, "horde_started fired once for this horde")

	# Wait for wave 1 fully spawned.
	var ok := await _wait_fighting(horde, horde_id, 4, 20000)
	_assert(ok, "wave 1 reaches fighting with 4 alive")
	if not ok:
		return _finish()

	var mob_ids: Array = horde._hordes[horde_id]["mobs_spawned_ids"]
	_assert(mob_ids.size() == 4, "4 mob ids tracked for wave 1 (got %d)" % mob_ids.size())

	# Real mobs: full data path checks.
	var mob0 = es.get_entity(str(mob_ids[0]))
	_assert(mob0 != null and is_instance_valid(mob0), "horde mob resolved in EntityService")
	if mob0 != null and is_instance_valid(mob0):
		_assert(int(mob0.max_health) > 0, "mob has real template health (%d)" % int(mob0.max_health))
		_assert(mob0._ai != null, "mob AI attached")
		_assert(int(mob0.level) == int(template.level), "mob level from template")

	# Kill all 4 through the real damage path -- in two batches so the
	# change-driven progress signal shows distinct values (4 -> 2 -> 0).
	var killed := 0
	for eid in mob_ids:
		if killed == 2:
			break
		var mob = es.get_entity(str(eid))
		if mob != null and is_instance_valid(mob) and not bool(mob.is_dead):
			mob.take_damage(99999, null)
			killed += 1
	for _i in range(4):
		await process_frame
	for eid in mob_ids:
		var mob = es.get_entity(str(eid))
		if mob != null and is_instance_valid(mob) and not bool(mob.is_dead):
			mob.take_damage(99999, null)

	ok = await _wait_wave_number(horde, horde_id, 2, 20000)
	_assert(ok, "wave 2 begins after wave 1 cleared")
	var cleared_for_horde := 0
	for hid in sig["wave_cleared"]:
		if str(hid) == horde_id:
			cleared_for_horde += 1
	_assert(cleared_for_horde == 1, "horde_wave_cleared fired once for wave 1")
	var prog: Array = []
	for entry in sig["progress"]:
		if str(entry[0]) == horde_id:
			prog.append(int(entry[1]))
	_assert(prog.size() >= 2, "progress emitted for distinct values (got %s)" % str(prog))
	var no_dupes := true
	for i in range(1, prog.size()):
		if int(prog[i]) == int(prog[i - 1]):
			no_dupes = false
	_assert(no_dupes, "no consecutive duplicate progress values (change-driven, not per-frame)")
	var monotonic := true
	var prev := 999999
	for r in prog:
		if int(r) > prev:
			monotonic = false
		prev = int(r)
	_assert(monotonic, "progress counts strictly non-increasing (4 -> 2 -> 0)")

	ok = await _wait_fighting(horde, horde_id, 4, 20000)
	_assert(ok, "wave 2 reaches fighting with 4 alive")

	# Kill wave 2 -> boss finale.
	var ids2: Array = horde._hordes[horde_id]["mobs_spawned_ids"]
	for eid in ids2:
		var mob = es.get_entity(str(eid))
		if mob != null and is_instance_valid(mob) and not bool(mob.is_dead):
			mob.take_damage(99999, null)

	ok = await _wait_boss(horde, horde_id, 20000)
	_assert(ok, "boss finale spawns after final wave")
	var boss_fired := 0
	for hid in sig["boss"]:
		if str(hid) == horde_id:
			boss_fired += 1
	_assert(boss_fired == 1, "horde_boss_spawned fired once for this horde")

	# Kill the boss -> horde completes successfully.
	var st: Dictionary = horde.get_horde_status(horde_id)
	var boss_id := str(st.get("boss_id", ""))
	_assert(boss_id != "", "boss id tracked in status")
	if boss_id != "":
		var boss = es.get_entity(boss_id)
		_assert(boss != null, "boss resolvable through EntityService")
		if boss != null and is_instance_valid(boss):
			boss.take_damage(99999, null)
	ok = await _wait_completed(horde, 20000)
	_assert(ok, "horde_completed fires after boss death")
	var completion_success := false
	for entry in sig["completed"]:
		if str(entry[0]) == horde_id:
			completion_success = bool(entry[1])
	_assert(completion_success, "completion is a success")
	_assert(horde.active_horde_in_zone("unzoned") == "", "no horde left active in zone")

	# --- 4. stop_horde sweep ----------------------------------------------
	var sweep_id: String = horde.start_horde("unzoned", {"template_id": "slime", "waves": 1, "mobs_per_wave": 3})
	ok = await _wait_fighting(horde, sweep_id, 3, 20000)
	_assert(ok, "sweep-test horde reaches fighting")
	var sweep_ids: Array = horde._hordes[sweep_id]["all_mob_ids"]
	var alive_before := 0
	for eid in sweep_ids:
		var mob = es.get_entity(str(eid))
		if mob != null and is_instance_valid(mob) and not bool(mob.is_dead):
			alive_before += 1
	_assert(alive_before == 3, "3 living mobs before sweep (got %d)" % alive_before)
	horde.stop_horde(sweep_id)
	await process_frame
	await process_frame
	var alive_after := 0
	for eid in sweep_ids:
		var mob = es.get_entity(str(eid))
		if mob != null and is_instance_valid(mob) and not bool(mob.is_dead):
			alive_after += 1
	_assert(alive_after == 0, "stop_horde swept every living mob")
	_assert(horde.active_horde_in_zone("unzoned") == "", "swept horde is gone from the zone map")

	# --- 6. HordeBar widget --------------------------------------------------
	var BarScript = load("res://ui/components/horde_bar.gd")
	var bar: Control = BarScript.new()
	root.add_child(bar)
	await process_frame
	_assert(not bar.visible, "HordeBar hidden when idle")

	bar.show_horde_started("h1", "unzoned", 3)
	_assert(bar.visible, "HordeBar shows on horde start")
	bar.show_wave_started(2, 3)
	_assert(bar.active_horde_id() == "h1", "bar tracks its horde id")
	bar.show_wave_progress(7)
	bar.show_wave_cleared()
	bar.show_boss()
	_assert(bar.visible, "bar stays visible through boss phase")
	bar.hide_horde()
	_assert(not bar.visible, "bar hides on completion")
	_assert(bar.active_horde_id() == "", "bar clears its horde id")

	_finish()

## ---------------------------------------------------------------------------
## Poll helpers (each waits for a state condition with a deadline)
## ---------------------------------------------------------------------------

func _wait_fighting(horde, horde_id: String, expected_alive: int, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var st: Dictionary = horde.get_horde_status(horde_id)
		if st.is_empty():
			return false
		if str(st.get("state", "")) == "fighting" and int(st.get("remaining", -1)) == expected_alive:
			return true
	return false

func _wait_wave_number(horde, horde_id: String, wave: int, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var st: Dictionary = horde.get_horde_status(horde_id)
		if st.is_empty():
			return false
		if int(st.get("wave_number", -1)) == wave:
			return true
	return false

func _wait_boss(horde, horde_id: String, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var st: Dictionary = horde.get_horde_status(horde_id)
		if st.is_empty():
			return false
		if str(st.get("state", "")) == "boss" and str(st.get("boss_id", "")) != "":
			return true
	return false

func _wait_completed(horde, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if not horde._hordes.is_empty():
			continue
		# Horde map empty does not alone prove the signal fired; the
		# caller checks sig["completed"] -- but we need the signal to
		# have landed, so poll the last captured value via closure is
		# not possible here. The caller double-checks; this just waits
		# for teardown.
		return true
	return false

func _assert(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("PASS: %s" % label)
	else:
		_fail += 1
		print("FAIL: %s" % label)

func _finish() -> void:
	print("HordeEvents: %d passed, %d failed" % [_pass, _fail])
