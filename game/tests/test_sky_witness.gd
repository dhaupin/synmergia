## Smoke test: the sky-witness achievement wiring (prd-quests.md section 4 --
## achievements celebrate the world's VERBS). The one verb this proves is the
## game's namesake practice: looking up and recording an insight.
##
## Proves the new event source actually reaches AchievementService and that the
## anti-farm guard holds where the guard actually lives:
##   - SignService.record_insight -> insight_recorded -> "insight" track
##   - record_insight() itself de-dupes one insight per player per window, so a
##     repeat gaze of the SAME window must not re-credit (no listener flag).
##
## Run: godot --headless --path . --script res://tests/test_sky_witness.gd
extends SceneTree

var _pass := 0
var _fail := 0


func _initialize() -> void:
	print("--- SKY WITNESS TEST ---")

	var ach = root.get_node_or_null("AchievementService")
	var listeners = root.get_node_or_null("AchievementListeners")
	var signs = root.get_node_or_null("SignService")
	_assert("AchievementService present", ach != null)
	_assert("AchievementListeners present", listeners != null)
	_assert("SignService present", signs != null)
	if ach == null or listeners == null or signs == null:
		_finish()
		return

	# --script mode: force the data + wiring the autoload _ready may not have
	# reached yet (same guard test_waking_verbs uses).
	var ds0 = root.get_node_or_null("DataService")
	if ds0 and not ds0._loaded and ds0.has_method("load_all_data"):
		ds0.load_all_data()
	if signs.has_method("ensure_initialized"):
		signs.ensure_initialized()
	var defs: Array = ach.get_all_achievements()
	if defs.is_empty():
		if ach.has_method("_load_achievement_definitions"):
			ach._load_achievement_definitions()
	defs = ach.get_all_achievements()
	_assert("defs loaded (%d)" % defs.size(), defs.size() >= 10)

	_assert("sky_witness_1 def present", _find_def(defs, "sky_witness_1") != null)
	_assert("sky_witness_10 def present", _find_def(defs, "sky_witness_10") != null)
	_assert("sky_witness_30 def present", _find_def(defs, "sky_witness_30") != null)

	# Connect entry points directly (order-independent under --script).
	listeners._connect_all()
	listeners._connect_insight_bridge()

	_test_first_witness(listeners, ach)
	_test_repeat_gaze_antifarm(listeners, ach, signs)
	_test_ten_insights(listeners, ach)

	_finish()


## A recorded insight wakes "First Witness": the real SignService.record_insight
## path fires insight_recorded, the listener tracks "insight", the global def
## unlocks. The reward grant is local-player-only (see _grant_rewards), so the
## title is exercised directly through TitleService with the id the def names.
func _test_first_witness(listeners, ach) -> void:
	var pid := "witness_player_%d" % Time.get_ticks_msec()
	listeners._on_insight_recorded(pid, "sign_the_awakening", 0)
	_assert("insight_recorded unlocks sky_witness_1", ach.has_unlocked(pid, "sky_witness_1"))
	var ts = root.get_node_or_null("TitleService")
	_assert("TitleService present", ts != null)
	if ts != null:
		ts.unlock(pid, "skywatcher")
		_assert("skywatcher title resolves and unlocks", _title_unlocked(pid, "skywatcher"))


## A repeat gaze of the SAME window must not climb the tier: SignService skips
## the emit entirely on "already recorded", so ten repeat emits for one window
## cannot reach sky_witness_10. (This models the service's own de-dupe: the
## listener sees at most one insight_recorded per player per window.)
func _test_repeat_gaze_antifarm(listeners, ach, signs) -> void:
	var pid := "witness_farm_%d" % Time.get_ticks_msec()
	# Emit the same window's insight once; a single credit must not complete the
	# tier (the service suppresses the rest, so this is the most a gaze can give).
	listeners._on_insight_recorded(pid, "sign_the_sunken_choir", 0)
	_assert("one insight does not farm sky_witness_10",
		not ach.has_unlocked(pid, "sky_witness_10"))
	# And confirm the SERVICE truly de-dupes: two record_insight calls in the
	# SAME window, second must report already-recorded and not double-count.
	var before: int = _insight_progress(ach, pid)
	var r1: Dictionary = signs.record_insight(pid)
	var r2: Dictionary = signs.record_insight(pid)
	if bool(r1.get("ok", false)) and String(r1.get("reason", "")) == "already recorded":
		_assert("repeat gaze of one window is idempotent (already recorded)",
			String(r2.get("reason", "")) == "already recorded")
	else:
		_assert("first gaze records", bool(r1.get("ok", false)))
		_assert("repeat gaze of one window is idempotent (already recorded)",
			String(r2.get("reason", "")) == "already recorded")
	var after: int = _insight_progress(ach, pid)
	_assert("service de-dupe bounds progress growth to <=1 this window",
		after - before <= 1)


## Ten DISTINCT insights unlock the tier.
func _test_ten_insights(listeners, ach) -> void:
	var pid := "witness_ten_%d" % Time.get_ticks_msec()
	for i in 10:
		listeners._on_insight_recorded(pid, "sign_the_awakening", i)
	_assert("ten insights unlock sky_witness_10", ach.has_unlocked(pid, "sky_witness_10"))


func _insight_progress(ach, pid: String) -> int:
	if ach.has_method("get_achievement_progress"):
		var p: Dictionary = ach.get_achievement_progress(pid, "sky_witness_1")
		return int(p.get("progress", 0))
	return 0


func _title_unlocked(player_id: String, title_id: String) -> bool:
	var ts = root.get_node_or_null("TitleService")
	if ts == null or not ts.has_method("is_unlocked"):
		return false
	return bool(ts.is_unlocked(player_id, title_id))


func _find_def(defs: Array, id: String) -> AchievementData:
	for d in defs:
		if d is AchievementData and d.id == id:
			return d
	return null


func _assert(name: String, cond: bool) -> void:
	if cond:
		_pass += 1
		print("  PASS: " + name)
	else:
		_fail += 1
		print("  FAIL: " + name)


func _finish() -> void:
	print("--- %d passed, %d failed ---" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
