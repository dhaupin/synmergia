## ThermalService - the sky roads (S12.5).
##
## Loads data/thermals/*.tres into a spatial book, samples updrafts
## for gliding bodies, owns the ritual awakening of ancient launchers
## (server effort flips dormant launchers awake -- the mystery beat),
## and tracks glide stats per player for the gliding achievements
## (distance / altitude / time).
##
## Autoload: NO class_name (AGENTS rule).
extends Node

const ThermalUpdraft = preload("res://core/schemas/thermal_updraft.gd")
const DictStore = preload("res://adapters/persistence/dict_store.gd")

## Ceiling of lift any updraft can give (m/s), the primitive's
## THERMAL_LIFT_MAX mirrored here so the schema samples against it.
const MAX_LIFT: float = 3.0

## Launch-boost bookkeeping: player_id -> {until: unix, speed: float}
var _launches: Dictionary = {}
## player_id -> glide stats {"distance": float, "max_altitude": float,
## "time": float} -- achievement book (AchievementService reads via
## track()).
var _glide_stats: Dictionary = {}
## launcher id -> awakened (session book; ritual persistence is the
## server-effort story, recorded per shard through DictStore).
var _awake: Dictionary = {}
var _updrafts: Array = []
var _store = null  # DictStore (runtime-assigned; lazy-friendly)


func _ready() -> void:
	_load_updrafts()
	var store: DictStore = DictStore.new()
	var saved = store.get_kv("thermals:awake", [])
	if saved is Array:
		for id in saved:
			_awake[str(id)] = true
	# Restore the awake flag onto the loaded resources too.
	for u in _updrafts:
		if _awake.has(str(u.id)):
			u.awakened = true
	GameLog.info("ThermalService: Ready (%d updrafts, %d ancient launchers awake)" % [_updrafts.size(), _awake.size()])


func _load_updrafts() -> void:
	_updrafts.clear()
	var dir := DirAccess.open("res://data/thermals")
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			var updraft: Resource = load("res://data/thermals/" + fname)
			if updraft != null and updraft is ThermalUpdraft:
				_updrafts.append(updraft)
		fname = dir.get_next()


## All updrafts (probe/UI).
func get_updrafts() -> Array:
	return _updrafts


## Total vertical contribution at a position (m/s, positive = lift).
func sample(pos: Vector3) -> float:
	var total: float = 0.0
	for u in _updrafts:
		total += u.sample_vertical_speed(pos, MAX_LIFT)
	return total


## Is there a launch burst under this position right now?
func sample_launch(pos: Vector3) -> float:
	for u in _updrafts:
		if u.kind == ThermalUpdraft.Kind.LAUNCHER and u.is_active():
			var v: float = u.sample_vertical_speed(pos, MAX_LIFT)
			if v > 0.0:
				return v
	return 0.0


## The updraft a position belongs to ("" when none) -- launcher feeds
## and UI want the name.
func updraft_at(pos: Vector3) -> String:
	for u in _updrafts:
		if u.sample_vertical_speed(pos, MAX_LIFT) > 0.0:
			return str(u.id)
	return ""


## ---- Ritual awakening (the server-effort beat) -------------------------

## Ancient launchers sleep until the shard wakes them. Contribution
## counting lives with the caller (quests/community goals); this is
## the moment of waking.
func awaken_launcher(launcher_id: String) -> bool:
	for u in _updrafts:
		if str(u.id) == launcher_id and u.kind == ThermalUpdraft.Kind.LAUNCHER:
			if _awake.has(launcher_id):
				return false
			_awake[launcher_id] = true
			u.awakened = true  # the sampler reads the resource truth
			var ids: Array = _awake.keys()
			var store: DictStore = DictStore.new()
			store.set_kv("thermals:awake", ids)
			GameLog.info("ThermalService: ancient launcher '%s' AWAKENS" % str(u.display_name))
			return true
	return false


func is_awake(launcher_id: String) -> bool:
	return _awake.has(launcher_id)


## ---- Glide stats (the achievements feed) --------------------------------

## Gliding bodies report their tick: distance covered and current
## altitude above the local surface. Time accrues per gliding second.
func record_glide_tick(player_id: String, distance: float, altitude: float) -> void:
	var stats: Dictionary = _glide_stats.get(player_id, {"distance": 0.0, "max_altitude": 0.0, "time": 0.0})
	stats["distance"] = float(stats.get("distance", 0.0)) + distance
	stats["max_altitude"] = maxf(float(stats.get("max_altitude", 0.0)), altitude)
	stats["time"] = float(stats.get("time", 0.0)) + (1.0 / 60.0)
	_glide_stats[player_id] = stats


func glide_stats(player_id: String) -> Dictionary:
	return _glide_stats.get(player_id, {"distance": 0.0, "max_altitude": 0.0, "time": 0.0})


## Achievement categories fed by the listeners when a bout/landing
## closes: "glide_distance" (meters), "glide_altitude" (meters),
## "glide_time" (seconds). Amounts are the stat value; the service
## caps at each def's target.
func push_glide_achievements(player_id: String) -> void:
	var ach = get_node_or_null("/root/AchievementService")
	if ach == null:
		return
	var stats: Dictionary = glide_stats(player_id)
	if float(stats.get("distance", 0.0)) > 0.0:
		ach.track(player_id, "glide_distance", int(float(stats["distance"])))
	if float(stats.get("max_altitude", 0.0)) > 0.0:
		ach.track(player_id, "glide_altitude", int(float(stats["max_altitude"])))
	if float(stats.get("time", 0.0)) >= 1.0:
		ach.track(player_id, "glide_time", int(float(stats["time"])))
