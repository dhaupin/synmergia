extends SceneTree

## Chronicle mysteries (prd-psy.md section 5, batch 14): chapter-gated
## attempts, DERIVED answers (the sky's own record -- nothing
## answer-shaped is stored), title + XP rewards, per-player solved
## ledger with DictStore round-trip. Run:
##   godot --headless --path . --script res://tests/test_mysteries.gd
##
## _initialize() + ensure_initialized(): autoload _ready may lag the
## first probes in script mode.

var _acts = null
var _svc = null
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

	ok = _test_mysteries_data() and ok
	ok = _test_locked_gate() and ok
	ok = _test_unlock_and_wrong_answer() and ok
	ok = _test_sky_code_solve() and ok
	ok = _test_tally_mystery() and ok
	ok = _test_solved_persistence() and ok

	print("--- MYSTERIES: ok=%s ---" % str(ok))
	quit(0 if ok else 1)


func _reset_world() -> void:
	for d in [1, 2, 3]:
		_svc._unlocked_days.erase(d)
	_acts._recorded.clear()
	_acts._rebuild_next_fill()
	# NOTE: _solved is deliberately NOT cleared here -- mysteries have
	# distinct ids and per-player keys, so the tally tests cannot
	# collide with the vault solve. Clearing it here would erase the
	# vault ledger before the persistence check reads it.


## Two mysteries loaded, sky-code first (the answer is DERIVED), gates
## name real act chapters, rewards name real titles.
func _test_mysteries_data() -> bool:
	var mysteries: Dictionary = _acts.get_mysteries()
	if mysteries.size() < 2:
		push_error("FAIL: expected >=2 mysteries, got %d" % mysteries.size())
		return false
	for required in ["mystery_the_first_vault", "mystery_the_watcher_tally"]:
		if not mysteries.has(required):
			push_error("FAIL: missing mystery %s" % required)
			return false
	var m = _acts.get_mystery("mystery_the_first_vault")
	if m == null or int(m.answer_kind) != 0 or int(m.answer_day) != 1:
		push_error("FAIL: first vault mystery shape wrong")
		return false
	if str(m.gate_act_id) != "act_1_the_first_vault" or int(m.gate_chapter_index) != 1:
		push_error("FAIL: first vault gate wrong")
		return false
	# The reward title exists in data.
	if _ds.get_item and false:
		pass
	var titles := _load_title_ids()
	if not titles.has("title_vault_reader") or not titles.has("title_wardens_word"):
		push_error("FAIL: reward titles missing from data/titles")
		return false
	# The expected answer is derivable and shaped like a 4-glyph code.
	var code: String = _svc.get_ancient_code(1)
	if code.count("-") != 3 or str(m.expected_answer(code)) != code.to_upper():
		push_error("FAIL: derived answer malformed: '%s'" % code)
		return false
	print("[OK] %d mysteries loaded; answer derived ('%s')" % [mysteries.size(), code])
	return true


## Gate check first: an unknown, locked, or already-solved mystery
## refuses BEFORE any answer comparison.
func _test_locked_gate() -> bool:
	_reset_world()
	if _acts.is_mystery_unlocked("mystery_the_first_vault"):
		push_error("FAIL: mystery unlocked before its chapter recorded")
		return false
	var unknown: Dictionary = _acts.attempt_mystery("mystery_nope", "m_player", "WAKE")
	if str(unknown.get("reason", "")) != "unknown":
		push_error("FAIL: unknown mystery not rejected: %s" % str(unknown))
		return false
	# Even the CORRECT answer bounces while the gate is sealed.
	var code: String = _svc.get_ancient_code(1)
	var locked: Dictionary = _acts.attempt_mystery("mystery_the_first_vault", "m_player", code)
	if bool(locked.get("ok", true)) or str(locked.get("reason", "")) != "locked":
		push_error("FAIL: sealed gate accepted an attempt: %s" % str(locked))
		return false
	print("[OK] gates: unknown + sealed-gate attempts refuse before answers")
	return true


## Record the gate chapter (act 1 chapter 1 via the door-open day 1),
## then a wrong answer fails cleanly without consuming anything.
func _test_unlock_and_wrong_answer() -> bool:
	_svc._unlocked_days[1] = true
	_acts._on_door_opened(1)
	if not _acts.is_mystery_unlocked("mystery_the_first_vault"):
		push_error("FAIL: gate chapter recorded but mystery still locked")
		return false
	var wrong: Dictionary = _acts.attempt_mystery("mystery_the_first_vault", "m_player", "WAKE-WAKE-WAKE-WAKE")
	if bool(wrong.get("ok", true)) or str(wrong.get("reason", "")) != "wrong":
		push_error("FAIL: wrong answer not rejected cleanly: %s" % str(wrong))
		return false
	if _acts.is_mystery_solved("mystery_the_first_vault", "m_player"):
		push_error("FAIL: wrong answer marked solved")
		return false
	print("[OK] gate opened via chapter record; wrong answers fail clean")
	return true


## The real solve: the derived sky code. One toast, title unlocked,
## idempotent afterwards. Case + whitespace normalization.
func _test_sky_code_solve() -> bool:
	var code: String = _svc.get_ancient_code(1)
	var nsvc = root.get_node_or_null("NotificationService")
	var toasts: Array = []
	var handler := func(entity_id: String, n: Dictionary) -> void:
		var data: Dictionary = n.get("data", {}) if n.get("data", {}) is Dictionary else {}
		if str(data.get("source_service", "")) == "ActsService" \
				and int(data.get("kind", -1)) == NotifKind.ACHIEVEMENT_UNLOCKED:
			toasts.append(n)
	nsvc.notification_sent.connect(handler)
	# lowercase + padded on purpose: normalization is part of the deal.
	var result: Dictionary = _acts.attempt_mystery("mystery_the_first_vault", "m_player", "  " + code.to_lower() + " ")
	nsvc.notification_sent.disconnect(handler)
	if not bool(result.get("ok", false)) or not bool(result.get("solved_now", false)):
		push_error("FAIL: correct sky code rejected: %s (expected '%s')" % [str(result), code])
		return false
	if toasts.size() != 1:
		push_error("FAIL: expected 1 solve toast, got %d" % toasts.size())
		return false
	var ts = root.get_node_or_null("TitleService")
	if ts == null or not ts.is_unlocked("m_player", "title_vault_reader"):
		push_error("FAIL: reward title not unlocked")
		return false
	var again: Dictionary = _acts.attempt_mystery("mystery_the_first_vault", "m_player", code)
	if bool(again.get("ok", true)) or str(again.get("reason", "")) != "already":
		push_error("FAIL: solved mystery re-attemptable: %s" % str(again))
		return false
	# A DIFFERENT player still gets to solve it (per-player ledger).
	var other: Dictionary = _acts.attempt_mystery("mystery_the_first_vault", "m_player_2", code)
	if not bool(other.get("ok", false)):
		push_error("FAIL: second player could not solve: %s" % str(other))
		return false
	print("[OK] sky-code solve: normalized, toasted, titled, per-player ledger")
	return true


## The observation mystery: the tally of catalogued signs, gated one
## chapter deeper.
func _test_tally_mystery() -> bool:
	_reset_world()
	# Re-earn act 1 ch1 + act 2 ch2 (gate day 3) through door opens.
	_svc._unlocked_days[1] = true
	_acts._on_door_opened(1)
	_svc._unlocked_days[2] = true
	_acts._on_door_opened(2)
	_svc._unlocked_days[3] = true
	_acts._on_door_opened(3)
	if not _acts.is_mystery_unlocked("mystery_the_watcher_tally"):
		push_error("FAIL: tally mystery not unlocked by its gate chapter")
		return false
	var signs: int = _svc._signs.size()
	var wrong: Dictionary = _acts.attempt_mystery("mystery_the_watcher_tally", "t_player", str(signs + 1))
	if bool(wrong.get("ok", true)):
		push_error("FAIL: wrong tally accepted")
		return false
	var right: Dictionary = _acts.attempt_mystery("mystery_the_watcher_tally", "t_player", str(signs))
	if not bool(right.get("ok", false)):
		push_error("FAIL: correct tally (%d) rejected: %s" % [signs, str(right)])
		return false
	var ts = root.get_node_or_null("TitleService")
	if ts == null or not ts.is_unlocked("t_player", "title_wardens_word"):
		push_error("FAIL: warden title not unlocked")
		return false
	print("[OK] tally mystery: catalog-derived answer accepted, title paid")
	return true


## Solved ledgers survive a service reboot (int-key normalize lesson).
func _test_solved_persistence() -> bool:
	if not _acts.is_mystery_solved("mystery_the_first_vault", "m_player"):
		push_error("FAIL: pre-reset state missing")
		return false
	_acts._initialized = false
	_acts._recorded = {}
	_acts._solved = {}
	_acts.ensure_initialized()
	if not _acts.is_mystery_solved("mystery_the_first_vault", "m_player"):
		push_error("FAIL: solved ledger lost across reboot")
		return false
	if not _acts.is_mystery_solved("mystery_the_watcher_tally", "t_player"):
		push_error("FAIL: tally ledger lost across reboot")
		return false
	print("[OK] solved ledgers survive reboot")
	return true


func _load_title_ids() -> Dictionary:
	var out: Dictionary = {}
	var dir := DirAccess.open("res://data/titles")
	if dir == null:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".tres"):
			var txt := FileAccess.get_file_as_string("res://data/titles/%s" % f)
			for line in txt.split("\n"):
				var t := line.strip_edges()
				if t.begins_with("id = \""):
					out[t.trim_prefix("id = \"").trim_suffix("\"")] = true
					break
		f = dir.get_next()
	return out
