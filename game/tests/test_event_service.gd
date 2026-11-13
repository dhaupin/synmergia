## EventService tests — the calendar-to-reward seam.
##
## Drives the REAL path: the live DataService catalog, the shipped
## EventData resource, the recurring-window law, and the two reward
## consumers (KillRewards XP/gold, LootTable drop chance). Time is
## INJECTED so the window logic is deterministic and machine-independent.
##
## Run:
##   godot --headless --path . --script res://tests/test_event_service.gd
extends SceneTree

const EventService = preload("res://core/services/event_service.gd")
const KillRewards = preload("res://core/services/kill_rewards.gd")
const LootTableScript = preload("res://core/schemas/loot_table.gd")
const EVENT_PATH := "res://data/events/event_double_xp_weekend.tres"

var _passed := 0
var _failed := 0


func _initialize() -> void:
	await process_frame
	await _run()
	print("EventService tests: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _run() -> void:
	_test_catalog_loaded()
	_test_window_law()
	_test_recurring_law()
	_test_real_event_window()
	_test_kill_rewards_multiplier()
	_test_loot_drop_multiplier()


## The catalog must be loaded and carry the shipped weekend event.
func _test_catalog_loaded() -> void:
	var ds := root.get_node_or_null("DataService")
	_assert(ds != null, "DataService autoload present")
	if ds == null:
		return
	var evs: Array = ds.get_all_events()
	_assert(evs.size() >= 1, "event catalog loaded from data/events")
	var ids := EventService.active_event_ids("2026-08-29T12:00:00")
	_assert(ids.has("event_double_xp_weekend"),
		"shipped weekend event is open inside its authored window")


## Non-recurring window law: inside / before / after.
func _test_window_law() -> void:
	var ev := _stub_event("2026-01-01T00:00:00", "2026-01-02T00:00:00", false, "weekly")
	_assert(EventService._is_open(ev, EventService._unix("2026-01-01T12:00:00")),
		"one-shot open inside window")
	_assert(not EventService._is_open(ev, EventService._unix("2025-12-31T23:00:00")),
		"one-shot closed before window")
	_assert(not EventService._is_open(ev, EventService._unix("2026-01-02T01:00:00")),
		"one-shot closed after window")
	var open_ended := _stub_event("2026-01-01T00:00:00", "", false, "weekly")
	_assert(EventService._is_open(open_ended, EventService._unix("2030-01-01T00:00:00")),
		"no end_date stays open from start onward")
	var always := _stub_event("", "", false, "")
	_assert(EventService._is_open(always, EventService._unix("2030-01-01T00:00:00")),
		"no start/end is always open")


## Recurring window law: the span repeats every period.
func _test_recurring_law() -> void:
	# A two-day weekend starting Sat 2026-08-29, recurring weekly.
	var ev := _stub_event("2026-08-29T00:00:00", "2026-08-31T00:00:00", true, "weekly")
	_assert(EventService._is_open(ev, EventService._unix("2026-08-29T12:00:00")),
		"recurring open in its first occurrence")
	_assert(not EventService._is_open(ev, EventService._unix("2026-09-02T12:00:00")),
		"recurring closed mid-week (phase past the span)")
	_assert(EventService._is_open(ev, EventService._unix("2026-09-05T12:00:00")),
		"recurring reopens one week later (the 'every weekend' law)")
	_assert(not EventService._is_open(ev, EventService._unix("2026-08-20T12:00:00")),
		"recurring closed before its first occurrence")


## The shipped event's real multiplier, at injected times.
func _test_real_event_window() -> void:
	var inside := EventService.xp_multiplier(1, "", "2026-08-29T12:00:00")
	_assert(absf(inside - 2.0) < 0.001,
		"weekend event doubles XP inside the window (got %.2f)" % inside)
	var outside := EventService.xp_multiplier(1, "", "2026-09-02T12:00:00")
	_assert(absf(outside - 1.0) < 0.001,
		"weekend event is inert mid-week (got %.2f)" % outside)


## KillRewards applies the event XP/gold multiplier. We open the shipped
## event around NOW (the loader cache hands us the same instance the
## catalog holds), then restore it.
func _test_kill_rewards_multiplier() -> void:
	var ev = load(EVENT_PATH)
	if ev == null:
		_fail("could not load the shipped event resource")
		return
	var saved_start: String = ev.start_date
	var saved_end: String = ev.end_date
	var saved_rec: bool = ev.is_recurring
	var saved_xp: float = ev.xp_multiplier
	var saved_gold: float = ev.gold_multiplier

	var now_unix := int(Time.get_unix_time_from_system())
	ev.start_date = Time.get_datetime_string_from_unix_time(now_unix - 3600)
	ev.end_date = Time.get_datetime_string_from_unix_time(now_unix + 3600)
	ev.is_recurring = false
	ev.xp_multiplier = 2.0
	ev.gold_multiplier = 2.0

	var player = _mk_player("ev_player")
	var enemy = _mk_entity("ev_enemy")
	enemy.level = 4
	# Baseline: same kill with the event closed.
	ev.start_date = Time.get_datetime_string_from_unix_time(now_unix + 7200)
	ev.end_date = Time.get_datetime_string_from_unix_time(now_unix + 10800)
	KillRewards.award_kill(enemy, player)
	var base_xp: int = player.experience
	var base_gold: int = player.gold

	# Now open the event and kill an identical enemy.
	player.experience = 0
	player.gold = 0
	ev.start_date = Time.get_datetime_string_from_unix_time(now_unix - 3600)
	ev.end_date = Time.get_datetime_string_from_unix_time(now_unix + 3600)
	KillRewards.award_kill(enemy, player)

	_assert(base_xp > 0, "baseline kill pays XP")
	_assert(player.experience == base_xp * 2,
		"open event doubles kill XP (%d -> %d)" % [base_xp, player.experience])
	_assert(player.gold == base_gold * 2,
		"open event doubles kill gold (%d -> %d)" % [base_gold, player.gold])

	ev.start_date = saved_start
	ev.end_date = saved_end
	ev.is_recurring = saved_rec
	ev.xp_multiplier = saved_xp
	ev.gold_multiplier = saved_gold
	player.free()
	enemy.free()


## LootTable.roll_drop scales its base chance by the drop multiplier and
## clamps at certainty.
func _test_loot_drop_multiplier() -> void:
	var table = LootTableScript.new()
	table.base_drop_chance = 0.5
	var n := 400
	var rolled_1x := 0
	var rolled_2x := 0
	var rng1 := RandomNumberGenerator.new()
	rng1.seed = 12345
	for i in range(n):
		if table.roll_drop(rng1, 1.0).get("rolled", false):
			rolled_1x += 1
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 12345
	for i in range(n):
		if table.roll_drop(rng2, 2.0).get("rolled", false):
			rolled_2x += 1
	_assert(rolled_1x > 0 and rolled_1x < n, "1x drop chance is probabilistic")
	_assert(rolled_2x == n, "2x drop multiplier clamps to certainty (%d/%d)" % [rolled_2x, n])


# --- helpers ---------------------------------------------------------------

## A real EventData instance, so get()/getter semantics match the live
## catalog exactly.
func _stub_event(start: String, end: String, recurring: bool, pattern: String) -> Resource:
	var s = load("res://core/schemas/event_data.gd")
	var ev = s.new()
	ev.id = "test_event"
	ev.start_date = start
	ev.end_date = end
	ev.is_recurring = recurring
	ev.recurrence_pattern = pattern
	return ev


func _mk_entity(id: String):
	var s = load("res://tests/support/reward_enemy_stub.gd")
	var e = s.new()
	e.entity_id = id
	e.display_name = id
	root.add_child(e)
	return e


func _mk_player(id: String):
	var s = load("res://core/entities/entity.gd")
	var p = s.new()
	p.entity_id = id
	p.display_name = id
	p.set_script(load("res://tests/support/reward_player_stub.gd"))
	root.add_child(p)
	return p


func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		push_error("FAIL: " + msg)


func _fail(msg: String) -> void:
	_failed += 1
	push_error("FAIL: " + msg)
