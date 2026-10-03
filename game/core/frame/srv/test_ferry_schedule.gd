extends SceneTree

## FerrySchedule frame primitive: the closed-form schedule both the
## almanac page and the dock read. Pure math -- no autoloads needed.
## Run: godot --headless --path . --script res://core/frame/srv/test_ferry_schedule.gd

var _checks: int = 0
var _fails: int = 0

func _init() -> void:
	var FS = load("res://core/frame/srv/ferry_schedule.gd")

	# The Haven Ferry's declaration: 8/day, first 06:00, 0.5 h crossing.
	var HOURS: Array[float] = FS.departure_hours(8, 6.0)
	_check("8 ferries a day give 8 departure hours", HOURS.size() == 8)
	_check("the spread wraps the day evenly (0,3,...,21)", \
		absf(HOURS[0] - 0.0) < 1e-9 and absf(HOURS[3] - 9.0) < 1e-9 \
		and absf(HOURS[7] - 21.0) < 1e-9)

	# Next departure, deterministic epochs.
	var d = FS.next_departure(8, 6.0, 100.0 + 5.0 / 24.0)  # day 100, 05:00
	_check("at 05:00 the 06:00 boat is one hour out", \
		not d.is_empty() and absf(float(d["hour"]) - 6.0) < 1e-9 \
		and int(d["day_offset"]) == 0 and absf(float(d["in_h"]) - 1.0) < 1e-9 \
		and not bool(d["departing"]))
	var d2 = FS.next_departure(8, 6.0, 100.0 + 9.0 / 24.0)  # 09:00 exactly
	_check("at 09:00 the 09:00 boat departs (in the window)", \
		absf(float(d2["hour"]) - 9.0) < 1e-9 and absf(float(d2["in_h"])) < 1e-9 \
		and bool(d2["departing"]))
	var d3 = FS.next_departure(8, 6.0, 100.0 + 9.2 / 24.0)  # 09:12
	_check("12 minutes past cast-off the boat is GONE (next is 12:00 today)", \
		absf(float(d3["hour"]) - 12.0) < 1e-9 and int(d3["day_offset"]) == 0 \
		and absf(float(d3["in_h"]) - 2.8) < 1e-9 and not bool(d3["departing"]))

	# Crossing in progress: the 09:00 boat at 09:18 (18 min in of 30).
	var c = FS.crossing_in_progress(8, 6.0, 0.5, 100.0 + 9.3 / 24.0)
	_check("the 09:00 boat at 09:18 is at sea, 12 minutes left", \
		not c.is_empty() and absf(float(c["departed_h"]) - 9.0) < 1e-9 \
		and int(c["day_offset"]) == 0 and absf(float(c["elapsed_h"]) - 0.3) < 1e-9 \
		and absf(float(c["remaining_h"]) - 0.2) < 1e-9)
	# Just after arrival (09:31): no crossing. (Exact-boundary epochs
	# are float-flaky by construction; one clock read, safely inside.)
	var c2 = FS.crossing_in_progress(8, 6.0, 0.5, 100.0 + (9.5 + 1.0 / 60.0) / 24.0)
	_check("at 09:31 the crossing is over (the boat is in port)", c2.is_empty())
	# A crossing that SPANS midnight: a 3.5 h crossing -- and with 8
	# departures a day there is a 00:00 boat, so the vessel at sea at
	# 00:06 is TODAY'S first (the wrap-scan prefers the newest sail).
	var c3 = FS.crossing_in_progress(8, 6.0, 3.5, 100.0 + 0.1 / 24.0)
	_check("at 00:06 the 00:00 boat (3.5 h crossing) is at sea", \
		not c3.is_empty() and int(c3["day_offset"]) == 0 \
		and absf(float(c3["departed_h"])) < 1e-9 \
		and absf(float(c3["elapsed_h"]) - 0.1) < 1e-9 \
		and absf(float(c3["remaining_h"]) - 3.4) < 1e-9)
	# A sparser schedule (2/day: 06:00 and 18:00) with a 3.5 h crossing.
	var c4 = FS.crossing_in_progress(2, 6.0, 3.5, 100.0 + 8.0 / 24.0)
	_check("a two-ferry day finds the 06:00 boat at sea at 08:00", \
		not c4.is_empty() and absf(float(c4["departed_h"]) - 6.0) < 1e-9 \
		and absf(float(c4["remaining_h"]) - 1.5) < 1e-9)

	# Audit round 18: a crossing that departed YESTERDAY and is still
	# running TODAY must be seen (day_offset -1). One ferry a day at
	# 20:00 with a 6 h crossing is at sea at 01:00.
	var overnight = FS.crossing_in_progress(1, 20.0, 6.0, 100.0 + 1.0 / 24.0)
	_check("an overnight crossing is seen at 01:00 (departed yesterday)", \
		not overnight.is_empty() and int(overnight["day_offset"]) == -1 \
		and absf(float(overnight["departed_h"]) - 20.0) < 1e-9 \
		and absf(float(overnight["elapsed_h"]) - 5.0) < 1e-9 \
		and absf(float(overnight["remaining_h"]) - 1.0) < 1e-9)
	var overnight_done = FS.crossing_in_progress(1, 20.0, 6.0, 100.0 + 2.5 / 24.0)
	_check("the overnight crossing is over at 02:30", overnight_done.is_empty())
	# Newest-sail preference: with a 7 h crossing (step 3 h) two boats are
	# at sea at 09:00 (03:00 and 06:00) -- the more recent one is reported.
	var newest = FS.crossing_in_progress(8, 6.0, 7.0, 100.0 + 9.0 / 24.0)
	_check("two simultaneous sails report the newest (06:00)", \
		absf(float(newest["departed_h"]) - 6.0) < 1e-9 \
		and absf(float(newest["elapsed_h"]) - 3.0) < 1e-9)

	# The empty schedule is honest.
	_check("no schedule: no departures, no crossing", \
		FS.departure_hours(0, 6.0).is_empty() \
		and FS.next_departure(0, 6.0, 100.0).is_empty() \
		and FS.crossing_in_progress(0, 6.0, 0.5, 100.0).is_empty())

	# The boarding window is the page's "casting off now".
	var w = FS.next_departure(8, 6.0, 100.0 + 5.95 / 24.0)  # 05:57
	_check("05:57 is inside the boarding window (board while departing)", \
		bool(w["departing"]) and absf(float(w["in_h"]) - 0.05) < 1e-9)

	if _fails == 0:
		print("FERRY SCHEDULE TEST PASSED (%d checks)" % _checks)
		quit(0)
	else:
		push_error("FERRY SCHEDULE TEST FAILED")
		quit(1)

func _check(label: String, cond: bool) -> void:
	_checks += 1
	if cond:
		print("  PASS " + label)
	else:
		_fails += 1
		print("  FAIL " + label)
