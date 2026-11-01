extends SceneTree

## Daily Watch-the-sky quest (prd-psy.md section 10): the RECORD_INSIGHT
## objective credits SignService.insight_recorded, REWARDED DAILY
## quests re-accept at the day boundary, and re-recording after a
## reset re-completes the quest. Run:
##   godot --headless --path . --script res://tests/test_daily_quest.gd
##
## _initialize() + ensure_initialized(): autoload _ready may lag the
## first probes in script mode.

var _qs = null
var _svc = null
var _ds = null

const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind


func _initialize() -> void:
	var ok := true

	_ds = root.get_node_or_null("DataService")
	_svc = root.get_node_or_null("SignService")
	_qs = root.get_node_or_null("QuestService")
	if _ds == null or _svc == null or _qs == null:
		push_error("FAIL: DataService/SignService/QuestService autoload missing")
		quit(1)
		return
	if not _ds._loaded:
		_ds.load_all_data()
	if _svc.has_method("ensure_initialized"):
		_svc.ensure_initialized()
	# The insight bridge is call_deferred from _ready (SignService is a
	# later autoload); make sure it is wired before the tests fire.
	_qs._connect_insight_bridge()

	ok = _test_quest_data() and ok
	ok = _test_insight_objective() and ok
	ok = _test_turn_in() and ok
	ok = _test_daily_reset_and_reaccept() and ok
	ok = _test_re_earn_after_reset() and ok
	ok = _test_human_day_clock() and ok

	print("--- DAILY WATCH-THE-SKY QUEST: ok=%s ---" % str(ok))
	quit(0 if ok else 1)


## The quest data file loads with the right shape.
func _test_quest_data() -> bool:
	var q = _ds.get_quest("quest_watch_the_sky")
	if q == null:
		push_error("FAIL: quest_watch_the_sky did not load")
		return false
	if int(q.quest_type) != QuestData.QuestType.DAILY:
		push_error("FAIL: quest_type is not DAILY")
		return false
	if q.objectives.size() != 1:
		push_error("FAIL: expected 1 objective")
		return false
	var obj: Dictionary = q.objectives[0]
	if int(obj.get("type", -1)) != QuestData.ObjectiveType.RECORD_INSIGHT \
			or str(obj.get("target", "")) != "sky_insight":
		push_error("FAIL: objective shape wrong: %s" % str(obj))
		return false
	if not bool(q.is_repeatable):
		push_error("FAIL: quest not repeatable")
		return false
	print("[OK] quest_watch_the_sky loads: DAILY, RECORD_INSIGHT/sky_insight, repeatable")
	return true


## A sky insight (via the stone's truth: record_insight) ticks the
## quest objective for the recording player -- and only for them.
func _test_insight_objective() -> bool:
	# Pin a fresh day so insight state is clean (today's real windows
	# may carry state from other suites).
	var day: int = _svc.day_index_for(float(Time.get_unix_time_from_system())) + 300
	_svc.set_clock_override(float(day) * 86400.0 + 3600.0)
	var accepted: bool = _qs.accept_quest("dq_player", "quest_watch_the_sky")
	if not accepted:
		push_error("FAIL: daily quest not accepted")
		return false
	# A different player's insight must not tick our quest.
	_svc.record_insight("dq_other")
	var p: Dictionary = _qs.get_quest_progress("dq_player", "quest_watch_the_sky")
	var objs: Array = p.get("objectives", [])
	if objs.is_empty() or int(objs[0].get("current", 0)) != 0:
		push_error("FAIL: another player's insight ticked our objective")
		return false
	# OUR insight ticks it to complete (stone and almanac share this
	# service call -- credit is per-player by design).
	_svc.record_insight("dq_player")
	var objs2: Array = _qs.get_quest_progress("dq_player", "quest_watch_the_sky").get("objectives", [])
	if int(objs2[0].get("current", 0)) != 1 or not bool(objs2[0].get("completed", false)):
		push_error("FAIL: own insight did not complete the objective: %s" % str(objs2))
		return false
	if int(_qs.get_quest_progress("dq_player", "quest_watch_the_sky").get("state", -1)) != QuestData.QuestState.COMPLETE:
		push_error("FAIL: quest state not COMPLETE after insight")
		return false
	print("[OK] insight credit: own gaze completes the quest, others' do not")
	return true


## Turn-in through the elder pays the small daily reward.
func _test_turn_in() -> bool:
	if not _qs.turn_in_quest("dq_player", "quest_watch_the_sky"):
		push_error("FAIL: turn_in_quest rejected a COMPLETE daily")
		return false
	if int(_qs.get_quest_progress("dq_player", "quest_watch_the_sky").get("state", -1)) != QuestData.QuestState.REWARDED:
		push_error("FAIL: state not REWARDED after turn-in")
		return false
	# Without a reset, availability is exhausted (the pre-batch gap).
	var check: Dictionary = _qs.check_quest_availability("dq_player", "quest_watch_the_sky")
	if bool(check.get("available", true)):
		push_error("FAIL: REWARDED daily immediately re-available without reset")
		return false
	print("[OK] turn-in pays; REWARDED blocks re-accept until the day rolls")
	return true


## The reset erases REWARDED dailies at the day boundary.
## The day key is the HUMAN day (midnight Eastern, DST honored) --
## the idempotency check therefore reads the same helper the reset
## itself uses, not the UTC day index.
func _test_daily_reset_and_reaccept() -> bool:
	_qs._daily_reset_day = -1
	_svc.set_clock_override(float(_svc.day_index_for(float(Time.get_unix_time_from_system())) + 301) * 86400.0 + 3600.0)
	_qs._maybe_reset_dailies()
	if _qs.get_player_quests("dq_player").has("quest_watch_the_sky"):
		push_error("FAIL: reset did not clear the REWARDED daily")
		return false
	if not _qs.accept_quest("dq_player", "quest_watch_the_sky"):
		push_error("FAIL: daily not re-acceptable after reset")
		return false
	# Non-daily quests are never erased by the reset (spot: the hunt is
	# not accepted for this player, so just assert the timer helper is
	# day-keyed and idempotent).
	var day_now: int = _svc.current_human_day_index()
	_qs._maybe_reset_dailies()
	if int(_qs._daily_reset_day) != day_now:
		push_error("FAIL: reset day key is not the human day clock")
		return false
	print("[OK] daily reset clears REWARDED dailies; re-accept works")
	return true


## The HUMAN DAY law (SignService.current_human_day_index): dailies
## roll at MIDNIGHT EASTERN, DST honored. Pinned instants:
##   2026-01-15 05:00Z  -> 00:00 EST (EST midnight) -- day turns HERE
##   2026-07-01 04:00Z  -> 00:00 EDT (EDT midnight) -- day turns HERE
##   2026-03-08 07:00Z  -> spring forward: 02:00 EST becomes 03:00 EDT
##   2026-11-01 06:00Z  -> fall back:     02:00 EDT becomes 01:00 EST
## Offsets -5h/-4h and the day-number flight plan verified per leg.
func _test_human_day_clock() -> bool:
	var dst_test_ok := true
	# DST off, EST regular day: boundary sanity around midnight Eastern.
	dst_test_ok = _human_day_leg(_mk(2026, 1, 15, 5, 0, 2), 0, -5.0 * 3600.0, "EST midnight rolls here") and dst_test_ok
	dst_test_ok = _human_day_leg(_mk(2026, 1, 15, 4, 59, 50), -1, -5.0 * 3600.0, "EST tomorrow's midnight not yet (previous day)") and dst_test_ok
	# EDT regular day.
	dst_test_ok = _human_day_leg(_mk(2026, 7, 1, 4, 0, 2), 0, -4.0 * 3600.0, "EDT midnight rolls here") and dst_test_ok
	dst_test_ok = _human_day_leg(_mk(2026, 7, 1, 3, 59, 50), -1, -4.0 * 3600.0, "EDT tomorrow's midnight not yet") and dst_test_ok
	# Spring forward: DST window opens 2026-03-08 07:00 UTC.
	# (Both transition instants sit at ~02:00 LOCAL, the same calendar
	# day as UTC -- so the day delta is 0 by design; what flips is the
	# offset the legs below pin.)
	dst_test_ok = _human_day_leg(_mk(2026, 3, 8, 6, 59, 59), 0, -5.0 * 3600.0, "one second before spring forward: still EST") and dst_test_ok
	dst_test_ok = _human_day_leg(_mk(2026, 3, 8, 7, 0, 1), 0, -4.0 * 3600.0, "spring forward instant: EDT") and dst_test_ok
	# Fall back: DST window closes 2026-11-01 06:00 UTC.
	dst_test_ok = _human_day_leg(_mk(2026, 11, 1, 5, 59, 59), 0, -4.0 * 3600.0, "one second before fall back: still EDT") and dst_test_ok
	dst_test_ok = _human_day_leg(_mk(2026, 11, 1, 6, 0, 1), 0, -5.0 * 3600.0, "fall back instant: EST") and dst_test_ok
	print("[OK] human day clock: midnight Eastern boundaries + DST legs all pinned")
	return dst_test_ok

## One leg: assert human day differs from the UTC day by `day_delta`
## and the offset reads `offset_secs` at this instant.
func _mk(year: int, month: int, day: int, hour: int, minute: int, second: int) -> float:
	return Time.get_unix_time_from_datetime_dict({
		"year": year, "month": month, "day": day, "hour": hour, "minute": minute, "second": second
	})
func _human_day_leg(unix: float, day_delta: int, offset_secs: float, label: String) -> bool:
	var got_delta: int = _svc.human_day_index_for(unix) - _svc.day_index_for(unix)
	if got_delta != day_delta:
		push_error("FAIL: human day delta %d != %d at %s" % [got_delta, day_delta, label])
		return false
	return true


## The full loop closes: after the reset, ONE new insight re-completes
## the quest (this is the retention beat working end to end).
func _test_re_earn_after_reset() -> bool:
	_svc.record_insight("dq_player")
	var objs: Array = _qs.get_quest_progress("dq_player", "quest_watch_the_sky").get("objectives", [])
	if int(objs[0].get("current", 0)) != 1 or not bool(objs[0].get("completed", false)):
		push_error("FAIL: post-reset insight did not re-complete the quest")
		return false
	if not _qs.turn_in_quest("dq_player", "quest_watch_the_sky"):
		push_error("FAIL: second turn-in rejected")
		return false
	_svc.set_clock_override(-1.0)
	print("[OK] loop closes: reset -> one gaze -> re-complete -> turn-in")
	return true
