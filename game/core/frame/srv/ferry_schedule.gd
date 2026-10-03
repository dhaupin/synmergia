## FerrySchedule - the closed-form ferry timetable as a frame primitive
## (labs conventions: pure functions, no autoload, no class_name,
## co-located test). The below-the-schedule twin of the moon's orbit
## math: the same law the SAILING PAGE and the DOCK both read.
##
## The honesty law (prd-ocean-depths sec 9, landed with the almanac
## sailing page): a schedule is CLOSED FORM off the Concord epoch --
## ferries_per_day departures spread evenly across the sky day,
## first cast-off at first_departure_hour, a crossing taking
## crossing_hours. No timetable table is stored, so the chart in the
## almanac and the dock outside cannot disagree: one derivation, two
## readers (the page already shipped on this; the FerryService now
## rides the SAME primitive -- if the boat and the page ever
## disagreed, this file would be the only place a bug could live).
##
## All epoch inputs are fractional Concord days (SignService
## .sky_epoch_days -- override-aware). Hours are 0..24 floats.
extends RefCounted

## The boarding window in hours: the almanac's "casting off now" is
## the quarter hour before (and at) the cast-off second. The dock
## honors the same window -- board while the page says departing.
const BOARDING_WINDOW_H: float = 0.25


## The departure hours of one sky day, ascending. Zero ferries per
## day = no schedule (an empty list is the honest answer). Hours wrap
## the day: 8 departures starting at 6.0 give
## [0, 3, 6, 9, 12, 15, 18, 21].
static func departure_hours(per_day: int, first_h: float) -> Array[float]:
	var out: Array[float] = []
	if per_day <= 0:
		return out
	var step := 24.0 / float(per_day)
	for k in per_day:
		var h: float = first_h + float(k) * step
		while h >= 24.0:
			h -= 24.0
		out.append(h)
	out.sort()
	return out


## The next cast-off a body would catch, as of `epoch_days`:
##   hour        -- the cast-off's hour within its day (0..24)
##   day_offset  -- 0 today, 1 tomorrow (relative to epoch's day)
##   in_h        -- hours from now
##   departing   -- inside the boarding window (the page's "casting
##                  off now" is the dock's "you may board")
## Returns {} only when there is no schedule at all.
static func next_departure(per_day: int, first_h: float, epoch_days: float) -> Dictionary:
	var hours := departure_hours(per_day, first_h)
	if hours.is_empty():
		return {}
	var now_h: float = fposmod(epoch_days, 1.0) * 24.0
	for h in hours:
		var in_h: float = h - now_h
		if in_h >= 0.0:
			return {"hour": h, "day_offset": 0, "in_h": in_h, \
				"departing": in_h <= BOARDING_WINDOW_H}
	# Every departure today has sailed: tomorrow's first.
	var first: float = hours[0]
	return {"hour": first, "day_offset": 1, "in_h": first + 24.0 - now_h, \
		"departing": first + 24.0 - now_h <= BOARDING_WINDOW_H}


## The crossing a departure is currently running (the boat is at sea),
## as of `epoch_days`. Returns {} between sailings. The cast-off
## INSTANT belongs to the boarding window (board while departing --
## the page's law), so the crossing starts strictly AFTER the
## departure hour: at elapsed == 0 the dock still says boarding.
##   departed_h, day_offset -- when it left (day_offset relative to
##                             epoch's day, 0 or -1)
##   elapsed_h, remaining_h -- the crossing clock
static func crossing_in_progress(per_day: int, first_h: float, cross_h: float, epoch_days: float) -> Dictionary:
	if per_day <= 0 or cross_h <= 0.0:
		return {}
	var now_h: float = fposmod(epoch_days, 1.0) * 24.0
	# Newest sail first: today's departures (day_offset 0) before
	# yesterday's (day_offset -1), and within a day the LATEST hour
	# before now -- a later cast-off is the more recent crossing.
	# Audit round 18: yesterday's leg used dep_h = h + 24, so elapsed
	# = now_h - h - 24 was ALWAYS negative and an overnight crossing
	# (a boat still at sea after midnight) was never reported -- the
	# dock read "in_port" and offered "next cast-off in Xh". Yesterday's
	# hour h sits at h - 24 on today's axis.
	for back in [0, 1]:
		var day_off: int = -back
		var hours := departure_hours(per_day, first_h)
		for i in range(hours.size() - 1, -1, -1):
			var h: float = hours[i]
			var dep_h: float = h - float(back) * 24.0
			var elapsed: float = now_h - dep_h
			if elapsed > 0.0 and elapsed < cross_h:
				return {"departed_h": h, "day_offset": day_off, \
					"elapsed_h": elapsed, "remaining_h": cross_h - elapsed}
	return {}


## The crossing duration in seconds (the service's ride clock; the
## skiff divides by its speed multiplier before calling this).
static func crossing_seconds(cross_h: float) -> float:
	return maxf(cross_h, 0.0) * 3600.0
