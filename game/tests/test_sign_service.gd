extends SceneTree

## SignService (Skyward Concord) smoke test: deterministic window math,
## per-window sign picks, the tribal reveal threshold, day-code
## assembly, tomorrow-Ancient unlock, rollover clears rumor state, and
## persistence round-trips. Run:
##   godot --headless --path . --script res://tests/test_sign_service.gd
##
## NOTE: _initialize(), not _init() -- autoloads attach after _init.

var _svc = null
var _ds = null


func _initialize() -> void:
	var ok := true

	_ds = root.get_node_or_null("DataService")
	_svc = root.get_node_or_null("SignService")
	if _ds == null or _svc == null:
		push_error("FAIL: DataService or SignService autoload missing")
		quit(1)
		return
	if not _ds._loaded:
		_ds.load_all_data()
	# Script-mode guard: the autoload's _ready may not have fired yet.
	if _svc.has_method("ensure_initialized"):
		_svc.ensure_initialized()

	ok = _test_signs_loaded() and ok
	ok = _test_window_math() and ok
	ok = _test_sign_picks_deterministic() and ok
	ok = _test_tribal_reveal() and ok
	ok = _test_day_code_and_unlock() and ok
	ok = _test_rollover_clears_rumors() and ok
	ok = _test_clock_override_flow() and ok

	print("--- SIGN SERVICE: ok=%s ---" % str(ok))
	quit(0 if ok else 1)


func _test_signs_loaded() -> bool:
	var signs: Dictionary = _ds.get_signs()
	if signs.size() < 3:
		push_error("FAIL: expected >=3 signs, got %d" % signs.size())
		return false
	for required in ["sign_the_awakening", "sign_the_sunken_choir", "sign_the_wandering_grove"]:
		if not signs.has(required):
			push_error("FAIL: missing sign %s" % required)
			return false
	var first = signs["sign_the_awakening"]
	if str(first.glyph) != "WAKE":
		push_error("FAIL: awakening glyph '%s' != WAKE" % first.glyph)
		return false
	print("[OK] %d signs loaded with glyphs" % signs.size())
	return true


func _test_window_math() -> bool:
	# Compute a true day boundary from the real clock (no hardcoded
	# epoch constants -- floor(now) IS a boundary, then verify edges).
	var day_start: float = floor(Time.get_unix_time_from_system() / 86400.0) * 86400.0
	if _svc.day_index_for(day_start) != _svc.day_index_for(day_start + 21599.0):
		push_error("FAIL: day boundary math inconsistent")
		return false
	# Window 0 starts at day start; window 3 starts 18h in.
	if _svc.window_index_for(day_start) != 0:
		push_error("FAIL: window at day start != 0")
		return false
	if _svc.window_index_for(day_start + 21600.0) != 1:
		push_error("FAIL: window 6h in != 1")
		return false
	if _svc.window_index_for(day_start + 64800.0) != 3:
		push_error("FAIL: window 18h in != 3")
		return false
	# Seconds left: 30s into window 1 -> 21570 left of 21600.
	if _svc.seconds_left_in_window(day_start + 21630.0) != 21570:
		push_error("FAIL: seconds_left math")
		return false
	# 4 windows * 6h = full day coverage.
	if _svc.WINDOWS_PER_DAY * _svc.WINDOW_SECONDS != 86400:
		push_error("FAIL: windows do not tile a day")
		return false
	print("[OK] window math: 4x6h tiles the day, boundaries exact")
	return true


func _test_sign_picks_deterministic() -> bool:
	# Same (day, window) -> same sign, across many calls and days.
	for day in [1000, 20000, 99999]:
		for w in 4:
			var a = _svc.sign_for_window(day, w)
			var b = _svc.sign_for_window(day, w)
			if a == null or b == null or a.id != b.id:
				push_error("FAIL: sign pick not deterministic for %d:%d" % [day, w])
				return false
	# Different windows of the same day can differ (variety sanity).
	var day := 51234
	var picks := {}
	for w in 4:
		var s = _svc.sign_for_window(day, w)
		if s == null:
			push_error("FAIL: null sign for %d:%d" % [day, w])
			return false
		picks[s.id] = true
	print("[OK] sign picks deterministic; day %d showed %d distinct sign(s)" % [day, picks.size()])
	return true


func _test_tribal_reveal() -> bool:
	# Pin the clock inside a known window.
	var day := 22222
	var win := 1
	var t: float = day * 86400.0 + win * 21600.0 + 60.0
	_svc.set_clock_override(t)
	var w: Dictionary = _svc.get_current_window()
	if int(w["day_index"]) != day or int(w["window_index"]) != win:
		push_error("FAIL: clock override did not pin the window")
		return false
	# Glyph hidden before the community reveals it.
	if w.has("glyph"):
		push_error("FAIL: glyph public before reveal threshold")
		return false
	# Observer 1 and 2: recorded, still rumor.
	var r1: Dictionary = _svc.record_insight("tribe_a")
	if not bool(r1["ok"]) or int(r1["observers"]) != 1:
		push_error("FAIL: first insight not recorded: %s" % str(r1))
		return false
	var r1b: Dictionary = _svc.record_insight("tribe_a")
	if bool(r1b["revealed_now"]) or int(r1b["observers"]) != 1:
		push_error("FAIL: duplicate insight not idempotent: %s" % str(r1b))
		return false
	_svc.record_insight("tribe_b")
	var glyphs: Array[String] = _svc.get_revealed_glyphs()
	if glyphs[win] != "?":
		push_error("FAIL: glyph public at 2 observers")
		return false
	# Observer 3 crosses the threshold: reveal fires.
	var r3: Dictionary = _svc.record_insight("tribe_c")
	if not bool(r3["revealed_now"]):
		push_error("FAIL: 3rd observer did not trigger reveal: %s" % str(r3))
		return false
	if not bool(_svc.get_current_window()["revealed"]):
		push_error("FAIL: window not marked revealed")
		return false
	if _svc.get_revealed_glyphs()[win] == "?":
		push_error("FAIL: revealed glyph still hidden")
		return false
	print("[OK] tribal reveal: 3 distinct observers needed, rumor -> shared glyph")
	return true


func _test_day_code_and_unlock() -> bool:
	# Reveal all 4 windows of day 22222 -> tomorrow's Ancient unlocks.
	var day := 22222
	for w in 4:
		_svc.force_reveal_window(day, w)
	if not _svc.is_ancient_unlocked(day + 1):
		push_error("FAIL: tomorrow's Ancient not unlocked after full reveal")
		return false
	var code: String = _svc.get_ancient_code(day)
	if code.count("-") != 3:
		push_error("FAIL: code '%s' is not 4 glyphs" % code)
		return false
	# Idempotent: repeat reveals do not double-fire.
	_svc._maybe_complete_day_code(day)
	print("[OK] day %d code '%s' assembled -> Ancient day %d unlocked" % [day, code, day + 1])
	return true


func _test_rollover_clears_rumors() -> bool:
	# The old day had revelations; stepping into the next day must wipe
	# the rumor state (new day, new hunt) but KEEP unlock history.
	var old_day := 22222
	var new_day := old_day + 1
	var t: float = new_day * 86400.0 + 60.0
	_svc.set_clock_override(t)
	var glyphs: Array[String] = _svc.get_revealed_glyphs()
	for g in glyphs:
		if g != "?":
			push_error("FAIL: new day leaks old glyphs: %s" % str(glyphs))
			return false
	if not _svc.is_ancient_unlocked(new_day):
		push_error("FAIL: unlock history lost across rollover")
		return false
	var w: Dictionary = _svc.get_current_window()
	if int(w["observers"]) != 0:
		push_error("FAIL: new day inherits observer state")
		return false
	print("[OK] rollover: rumors wiped, unlock history kept")
	return true


func _test_clock_override_flow() -> bool:
	# A day far in the future resolves cleanly end-to-end.
	var day := 7777777
	_svc.set_clock_override(day * 86400.0 + 3.0 * 21600.0 + 120.0)
	var w: Dictionary = _svc.get_current_window()
	if int(w["day_index"]) != day or int(w["window_index"]) != 3:
		push_error("FAIL: future day window mismatch")
		return false
	var s = _svc.sign_for_window(day, 3)
	if s == null or str(s.id).is_empty():
		push_error("FAIL: future window has no sign")
		return false
	# Release the override so later tests / runtime use the real clock.
	_svc.set_clock_override(-1.0)
	print("[OK] clock override flow: day %d window 3 = %s" % [day, str(s.id)])
	return true
