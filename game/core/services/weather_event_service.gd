## WeatherEventService — the sun-to-sword seam, DATA-DRIVEN.
##
## Upstream is verified: CosmicService owns ONE flywheel fed by real
## NOAA Kp; sparks bridge onto EventHub.cosmic_weather_spark; weather.gd
## resolves cosmic bands. This service stages the world's reaction —
## and the LAW of what fires is authored as .tres, not code:
##
##   data/weather_events/*.tres (WeatherEventData schema)
##   - trigger_kinds: SPARK_BAND (cosmic spark band name), BAND_STATE
##     (weather resolve state change), AURORA_BAND (spark aurora >= min)
##   - actions: stir_horde_config (a data/hordes/ composition, wave-
##     capped, boss off), open_aurora_window (observation window),
##     notify_message (typed toast).
##
## Adding a custom event (a Kp-driven giveaway, a fog ritual, "Kp 9
## calls the Ancient down") is a .tres file — zero code. Ship the
## schema conventions: storm_pack (storms stir storm_wolves packs),
## aurora_window (auroras open mystery windows).
##
## Consumption conventions per event: cooldown_sec cited from data
## (0 = fire every trigger; the fresh-tick sentinel makes 0 real),
## zone_ids empty = zone_starter_plains (the stirred-pack ground in v1).
##
## The embedded DEFAULTS here are the pre-data behavior (storm_pack /
## aurora_window windows) used only when the data catalog is empty --
## tests keep pinning through BOTH paths.
extends Node3D

const WeatherScript = preload("res://core/frame/srv/weather.gd")
const CosmicEntropyScript = preload("res://core/frame/srv/cosmic_entropy.gd")
const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind
const WeatherEventResolver = preload("res://core/schemas/weather_event_resolver.gd")
const WeatherEventData = preload("res://core/schemas/weather_event_data.gd")

signal storm_event_started(zone_id: String, horde_id: String)
signal aurora_window_opened(mystery_id: String)
signal aurora_window_closed(mystery_id: String)
signal aurora_window_time(mystery_id: String, sec_remaining: float, sec_total: float)

## HUD contract (SkyTotem): seconds remaining on the open aurora
## window + its total. Read from data (open_window_sec), not constant —
## the HUD never lies about a data-authored duration.
func aurora_window_remaining() -> Dictionary:
	if _aurora_open.is_empty():
		return {}
	var mid: String = _aurora_open.keys()[0]
	var now := Time.get_ticks_msec()
	var remaining_ms := maxf(0.0, float(int(_aurora_open[mid]) - now))
	return {"mystery_id": mid, "sec_remaining": remaining_ms / 1000.0,
		"sec_total": _aurora_seek_total(mid)}

var _aurora_totals: Dictionary = {}  # mystery_id -> sec_total
func _aurora_seek_total(mid: String) -> float:
	if not _aurora_totals.has(mid):
		return 0.0
	return float(_aurora_totals[mid])

## Data-driven law: config.id -> {cfg, last_fired_ms}.
var _events: Dictionary = {}
## Auroras currently open: mystery_id -> close_at_ms.
var _aurora_open: Dictionary = {}
## Fallback law when the data catalog is empty (pre-data behavior): the
## storm_pack/aurora_window pair. Kept as code so behavior never
## regresses for missing content.
var _loaded_from_data: bool = false
## Latched: horde/resolver initialization only warns once (spam).
var _warned_no_data: bool = false


func _ready() -> void:
	_load_event_configs()
	_hook_autoloads()


func _load_event_configs() -> void:
	# The catalog is the .tres content pipeline. DataService's loader
	# runs when loaded; a fresh script-mode boot may not have called
	# load_all_data yet — request it lazily.
	var ds = _root_node("DataService")
	if ds != null and ds.is_inside_tree() and ds.has_method("load_all_data") and not ds._loaded:
		ds.load_all_data()
	var configs: Array = []
	if ds != null and ds.has_method("get_all_weather_events"):
		configs = ds.get_all_weather_events()
	if configs.is_empty():
		# Resolver convention path also serves the same .tres; try it
		# before falling back to the code law (a data dir and a missing
		# DataService load are the same symptom as an EMPTY catalog).
		var paths := ["storm_pack", "aurora_window"]
		for cfg_id in paths:
			var cfg = WeatherEventResolver.load_config(str(cfg_id))
			if cfg != null:
				configs.append(cfg)
		_loaded_from_data = not configs.is_empty()
		if not _loaded_from_data and not _warned_no_data:
			_warned_no_data = true
			GameLog.info("WeatherEventService: no data/weather_events catalog — running the built-in law")
		_events["storm_pack"] = {"cfg": _builtin_storm_pack(), "last_fired_ms": 0}
		_events["aurora_window"] = {"cfg": _builtin_aurora_window(), "last_fired_ms": 0}
		return
	for cfg in configs:
		var id := str(cfg.get("id"))
		# Normalize: a WeatherEventData .tres flattens through to_config()
		# (the HordeData convention), built-in laws already are Dictionaries.
		var flat: Dictionary = cfg.to_config() if cfg.has_method("to_config") else (cfg as Dictionary)
		_events[id] = {"cfg": flat, "last_fired_ms": 0}
	GameLog.info("WeatherEventService: loaded %d weather event configs (the law is data)" % _events.size())


## Built-in fallback laws (schema-shaped; the same Dictionary shape
## to_config produces — so every downstream path is identical).
func _builtin_storm_pack() -> Dictionary:
	return {
		"id": "storm_pack",
		"trigger_kinds": [0, 1],
		"band_names": ["storm", "tempest", "rain"],
		"aurora_min": 0.5,
		"cooldown_sec": 240.0,
		"zone_ids": [],
		"stir_horde_config": "storm_wolves",
		"stir_waves": 2,
		"open_window_sec": 0.0,
		"notify_message": "The storm stirs the wilds — something is coming.",
	}


func _builtin_aurora_window() -> Dictionary:
	return {
		"id": "aurora_window",
		"trigger_kinds": [2],
		"band_names": [],
		"aurora_min": 0.5,
		"cooldown_sec": 600.0,
		"zone_ids": [],
		"stir_horde_config": "",
		"stir_waves": 2,
		"open_window_sec": 1800.0,
		"notify_message": "An aurora unfolds — the sky is writing. Something may be answered.",
	}


func _root_node(node_name: String) -> Node:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(node_name)


func _ready_or_null(node_name: String) -> Node:
	var n := _root_node(node_name)
	if n == null:
		return null
	return n


func _hook_autoloads() -> void:
	var cs = _ready_or_null("CosmicService")
	if cs != null and cs.has_signal("spark") and not cs.spark.is_connected(_on_cosmic_spark):
		cs.spark.connect(_on_cosmic_spark)
		GameLog.info("WeatherEventService: watching the cosmic wheel (the sky stirs the world)")


## A cosmic spark (real Kp crossing the flywheel threshold). Fires
## every event config whose SPARK_BAND / AURORA_BAND trigger matches.
## The AURORA_BAND leg reads the SHIELDED aurora (moon CME shadow,
## aurora_at_epoch): when the pale stone stands between the sun and
## Synmergia, the sky's aurora the world experiences is trimmed --
## and an aurora-window event keyed to raw upstream aurora would fire
## on a sky nobody sees. Same epoch the moon orbits on.
func _on_cosmic_spark(payload: Dictionary) -> void:
	var kp: float = float(payload.get("kp", 0.0))
	var band: Dictionary = CosmicEntropyScript.kp_to_band(kp)
	var band_name: String = str(band.get("name", "calm"))
	var band_aurora: float = float(band.get("aurora", 0.0))
	var epoch: float = -1.0
	var ssvc = _root_node("SignService")
	if ssvc != null and ssvc.has_method("sky_epoch_days"):
		epoch = ssvc.sky_epoch_days()
	if epoch >= 0.0 and payload.has("kp"):
		# The shield reads through the instance law on CosmicEntropy
		# (moon_shield_factor/aurora_at_epoch); payload-side so tests can
		# pin it deterministically with an injected epoch.
		var ent = CosmicEntropyScript.new()
		band_aurora = ent.aurora_at_epoch(kp, epoch)
	for eid in _events:
		# cfg may be a Dictionary (built-in law) or a WeatherEventData
		# Resource (.tres law) — both answer .get() identically.
		var ecfg = _events[eid]["cfg"]
		var kinds: Array = ecfg.get("trigger_kinds", [])
		if kinds.has(int(WeatherEventData.TriggerKind.SPARK_BAND)) \
				and (ecfg.get("band_names", []) as Array).has(band_name):
			_try_fire(eid)
		elif kinds.has(int(WeatherEventData.TriggerKind.AURORA_BAND)) \
				and band_aurora >= float(ecfg.get("aurora_min", 0.5)):
			_try_fire(eid)


## A weather RESOLVE state change (via the AmbienceDriver push — the
## trad-fallback bucket that never waits for the sun). Fires every
## config whose BAND_STATE trigger names the new state.
func on_weather_band_changed(state: Dictionary) -> void:
	var st: String = str(state.get("name", ""))
	for eid in _events:
		var ecfg = _events[eid]["cfg"]
		var kinds: Array = ecfg.get("trigger_kinds", [])
		if kinds.has(int(WeatherEventData.TriggerKind.BAND_STATE)) \
				and (ecfg.get("band_names", []) as Array).has(st):
			_try_fire(eid)


## Fire one event config, gated by ITS OWN cooldown. First fire is
## always allowed (last_fired_ms==0 is the cold-engine sentinel:
## get_ticks_msec starts near 0 in fresh harnesses and would otherwise
## gate the world silent for a full cooldown).
func _try_fire(eid: String) -> void:
	var entry: Dictionary = _events.get(eid, {})
	if entry.is_empty():
		return
	var ecfg = entry["cfg"]  # Dictionary (built-in) or WeatherEventData (.tres)
	var now := Time.get_ticks_msec()
	var cooldown_ms := int(float(ecfg.get("cooldown_sec", 240.0)) * 1000.0)
	if cooldown_ms > 0 and int(entry["last_fired_ms"]) != 0 \
			and now - int(entry["last_fired_ms"]) < cooldown_ms:
		return
	_events[eid]["last_fired_ms"] = now
	_actions(ecfg)


## Event actions in a fixed order: stir -> window -> notify.
## zone_override ("") keeps the config's zone convention (its own
## zone_ids or the starter-plains default).
func _actions(ecfg: Dictionary, zone_override: String = "") -> void:
	var zone_id: String = zone_override if zone_override != "" else _pick_zone(ecfg)
	var horde_id := ""
	if str(ecfg.get("stir_horde_config", "")) != "":
		horde_id = _stir_pack(ecfg, zone_id)
	var window_mystery := ""
	if float(ecfg.get("open_window_sec", 0.0)) > 0.0:
		window_mystery = _open_window(ecfg)
	var msg := str(ecfg.get("notify_message", ""))
	if msg != "":
		_notif(msg, "weather:%s"%(str(ecfg.get("id","event"))), _notify_kind(ecfg))
	if horde_id != "":
		storm_event_started.emit(zone_id, horde_id)


func _notify_kind(_ecfg: Dictionary) -> int:
	return NotifKind.WEATHER_STORM_STIRRED


func _pick_zone(ecfg: Dictionary) -> String:
	var zones: Array = ecfg.get("zone_ids", [])
	if zones.is_empty():
		return "zone_starter_plains"
	return str(zones[0])


func _stir_pack(ecfg: Dictionary, zone_id: String) -> String:
	var horde = _root_node("HordeEventService")
	if horde == null or not horde.has_method("start_horde_from_config"):
		return ""
	# Wave cap + boss off: a stirred pack, not the config's raid.
	var horde_id: String = horde.start_horde_from_config(str(ecfg["stir_horde_config"]), zone_id, {
		"waves": int(ecfg.get("stir_waves", 2)),
		"boss_template_id": "",
		"bosses_alert": false,
	})
	if horde_id != "":
		GameLog.info("WeatherEventService: %s stirred a pack (%s)" % [str(ecfg.get("id", "?")), horde_id])
	return horde_id


func _open_window(ecfg: Dictionary) -> String:
	var acts = _root_node("ActsService")
	if acts == null or not acts.has_method("get_mysteries"):
		return ""
	if not _aurora_open.is_empty():
		return ""  # one window at a time: the sky is not chatty
	var now := Time.get_ticks_msec()
	var mysteries: Dictionary = acts.get_mysteries()
	# Prefer GATE-UNLOCKED mysteries; else the first unsolved one as
	# staging (the gate law itself still refuses attempts).
	var picked := ""
	for mid in mysteries.keys():
		if acts.is_mystery_unlocked(str(mid)) and not acts.is_mystery_solved(str(mid), ""):
			picked = str(mid)
			break
	if picked == "":
		for mid in mysteries.keys():
			if not acts.is_mystery_solved(str(mid), ""):
				picked = str(mid)
				break
	if picked != "":
		var sec_total := float(ecfg.get("open_window_sec", 1800.0))
		_aurora_totals[picked] = sec_total
		_aurora_open[picked] = now + int(sec_total * 1000.0)
		aurora_window_time.emit(picked, sec_total, sec_total)
		# Sign tie-in: the CURRENT sky window is aurora-lit — its glyph
		# reveals at half the tribal threshold while the sky glows (the
		# SignService.set_aurora_support law). Cleared on expiry.
		var ssvc = _root_node("SignService")
		if ssvc != null and ssvc.has_method("set_aurora_support"):
			ssvc.set_aurora_support(ssvc.day_index_for(ssvc._now_unix()), ssvc.window_index_for(ssvc._now_unix()), true)
		GameLog.info("WeatherEventService: aurora window opens on %s" % picked)
		aurora_window_opened.emit(picked)
	return picked


func _process(_delta: float) -> void:
	_hook_autoloads_once()
	_close_expired_aurora_windows()


var _hooked: bool = false
func _hook_autoloads_once() -> void:
	if _hooked:
		return
	var cs = _root_node("CosmicService")
	if cs != null and cs.has_signal("spark"):
		_hooked = true
		if not cs.spark.is_connected(_on_cosmic_spark):
			cs.spark.connect(_on_cosmic_spark)


func _close_expired_aurora_windows() -> void:
	if _aurora_open.is_empty():
		return
	var now := Time.get_ticks_msec()
	for mid in _aurora_open.keys():
		if now >= int(_aurora_open[mid]):
			_aurora_open.erase(mid)
			# Un-light the Sign window's aurora support on expiry.
			var ssvc = _root_node("SignService")
			if ssvc != null and ssvc.has_method("set_aurora_support"):
				ssvc.set_aurora_support(ssvc.day_index_for(ssvc._now_unix()), ssvc.window_index_for(ssvc._now_unix()), false)
			GameLog.info("WeatherEventService: aurora window closes on %s" % str(mid))
			aurora_window_closed.emit(mid)
			_aurora_totals.erase(mid)


## May a mystery be attempted right now (aurora-window verdict)?
func is_aurora_window_open(mystery_id: String) -> bool:
	return _aurora_open.has(mystery_id)


func _notif(msg: String, dedupe_key: String, kind: int = NotifKind.WEATHER_STORM_STIRRED) -> void:
	var nsvc = _root_node("NotificationService")
	if nsvc == null or not nsvc.has_method("notify"):
		return
	nsvc.notify(kind, msg, "WeatherEventService", dedupe_key, {}, "")


## Loaded event ids (debug/HUD surface: which laws are armed).
func loaded_event_ids() -> Array:
	return _events.keys()


## Admin surface: every armed event config, as flat Dictionaries (the
## same shape to_config produces) so the command layer can display ids,
## trigger kinds, and actions without touching the private law table.
func list_configs() -> Array:
	var out: Array = []
	for eid in _events:
		var ecfg = _events[eid]["cfg"]
		var flat: Dictionary = cfg_to_flat(ecfg)
		out.append(flat)
	return out


## Shared flatten: a WeatherEventData Resource (.tres law) goes
## through to_config(); a built-in law is already a Dictionary. Dictionaries
## answer has_method by THROWING in GDScript -- type-check instead.
static func cfg_to_flat(ecfg) -> Dictionary:
	if ecfg is Dictionary:
		return ecfg
	return ecfg.to_config()

## Admin surface: force-fire an event config NOW, bypassing its
## cooldown (dev/testing path for data-authored events). zone_override
## ("") keeps the config's own zone convention. The actions run the
## exact same _actions pipeline a real trigger uses — force-fire must
## never be a second law. Returns the config id on success, "" when
## the id is unknown.
func force_fire(event_id: String, zone_override: String = "") -> String:
	if not _events.has(event_id):
		return ""
	_events[event_id]["last_fired_ms"] = Time.get_ticks_msec()
	_actions(_events[event_id]["cfg"], zone_override)
	return event_id
