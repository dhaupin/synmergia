## EventService — the calendar-to-reward seam for global event modifiers.
##
## EventData (data/events/*.tres) authored the modifier surface — an XP
## boost weekend, a gold boost, a drop boost — but nothing ever READ it:
## DataService loaded the catalog, then get_event()/get_all_events() had
## zero callers, is_within_time_range()/get_xp_multiplier() were dead, and
## nothing anywhere consumed xp_multiplier / gold_multiplier /
## drop_rate_multiplier. The one shipped event (a recurring "Double XP
## Weekend") was therefore inert, and its reward line named an item that
## did not exist.
##
## This is the bridge. It answers ONE question for the reward paths:
## "what is the event multiplier for XP / gold / drops right now?" — a
## product over every event whose window is currently open (and whose
## zone/level scope matches), defaulting to 1.0 with no events.
##
## Preload-only static utility: no autoload, no class_name (AGENTS.md
## frame/service conventions). The autoload catalog is late-resolved, so
## bare Entities and --script test mode never touch a bare identifier.
##
## Window law: stamps are ISO-8601 UTC and compared as unix seconds
## (timezone-consistent, unlike the raw string compare the schema used).
## A RECURRING event repeats its authored [start, end] SPAN every
## `recurrence_pattern` (weekly default; daily / monthly understood), so a
## weekly "weekend" is live every weekend instead of only its authored
## dates. A one-shot event with no end_date is open from its start onward;
## with no start_date it is always open.
extends RefCounted

const WEEK_SECONDS := 604800
const DAY_SECONDS := 86400
const MONTH_SECONDS := 2592000  # 30 days


## Product of xp_multiplier over every currently-open event.
static func xp_multiplier(entity_level: int = 0, zone_id: String = "", now: String = "") -> float:
	return _product("xp_multiplier", entity_level, zone_id, now)


## Product of gold_multiplier over every currently-open event.
static func gold_multiplier(entity_level: int = 0, zone_id: String = "", now: String = "") -> float:
	return _product("gold_multiplier", entity_level, zone_id, now)


## Product of drop_rate_multiplier over every currently-open event.
static func drop_multiplier(entity_level: int = 0, zone_id: String = "", now: String = "") -> float:
	return _product("drop_rate_multiplier", entity_level, zone_id, now)


## Ids of every event open at `now` (empty catalog or no match -> empty).
static func active_event_ids(now: String = "") -> Array[String]:
	var out: Array[String] = []
	var ds := _data_service()
	if ds == null or not ds.has_method("get_all_events"):
		return out
	var when := _unix(now)
	for ev in ds.get_all_events():
		if _is_open(ev, when):
			out.append(str(ev.get("id")))
	return out


## Shared product: fold one modifier field across the open events. An
## event whose level/zone scope excludes this kill contributes 1.0, not
## a zero — the multiplier is a no-op for out-of-scope targets.
static func _product(field: String, entity_level: int, zone_id: String, now: String) -> float:
	var product := 1.0
	var ds := _data_service()
	if ds == null or not ds.has_method("get_all_events"):
		return product
	var when := _unix(now)
	for ev in ds.get_all_events():
		if not _is_open(ev, when):
			continue
		if entity_level > 0 and ev.has_method("affects_level") and not ev.affects_level(entity_level):
			continue
		if zone_id != "" and ev.has_method("affects_zone") and not ev.affects_zone(zone_id):
			continue
		var mult := float(ev.get(field))
		if mult != 0.0:
			product *= mult
	return product


## Is the event open at unix time `when`? Derives activeness from the
## authored window (the .tres `_status` field is runtime-only and never
## set by data, so is_active() alone would report every event dead).
static func _is_open(ev, when: int) -> bool:
	if ev == null:
		return false
	var start := str(ev.get("start_date"))
	var end := str(ev.get("end_date"))
	if start.is_empty() and end.is_empty():
		return true
	if bool(ev.get("is_recurring")):
		return _recurring_open(ev, start, end, when)
	var s := _unix(start)
	var e := _unix(end)
	if start.is_empty():
		return when <= e
	if end.is_empty():
		return when >= s
	return when >= s and when <= e


## A recurring event repeats its authored span every period. Phase = how
## far `when` sits past the first start, modulo the period; the event is
## open while that phase is inside the authored duration.
static func _recurring_open(ev, start: String, end: String, when: int) -> bool:
	if start.is_empty() or end.is_empty():
		return true
	var s := _unix(start)
	var e := _unix(end)
	if s <= 0 or e < s:
		return false
	if when < s:
		return false  # before the first occurrence
	var duration := e - s
	var period := _period_seconds(str(ev.get("recurrence_pattern")))
	if period <= 0:
		return when <= e
	return (when - s) % period <= duration


static func _period_seconds(pattern: String) -> int:
	match pattern.strip_edges().to_lower():
		"daily":
			return DAY_SECONDS
		"monthly":
			return MONTH_SECONDS
		"weekly":
			return WEEK_SECONDS
		_:
			return WEEK_SECONDS


## Injected stamp -> unix seconds; "" means the real clock.
static func _unix(stamp: String) -> int:
	if stamp.is_empty():
		return int(Time.get_unix_time_from_system())
	return int(Time.get_unix_time_from_datetime_string(stamp))


## Parse-time autoload edge in --script mode: resolve through the tree,
## never the bare identifier.
static func _data_service() -> Node:
	var ml := Engine.get_main_loop()
	if ml == null or not (ml is SceneTree):
		return null
	return (ml as SceneTree).root.get_node_or_null(NodePath("DataService"))
