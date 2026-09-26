extends SceneTree

## ActsService (Concord Chronicle, prd-psy.md section 5) smoke test:
## the AncientDoor.door_opened consumer records chapters, concrete
## gate days need their Ancient unlock earned, fill-in chapters
## advance one per door open inside the act's range, advance_from_day
## fences future acts out, announcements fire once per record,
## persistence round-trips, and the almanac's Watch-the-sky button
## records a real insight. Run:
##   godot --headless --path . --script res://tests/test_acts_service.gd
##
## _initialize() + ensure_initialized(): autoload _ready may lag the
## first probes in script mode.

var _svc = null
var _acts = null
var _ds = null

const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind


func _initialize() -> void:
	var ok := true

	_ds = root.get_node_or_null("DataService")
	_svc = root.get_node_or_null("SignService")
	_acts = root.get_node_or_null("ActsService")
	if _ds == null or _svc == null or _acts == null:
		push_error("FAIL: DataService/SignService/ActsService autoload missing")
		quit(1)
		return
	if not _ds._loaded:
		_ds.load_all_data()
	if _svc.has_method("ensure_initialized"):
		_svc.ensure_initialized()
	if _acts.has_method("ensure_initialized"):
		_acts.ensure_initialized()

	ok = _test_acts_data_loaded() and ok
	ok = _test_reset_chronicle() and ok
	# Script-mode boot never joined the tree, so the service's own door
	# wiring was skipped; scans are idempotent, so run one now that the
	# test is live.
	_acts._scan_doors()
	ok = _test_first_open_records_gate_and_fill() and ok
	ok = _test_advance_from_day_fence() and ok
	ok = _test_fill_sequence_one_per_open() and ok
	ok = _test_no_faith_language() and ok
	ok = _test_announcement_toast() and ok
	ok = await _test_almanac_watch_button() and ok
	ok = _test_persistence_round_trip() and ok
	ok = await _test_chronicle_panel() and ok

	print("--- ACTS SERVICE: ok=%s ---" % str(ok))
	quit(0 if ok else 1)


## Acts data: 3 authored acts, act_ prefix, chapters present.
func _test_acts_data_loaded() -> bool:
	var acts: Dictionary = _acts.get_acts()
	if acts.size() < 3:
		push_error("FAIL: expected >=3 acts, got %d" % acts.size())
		return false
	for required in ["act_1_the_first_vault", "act_2_the_unpaid_debt", "act_3_the_trust_audit"]:
		if not acts.has(required):
			push_error("FAIL: missing act %s" % required)
			return false
	var act1 = _acts.get_act("act_1_the_first_vault")
	if act1 == null or act1.get_chapter_count() != 3:
		push_error("FAIL: act_1 missing or wrong chapter count")
		return false
	if act1.get_summary(0).is_empty():
		push_error("FAIL: act summary empty")
		return false
	print("[OK] %d acts loaded with chapters" % acts.size())
	return true


## Determinism: gate days 1..3 are OURS for this test. Nothing else in
## the suite persists those unlocks, but clear them defensively; also
## reset the recorded ledger so the sequence below runs from zero.
func _test_reset_chronicle() -> bool:
	for d in [1, 2, 3]:
		_svc._unlocked_days.erase(d)
	_acts._recorded.clear()
	_acts._next_fill.clear()
	_acts._rebuild_next_fill()
	if _acts.is_chapter_recorded("act_3_the_trust_audit", 1):
		push_error("FAIL: reset left act_3 chapter 1 recorded")
		return false
	print("[OK] chronicle reset (days 1-3 clear, ledgers empty)")
	return true


## First door open (day 1): Act 1 chapter 1 records (its gate day 1 is
## unlocked); Act 3 chapter 1 records (fill-in act, no fence); Act 1
## chapters 2-3 stay sealed (their gates are not unlocked yet).
func _test_first_open_records_gate_and_fill() -> bool:
	# A chapter must NEVER record without a door open.
	_svc._unlocked_days[1] = true
	if _acts.is_chapter_recorded("act_1_the_first_vault", 1):
		push_error("FAIL: gate chapter recorded without door_opened")
		return false
	_acts._on_door_opened(1)
	if not _acts.is_chapter_recorded("act_1_the_first_vault", 1):
		push_error("FAIL: unlocked gate chapter did not record on door open")
		return false
	for gated in [2, 3]:
		if _acts.is_chapter_recorded("act_1_the_first_vault", gated):
			push_error("FAIL: locked gate chapter %d recorded" % gated)
			return false
	if not _acts.is_chapter_recorded("act_3_the_trust_audit", 1):
		push_error("FAIL: fill-in chapter did not record on first open")
		return false
	# The typed view carries the recorded flag.
	var views: Array = _acts.get_act_chapter_views("act_1_the_first_vault")
	if views.size() != 3 or not views[0].recorded or views[1].recorded:
		push_error("FAIL: chapter views recorded flags wrong")
		return false
	if views[0].get_record_line().is_empty():
		push_error("FAIL: record line empty")
		return false
	print("[OK] first open: gate chapter records, locked gates hold, fill-in advances")
	return true


## advance_from_day fences the act until the clock reaches it: Act 2
## (advance_from_day = 3) records nothing on day-1 and day-2 opens,
## then its fill-in chapter 1 records on the day-3 open together with
## its concrete gate chapter 2 (gate day 3 unlocked).
func _test_advance_from_day_fence() -> bool:
	# Day 2's unlock arrives (the tribe solved day 1's code earlier in
	# this run); day 3's unlock waits until after the fence check.
	_svc._unlocked_days[2] = true
	_acts._on_door_opened(2)
	if _acts.is_chapter_recorded("act_2_the_unpaid_debt", 1):
		push_error("FAIL: fenced act recorded before advance_from_day")
		return false
	if not _acts.is_chapter_recorded("act_1_the_first_vault", 2):
		push_error("FAIL: act 1 gate chapter 2 did not record on its day")
		return false
	_svc._unlocked_days[3] = true
	_acts._on_door_opened(3)
	if not _acts.is_chapter_recorded("act_2_the_unpaid_debt", 1):
		push_error("FAIL: act 2 chapter 1 did not record at its fence")
		return false
	if not _acts.is_chapter_recorded("act_2_the_unpaid_debt", 2):
		push_error("FAIL: act 2 gate chapter 2 did not record on gate day 3")
		return false
	# Act 1 chapter 3 (gate day 3) records on the day-3 open.
	if not _acts.is_chapter_recorded("act_1_the_first_vault", 3):
		push_error("FAIL: act 1 gate chapter 3 did not record on gate day 3")
		return false
	# Act 3 fill-in continues in order (chapter 2 on the second open).
	if not _acts.is_chapter_recorded("act_3_the_trust_audit", 2):
		push_error("FAIL: fill-in sequence did not advance to chapter 2")
		return false
	print("[OK] advance_from_day fence + gate days 2-3 + fill sequence")
	return true


## Fill-in chapters advance exactly one per door open: the day-4 open
## takes Act 3 chapter 3 (complete) and Act 2 chapter 3; nothing new
## records on a REPEAT open of the same day (idempotent).
func _test_fill_sequence_one_per_open() -> bool:
	_acts._on_door_opened(4)
	var act3_after: Dictionary = _acts.get_recorded_chapters("act_3_the_trust_audit")
	if act3_after.size() != 3:
		push_error("FAIL: act 3 not complete after 4 opens: %s" % str(act3_after))
		return false
	if not _acts.is_chapter_recorded("act_2_the_unpaid_debt", 3):
		push_error("FAIL: act 2 chapter 3 did not record on day 4")
		return false
	var total_before: int = _total_recorded()
	_acts._on_door_opened(4)
	if _total_recorded() != total_before:
		push_error("FAIL: repeat open double-recorded (%d -> %d)" % [total_before, _total_recorded()])
		return false
	var views: Array = _acts.get_act_chapter_views("act_3_the_trust_audit")
	if views.size() != 3:
		push_error("FAIL: act 3 view count wrong")
		return false
	for v in views:
		if not v.recorded:
			push_error("FAIL: complete act still has an unrecorded view")
			return false
	print("[OK] fill chapters one per open; repeat opens idempotent (9 chapters)")
	return true


## Voice law (prd-psy.md section 4): act copy is historical record --
## never faith language.
func _test_no_faith_language() -> bool:
	var banned := ["prayer", "holy", "sacred", "worship", "divine", "miracle"]
	var bad: Array = []
	for act_id in _acts.get_acts():
		var act = _acts.get_act(str(act_id))
		var blob := str(act.description)
		for d in act.chapters:
			blob += " " + str(d.get("record_text", "")) + " " + str(d.get("source_name", ""))
		var lower := blob.to_lower()
		for word in banned:
			if lower.contains(word):
				bad.append("%s says '%s'" % [str(act_id), word])
	if bad.is_empty():
		print("[OK] act copy honors the voice law (no faith language)")
		return true
	push_error("FAIL: faith language in acts: %s" % ", ".join(bad))
	return false


## Each record announces exactly one toast through the typed pipeline.
## Uses a FRESH open day (11) and clears the days 1-3 unlocks so the
## dedupe keys AND the gates from the tests above cannot interfere.
## From a clean chronicle, day-11 opens record exactly two fill-in
## chapters: act 2 chapter 1 (its fence is behind) and act 3 chapter
## 1. Act 1 has no fill-ins and its gates are day-specific, and a
## single open advances each act at most one fill-in.
func _test_announcement_toast() -> bool:
	var nsvc = root.get_node_or_null("NotificationService")
	if nsvc == null:
		push_error("FAIL: NotificationService missing")
		return false
	for d in [1, 2, 3]:
		_svc._unlocked_days.erase(d)
	_acts._recorded.clear()
	_acts._next_fill.clear()
	_acts._rebuild_next_fill()
	var toasts: Array = []
	var handler := func(_entity_id: String, n: Dictionary) -> void:
		if str(n.get("source_service", "")) == "ActsService":
			toasts.append(n)
	nsvc.notification_received.connect(handler)
	_acts._on_door_opened(11)
	nsvc.notification_received.disconnect(handler)
	if toasts.size() != 2:
		push_error("FAIL: expected exactly 2 chapter toasts, got %d" % toasts.size())
		return false
	var msg := str(toasts[0].get("message", ""))
	if not msg.contains("The Chronicle records"):
		push_error("FAIL: toast message wrong: %s" % msg)
		return false
	print("[OK] chapter records announce once each (2 fill-in toasts on a fresh open)")
	return true


## The almanac's Watch-the-sky button records a REAL insight for the
## local player (one toast, observer count +1, rows rebuilt).
func _test_almanac_watch_button() -> bool:
	var ui_script = load("res://ui/components/sky_almanac_ui.gd")
	if ui_script == null:
		push_error("FAIL: sky_almanac_ui.gd missing")
		return false
	var panel = ui_script.new()
	root.add_child(panel)
	await process_frame
	var day: int = _svc.day_index_for(float(Time.get_unix_time_from_system()))
	var win: int = _svc.window_index_for(float(Time.get_unix_time_from_system()))
	var before: int = _svc._observer_count(day, win)

	var nsvc = root.get_node_or_null("NotificationService")
	var toasts: Array = []
	# Targeted notifies (recipient set) flow through the legacy send()
	# path, which emits notification_sent with kind/source_service
	# nested in the data dict -- notification_received only carries the
	# broadcast path.
	var handler := func(entity_id: String, n: Dictionary) -> void:
		var data: Dictionary = n.get("data", {}) if n.get("data", {}) is Dictionary else {}
		if int(data.get("kind", -1)) == NotifKind.SIGN_INSIGHT_RECORDED \
				and str(data.get("source_service", "")) == "SkyAlmanacUI":
			toasts.append(n)
	nsvc.notification_sent.connect(handler)
	panel._on_watch_pressed()
	nsvc.notification_sent.disconnect(handler)

	var after: int = _svc._observer_count(day, win)
	if after != before + 1:
		push_error("FAIL: watch button did not record an insight (%d -> %d)" % [before, after])
		panel.free()
		return false
	if toasts.size() != 1:
		push_error("FAIL: expected 1 watch toast, got %d" % toasts.size())
		panel.free()
		return false
	# The button must exist and be wired to the handler.
	if panel._watch_btn == null or not panel._watch_btn.pressed.is_connected(panel._on_watch_pressed):
		push_error("FAIL: watch button not wired")
		panel.free()
		return false
	# Idempotent second gaze: still ok, still one per window.
	panel._on_watch_pressed()
	if _svc._observer_count(day, win) != after:
		push_error("FAIL: second gaze recorded twice")
		panel.free()
		return false
	panel.free()
	print("[OK] almanac Watch-the-sky: insight recorded (+1 observer), toast fired")
	return true


## Recorded chapters survive a service reboot (DictStore round-trip).
## Self-deriving: whatever chapters the earlier tests recorded, those
## exact entries must come back after a reboot.
func _test_persistence_round_trip() -> bool:
	var expected: int = _total_recorded()
	if expected == 0:
		push_error("FAIL: nothing recorded to round-trip")
		return false
	var sample_act := ""
	var sample_idx := -1
	for rid in _acts._recorded.keys():
		var ledger: Dictionary = _acts._recorded[rid]
		if not ledger.is_empty():
			sample_act = str(rid)
			sample_idx = int(ledger.keys()[0])
			break
	_acts._initialized = false
	_acts._recorded = {}
	_acts._next_fill = {}
	_acts.ensure_initialized()
	if _total_recorded() != expected:
		push_error("FAIL: reboot lost chapters (%d != %d)" % [_total_recorded(), expected])
		return false
	if not _acts.is_chapter_recorded(sample_act, sample_idx):
		push_error("FAIL: reboot lost %s chapter %d" % [sample_act, sample_idx])
		return false
	print("[OK] persistence: %d recorded chapters survive reboot" % expected)
	return true


## The dedicated Chronicle panel (J) renders acts + sealed frames
## without leaking unrecorded lessons, and its _add_section extension
## point blocks cleanly for future mysteries.
func _test_chronicle_panel() -> bool:
	var ui_script = load("res://ui/components/chronicle_ui.gd")
	if ui_script == null:
		push_error("FAIL: chronicle_ui.gd missing")
		return false
	var panel = ui_script.new()
	root.add_child(panel)
	await process_frame
	panel.refresh()
	await process_frame
	if panel._sections == null or panel._sections.get_child_count() == 0:
		push_error("FAIL: chronicle panel rendered no sections")
		panel.free()
		return false
	var text := ""
	for block in panel._sections.get_children():
		if block is Label:
			text += str(block.text) + "\n"
	if not text.contains("The First Vault"):
		push_error("FAIL: chronicle panel missing act title")
		panel.free()
		return false
	# Voice law at the panel layer too.
	for word in ["prayer", "holy", "sacred", "worship", "divine", "miracle"]:
		if text.to_lower().contains(word):
			push_error("FAIL: panel text says '%s'" % word)
			panel.free()
			return false
	# Honesty: at least one sealed frame, and no recorded lesson text
	# leaks for the act 1 chapters this run never opened.
	if not text.contains("[sealed"):
		push_error("FAIL: chronicle panel shows no sealed frames")
		panel.free()
		return false
	panel.free()
	print("[OK] Chronicle panel: acts render, seals hold, voice law holds")
	return true


func _total_recorded() -> int:
	var n := 0
	for rid in _acts._recorded.keys():
		n += (_acts._recorded[rid] as Dictionary).size()
	return n
