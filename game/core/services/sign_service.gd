## SignService -- the Skyward Concord (labs/prd-psy.md)
##
## The shard's communal sky clock. Four 6-hour windows per day; each
## window shows exactly one Sign (a data-defined celestial arrangement,
## data/signs/*.tres). Observant players who LOOK UP during a window
## record an Insight -- but one glyph alone is not the code. The DAY's
## code is the ordered glyph sequence across all four windows, and it
## unlocks TOMORROW's Ancient (server-wide door/vault).
##
## The tribal rule: a window's glyph only becomes PUBLIC once
## REVEAL_OBSERVERS distinct players have recorded the Insight that
## window. Until then the glyph is rumor -- players must gather, compare
## notes, and make sure someone is watching the sky in every window,
## including the 3 a.m. one. No single player can complete a day alone
## unless they no-life all four windows (we see you, and we salute you).
##
## Determinism: window -> Sign picks are a pure hash of (day, window),
## so every client and the server agree without sync, and past days can
## always be re-derived for lore/vault verification.
##
## Persistence mirrors AntiCheatService: DictStore KV, loaded in
## _ready(), written on change. Autoload ORDER: must be listed after
## DataService (resolves sign data there at _ready).
extends Node

const DictStore = preload("res://adapters/persistence/dict_store.gd")
const SignProfileScript = preload("res://core/schemas/sign_profile.gd")
const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind

signal sign_window_changed(sign_id: String, window_index: int, day_index: int)
signal insight_recorded(player_id: String, sign_id: String, window_index: int)
signal ancient_unlocked(for_day_index: int, code: String)

## Four 6-hour windows per day (UTC-aligned; the world clock IS the sky).
const WINDOWS_PER_DAY: int = 4
const WINDOW_SECONDS: int = 6 * 3600
## Distinct observers needed before a window's glyph goes public.
const REVEAL_OBSERVERS: int = 3
## Max stored observers per window (oldest dropped) -- bounds persistence.
const MAX_INSIGHTS_PER_WINDOW: int = 64

const _KV := "signs:"

var _signs: Dictionary = {}
var _sign_ids: Array[String] = []
## Test/admin clock override (unix seconds); -1 = use the real clock.
var _clock_override: float = -1.0

var _current_day: int = -1
## Guard for ensure_initialized(): _ready may not have fired yet when
## script-mode tests resolve the autoload (autoloads attach after
## _init but their _ready runs once the main loop starts).
var _initialized: bool = false
## window_key ("day:window") -> {player_id: true}
var _insights: Dictionary = {}
## window_key -> true (glyph public for this window)
var _revealed: Dictionary = {}
## day_index -> true (that day's Ancient door is unlocked server-wide)
var _unlocked_days: Dictionary = {}


func _ready() -> void:
	ensure_initialized()


## Idempotent boot: safe to call from _ready AND from script-mode tests
## that resolve the autoload before its _ready has run.
func ensure_initialized() -> void:
	if _initialized:
		return
	_initialized = true
	_load_signs()
	_load_state()
	_maybe_roll_day()
	# Cheap drift check; real work only happens when the day flips.
	var timer := Timer.new()
	timer.wait_time = 60.0
	timer.autostart = true
	timer.timeout.connect(_maybe_roll_day)
	add_child(timer)
	# Blessed-class login toast (prd-psy.md section 8).
	if GameManager != null and not GameManager.player_entered_world.is_connected(_on_player_entered_world):
		GameManager.player_entered_world.connect(_on_player_entered_world)
	GameLog.info("SignService: Concord active (%d signs, day %d)" % [_sign_ids.size(), _current_day])


## Unix seconds now (overridable for tests/admin time travel).
func _now_unix() -> float:
	if _clock_override >= 0.0:
		return _clock_override
	return float(Time.get_unix_time_from_system())


# ------------------------------------------------------------------
# Window math (pure, deterministic -- no state touched)
# ------------------------------------------------------------------

## Epoch day index for a unix timestamp.
func day_index_for(unix: float) -> int:
	return int(floor(unix / 86400.0))


## Epoch day index of "now" (honors the test/admin clock override).
## Services that key daily state off the sky MUST use this, not the
## raw clock, or admin time-travel desyncs their calendars.
func current_day_index() -> int:
	return day_index_for(_now_unix())


## The canonical sky-clock epoch in fractional days -- the single
## number every sky-driven system reads (S16.2: closed-form orbits
## evaluate WorldRegistry.orbit_position against THIS). Honors the
## clock override exactly like current_day_index, so admin time
## travel moves the moon with the calendar. One clock: the Concord
## and the lattice never disagree about when it is.
func sky_epoch_days() -> float:
	return _now_unix() / 86400.0

## 0..3 window index within the day for a unix timestamp.
func window_index_for(unix: float) -> int:
	var secs_into_day: float = fposmod(unix, 86400.0)
	return int(secs_into_day / float(WINDOW_SECONDS))

## Seconds left in the window containing `unix`.
func seconds_left_in_window(unix: float) -> int:
	var secs_into_day: float = fposmod(unix, 86400.0)
	return WINDOW_SECONDS - int(secs_into_day) % WINDOW_SECONDS

## The Sign shown in (day, window). Pure hash of the pair: server and
## every client derive the same sky without any sync traffic.
func sign_for_window(day_index: int, window_index: int) -> SignProfile:
	if _sign_ids.is_empty():
		return null
	var key := "%d:%d" % [day_index, window_index]
	var idx: int = absi(hash(key)) % _sign_ids.size()
	return _signs.get(_sign_ids[idx])


## The day's true code phrase ("WAKE-SUNKEN-GROVE-WAKE"), server truth.
## Re-derivable for any past day (lore checks, vault verification).
func get_ancient_code(day_index: int) -> String:
	var glyphs: Array[String] = []
	for w in WINDOWS_PER_DAY:
		var sign := sign_for_window(day_index, w)
		if sign != null:
			glyphs.append(sign.glyph)
	return "-".join(glyphs)


# ------------------------------------------------------------------
# Daily Class Blessing (prd-psy.md section 8)
# ------------------------------------------------------------------

## The day's BLESSED CLASS: whichever class the assembled sky code
## "names" gets +20% damage/healing and an effective level +5 for the
## whole shard, for that one day. This is the retention beat: solve
## the sky -> log in tomorrow on the lucky class (or level an alt).
##
## TWO rules make it a game rather than a screensaver:
##
## 1. IT MUST BE EARNED. Day d's blessing is only ACTIVE if day d is
##    Ancient-unlocked (i.e. the tribe assembled day d-1's code). No
##    solve, no buff -- the code IS the lottery ticket, and agents can
##    run the reveal outside game processes (prd-psy.md section 6).
##
## 2. HYDRATION IS GUARANTEED, NOT PROBABILISTIC. The "sky wheel":
##    each round of n = class_count days shuffles the playable classes
##    ONCE (deterministic seed from the round epoch) and walks the
##    permutation slot by slot -- every class blesses exactly once per
##    round BY CONSTRUCTION. No repeat before a full rotation, on any
##    server, ever; re-hashing per day would allow collisions.
const BLESSED_DAMAGE_MULTIPLIER: float = 1.2
const BLESSED_LEVEL_BONUS: int = 5

## Which class the wheel names for `day_index` (always derivable --
## the almanac previews it once the day is unlocked). Deterministic
## permutation-per-round: round = day / n, slot = day mod n.
func get_blessed_class_id(day_index: int) -> String:
	var ids := _playable_class_ids()
	if ids.is_empty():
		return ""
	var n := ids.size()
	var d: int = maxi(day_index, 0)
	var round_epoch: int = d / n
	var slot: int = d % n
	return _wheel_order(round_epoch, ids)[slot]

## Deterministic shuffle for a round: Fisher-Yates over the sorted ids
## with the round epoch as the only seed. Same data + same round = same
## order on every server.
func _wheel_order(round_epoch: int, ids: Array[String]) -> Array[String]:
	var order := ids.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("skywheel:%d" % round_epoch)
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: String = order[i]
		order[i] = order[j]
		order[j] = tmp
	return order

## Is day_index's blessing LIVE? True only when that day is
## Ancient-unlocked -- the tribe assembled yesterday's code.
func is_blessing_active(day_index: int) -> bool:
	return _unlocked_days.has(day_index)

## Consumer truth (CombatMath/Skill): class blessed AND day earned.
## day_index < 0 = today. A class the wheel names on an unearned day
## gets nothing -- the sky does not pay for unsolved work.
func is_class_blessed(class_id: String, day_index: int = -1) -> bool:
	if class_id.is_empty():
		return false
	var day := day_index
	if day < 0:
		day = day_index_for(_now_unix())
	if not is_blessing_active(day):
		return false
	return get_blessed_class_id(day) == class_id

## Sorted playable (non-GM) class ids: the stable rotation order every
## server derives identically from the same data.
func _playable_class_ids() -> Array[String]:
	var out: Array[String] = []
	if DataService == null:
		return out
	for cls in DataService.get_all_classes():
		if cls == null or not ("id" in cls):
			continue
		# GM classes never bless (role 0 = GM).
		if "role" in cls and int(cls.role) == 0:
			continue
		# Species-scoped classes only: a player must be able to PICK
		# the class for its blessing day to mean anything. This filters
		# legacy shared archetypes ("warrior" from class_warrior.tres)
		# that no character creation path grants.
		var cid := str(cls.id)
		var playable := false
		for sp in ["human", "akkan", "synthetic"]:
			if cid.begins_with(sp + "_"):
				playable = true
				break
		if not playable:
			continue
		out.append(cid)
	out.sort()
	return out




# ------------------------------------------------------------------
# Current-window state
# ------------------------------------------------------------------

## Snapshot of the active window. glyph is only included once the
## community has revealed it -- before that it is rumor, not fact.
func get_current_window() -> Dictionary:
	var unix := _now_unix()
	var day := day_index_for(unix)
	var win := window_index_for(unix)
	var sign := sign_for_window(day, win)
	var out: Dictionary = {
		"day_index": day,
		"window_index": win,
		"sign_id": sign.id if sign != null else "",
		"sign_name": sign.display_name if sign != null else "",
		"seconds_remaining": seconds_left_in_window(unix),
		"observers": _observer_count(day, win),
		"reveal_threshold": REVEAL_OBSERVERS,
		"revealed": _revealed.has(_window_key(day, win)),
	}
	if bool(out["revealed"]) and sign != null:
		out["glyph"] = sign.glyph
	return out

## Public glyph knowledge for the current day, in window order.
## Unrevealed windows render as "?" -- the tribal gap.
func get_revealed_glyphs() -> Array[String]:
	var out: Array[String] = []
	var day := day_index_for(_now_unix())
	for w in WINDOWS_PER_DAY:
		var key := _window_key(day, w)
		if _revealed.has(key):
			var sign := sign_for_window(day, w)
			out.append(sign.glyph if sign != null else "?")
		else:
			out.append("?")
	return out

func _window_key(day_index: int, window_index: int) -> String:
	return "%d:%d" % [day_index, window_index]

func _observer_count(day_index: int, window_index: int) -> int:
	var key := _window_key(day_index, window_index)
	if not _insights.has(key):
		return 0
	return (_insights[key] as Dictionary).size()


# ------------------------------------------------------------------
# Insight recording (the tribal mechanic)
# ------------------------------------------------------------------

## Record THIS player's observation of the current window. Returns a
## result Dictionary: {ok, reason, revealed_now, observers}.
## One insight per player per window; repeats are idempotent, not spam.
func record_insight(player_id: String) -> Dictionary:
	_maybe_roll_day()
	var day := day_index_for(_now_unix())
	var win := window_index_for(_now_unix())
	var key := _window_key(day, win)
	var sign := sign_for_window(day, win)
	if sign == null:
		return {"ok": false, "reason": "no signs loaded"}
	if not _insights.has(key):
		_insights[key] = {}
	var window_observers: Dictionary = _insights[key]
	if window_observers.has(player_id):
		return {"ok": true, "reason": "already recorded", "revealed_now": false, "observers": window_observers.size()}
	window_observers[player_id] = true
	# Bound growth (oldest dropped) so a busy window cannot balloon state.
	while window_observers.size() > MAX_INSIGHTS_PER_WINDOW:
		var oldest: String = window_observers.keys()[0]
		window_observers.erase(oldest)
	insight_recorded.emit(player_id, sign.id, win)
	_save_insights()
	var revealed_now := false
	if not _revealed.has(key) and window_observers.size() >= REVEAL_OBSERVERS:
		_revealed[key] = true
		revealed_now = true
		_save_revealed()
		if NotificationService:
			NotificationService.notify(
				NotifKind.SIGN_INSIGHT_RECORDED,
				"The Concord marks it: %s is in the sky. Glyph '%s' is now shared knowledge." % [sign.display_name, sign.glyph],
				"SignService",
				"sign:reveal:%s" % key,
				{"sign_id": sign.id, "glyph": sign.glyph, "window_key": key}
			)
		_maybe_complete_day_code(day)
	return {"ok": true, "reason": "", "revealed_now": revealed_now, "observers": window_observers.size()}


## When every window of `day` is revealed, TOMORROW's Ancient unlocks
## server-wide. Fires once per day; idempotent on repeat.
func _maybe_complete_day_code(day: int) -> void:
	for w in WINDOWS_PER_DAY:
		if not _revealed.has(_window_key(day, w)):
			return
	var tomorrow := day + 1
	if _unlocked_days.has(tomorrow):
		return
	_unlocked_days[tomorrow] = true
	_save_unlocked()
	var code := get_ancient_code(day)
	if NotificationService:
		NotificationService.notify(
			NotifKind.ANCIENT_UNLOCKED,
			"The day's code is assembled: %s. Tomorrow's Ancient stirs -- the door will know its name." % code,
			"SignService",
			"sign:ancient:%d" % tomorrow,
			{"for_day": tomorrow, "code": code}
		)
		# Daily Class Blessing (prd-psy.md section 8): name the class the
		# wheel picked for tomorrow, so players can plan their login.
		var blessed := get_blessed_class_id(tomorrow)
		var blessed_name := blessed
		if DataService != null:
			var cls = DataService.get_character_class(blessed)
			if cls != null:
				blessed_name = str(cls.display_name)
		NotificationService.notify(
			NotifKind.CLASS_BLESSED,
			"The wheel turns: %s is blessed tomorrow (+%d%% might, +%d levels, +%d%% XP)." % [blessed_name, int((BLESSED_DAMAGE_MULTIPLIER - 1.0) * 100.0), BLESSED_LEVEL_BONUS, int((BLESSED_DAMAGE_MULTIPLIER - 1.0) * 100.0)],
			"SignService",
			"sign:blessed:%d" % tomorrow,
			{"for_day": tomorrow, "class_id": blessed}
		)
	ancient_unlocked.emit(tomorrow, code)

func is_ancient_unlocked(day_index: int) -> bool:
	return _unlocked_days.has(day_index)


# ------------------------------------------------------------------
# Day rollover
# ------------------------------------------------------------------

## Flip to the new day when the clock crosses the boundary: clear the
## day's rumor state, announce the window change. Safe to call often.
func _maybe_roll_day() -> void:
	var day := day_index_for(_now_unix())
	if day == _current_day:
		return
	var first_boot: bool = _current_day == -1
	_current_day = day
	_insights.clear()
	_revealed.clear()
	_save_revealed()
	_save_insights()
	# Announce the window that is live right now (skip announcement on
	# the very first boot -- the world has not asked yet).
	if not first_boot:
		var win := window_index_for(_now_unix())
		var sign := sign_for_window(day, win)
		if NotificationService and sign != null:
			NotificationService.notify(
				NotifKind.SIGN_WINDOW_CHANGED,
				"The sky turns. A new sign gathers over the shard.",
				"SignService",
				"sign:window:%d:%d" % [day, win],
				{"sign_id": sign.id, "window_index": win, "day_index": day}
			)
		# Daily Class Blessing dawn call (prd-psy.md section 8): the day
		# was earned yesterday (code solved -> unlock persisted), so name
		# the blessed class the moment it goes live. An unearned dawn
		# stays silent -- the almanac carries the preview instead.
		if NotificationService and is_blessing_active(day):
			var blessed := get_blessed_class_id(day)
			var blessed_name := blessed
			if DataService != null:
				var cls = DataService.get_character_class(blessed)
				if cls != null:
					blessed_name = str(cls.display_name)
			NotificationService.notify(
				NotifKind.CLASS_BLESSED,
				"Dawn: %s carries the sky's blessing today (+%d%% might, +%d levels, +%d%% XP)." % [blessed_name, int((BLESSED_DAMAGE_MULTIPLIER - 1.0) * 100.0), BLESSED_LEVEL_BONUS, int((BLESSED_DAMAGE_MULTIPLIER - 1.0) * 100.0)],
				"SignService",
				"sign:blessed:dawn:%d" % day,
				{"day_index": day, "class_id": blessed}
			)
		sign_window_changed.emit(sign.id if sign != null else "", win, day)


# ------------------------------------------------------------------
# Admin / test controls
# ------------------------------------------------------------------

## Force-reveal the current window's glyph (admin convening the Concord).
func force_reveal_current() -> Dictionary:
	var day := day_index_for(_now_unix())
	var win := window_index_for(_now_unix())
	return force_reveal_window(day, win)

## Force-reveal a SPECIFIC window (admin tooling). Idempotent.
func force_reveal_window(day_index: int, window_index: int) -> Dictionary:
	var key := _window_key(day_index, window_index)
	var sign := sign_for_window(day_index, window_index)
	if sign == null:
		return {"ok": false, "reason": "no signs loaded"}
	_revealed[key] = true
	_save_revealed()
	_maybe_complete_day_code(day_index)
	return {"ok": true, "glyph": sign.glyph, "window_key": key}

## Test hook: pin the clock to an arbitrary unix timestamp.
func set_clock_override(unix: float) -> void:
	_clock_override = unix
	_maybe_roll_day()


## Personal login toast (prd-psy.md section 8): a player whose class
## the wheel named TODAY -- and whose tribe actually earned it -- hears
## it on login. Hooked to GameManager.player_entered_world in
## ensure_initialized; silent for everyone else (no blessing, no
## noise). The class id comes from character_data.class_id so demo
## boots without a selected character simply never match.
func _on_player_entered_world(player_id: String, character_data: Resource) -> void:
	if NotificationService == null or character_data == null or not ("class_id" in character_data):
		return
	var cid := str(character_data.class_id)
	if cid.is_empty() or not is_class_blessed(cid):
		return
	var day := day_index_for(_now_unix())
	var display := cid
	if DataService != null:
		var cls = DataService.get_character_class(cid)
		if cls != null:
			display = str(cls.display_name)
	NotificationService.notify(
		NotifKind.CLASS_BLESSED,
		"The sky's wheel named YOUR class today: +%d%% might, +%d levels, +%d%% XP until dawn." % [int((BLESSED_DAMAGE_MULTIPLIER - 1.0) * 100.0), BLESSED_LEVEL_BONUS, int((BLESSED_DAMAGE_MULTIPLIER - 1.0) * 100.0)],
		"SignService",
		"sign:blessed_login:%s:%d" % [player_id, day],
		{"for_day": day, "class_id": cid, "player_id": player_id}
	)


# ------------------------------------------------------------------
# Data + persistence
# ------------------------------------------------------------------

func _load_signs() -> void:
	if DataService == null:
		GameLog.warn("SignService: DataService missing -- no signs")
		return
	if not DataService._loaded:
		DataService.load_all_data()
	_signs = DataService.get_signs()
	_sign_ids.clear()
	for sid in _signs.keys():
		_sign_ids.append(str(sid))
	_sign_ids.sort()

func _load_state() -> void:
	var store := DictStore.new()
	var keys: Array = store.all_keys()
	for k in keys:
		var ks := str(k)
		if not ks.begins_with(_KV):
			continue
		var val = store.get_kv(ks)
		if ks == _KV + "revealed" and val is Dictionary:
			_revealed = val.duplicate()
		elif ks == _KV + "insights" and val is Dictionary:
			_insights = val.duplicate()
		elif ks == _KV + "unlocked" and val is Dictionary:
			_unlocked_days = val.duplicate()

func _save_revealed() -> void:
	var store := DictStore.new()
	store.set_kv(_KV + "revealed", _revealed.duplicate())

func _save_insights() -> void:
	var store := DictStore.new()
	store.set_kv(_KV + "insights", _insights.duplicate())

func _save_unlocked() -> void:
	var store := DictStore.new()
	store.set_kv(_KV + "unlocked", _unlocked_days.duplicate())
