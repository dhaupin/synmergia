## AchievementService - Player achievements and progression
## Pure service: defs come from data/achievements via DataService, progress is
## persisted through the DictStore adapter. Game signals are bridged in by
## achievement_listeners.gd (autoload); rewards pay out to the local player
## and titles route through TitleService.
extends Node

const AchievementData = preload("res://core/schemas/achievement_data.gd")
const DictStore = preload("res://adapters/persistence/dict_store.gd")
## Instance-level so test harnesses can isolate their store namespace.
var _kv_prefix: String = "achievement:player:"
## .tres fallback scan dir when DataService is unavailable (--script tests).
const _TRES_DIR := "res://data/achievements/"

## Achievement definitions loaded from data/achievements via DataService
var _achievement_defs: Array = []

## Player achievement state: player_id -> {achievement_id -> {progress, unlocked, unlocked_at}}
var _player_achievements: Dictionary = {}

signal achievement_unlocked(player_id: String, achievement_id: String)
signal achievement_progressed(player_id: String, achievement_id: String, progress: float)

func _ready() -> void:
	_log("info", "AchievementService: Initialized")
	_load_achievement_definitions()
	_load_player_achievements()

## Autoload-safe logging: bare GameLog references abort at runtime in
## --script test mode (autoloads are not pre-loaded). This resolves via
## the same _service() route the other methods use.
func _log(level: String, msg: String) -> void:
	var gl := _service("GameLog")
	if gl != null and gl.has_method(level):
		gl.call(level, msg)

func _load_achievement_definitions() -> void:
	var ds := _service("DataService")
	if ds != null and ds.has_method("get_all_achievements"):
		_achievement_defs = ds.call("get_all_achievements")
		_log("info", "AchievementService: Loaded %d achievements from DataService" % _achievement_defs.size())
		return
	# --script / fallback path: scan the .tres directory directly so the
	# catalog works outside the full game boot.
	_achievement_defs = _load_defs_from_tres_dir()
	if _achievement_defs.is_empty():
		_log("warn", "AchievementService: no achievement defs found (DataService absent, .tres scan empty)")
	else:
		_log("info", "AchievementService: Loaded %d achievements from .tres fallback" % _achievement_defs.size())

const ResourceScan = preload("res://core/frame/srv/resource_scan.gd")

func _load_defs_from_tres_dir() -> Array:
	var out: Array = []
	# Export-safe scan: the pack stores .tres as .res + .tres.remap.
	for p in ResourceScan.list_resources(_TRES_DIR):
		var res: Resource = load(p)
		if res != null and res is AchievementData:
			out.append(res)
	return out

## ============================================================================
## PUBLIC API
## ============================================================================

## Unlock a specific achievement for a player (direct unlock: bypasses
## chain gating, still guards double unlocks and unknown ids)
static func unlock(player_id: String, achievement_id: String) -> void:
	var inst := singleton()
	if inst == null:
		return
	inst._do_unlock(player_id, achievement_id)

## Unlock the first GLOBAL achievement whose target_type matches
## (e.g. "party", "guild", "trade", "session"). Used by the listeners bridge.
static func unlock_event(player_id: String, target_type: String) -> void:
	var inst := singleton()
	if inst == null:
		return
	inst._do_unlock_event(player_id, target_type)

## Track an event (e.g., enemy killed, item collected) for a player
## event_category matches the achievement's target_type
## ("enemy", "item", "zone", "quest", "chat", ...)
static func track(player_id: String, event_category: String, amount: int = 1) -> void:
	var inst := singleton()
	if inst == null:
		return
	inst._track_event(player_id, event_category, amount)

## Convenience methods for quest/follow/waypoint integration
static func on_quest_completed(player_id: String, _quest_id: String = "") -> void:
	track(player_id, "quest", 1)

static func on_quest_started(_player_id: String, _quest_id: String = "") -> void:
	pass

static func on_follow_started(player_id: String, _target_id: String = "") -> void:
	track(player_id, "follow_started", 1)

static func on_follow_ended(player_id: String, _reason: String = "manual") -> void:
	track(player_id, "follow_ended", 1)

static func on_waypoint_created(player_id: String) -> void:
	track(player_id, "waypoint_created", 1)

static func on_enemy_killed(player_id: String, _enemy_type: String = "") -> void:
	track(player_id, "enemy", 1)

static func singleton() -> Node:
	var ml: MainLoop = Engine.get_main_loop()
	if ml == null or not ml is SceneTree:
		return null
	var root: Window = (ml as SceneTree).root
	if root == null:
		return null
	return root.get_node_or_null("AchievementService")

## ============================================================================
## ACHIEVEMENT DATA
## ============================================================================

func get_achievement(id: String) -> AchievementData:
	var local := _find_def(id)
	if local != null:
		return local
	var ds := _service("DataService")
	if ds != null and ds.has_method("get_achievement"):
		return ds.call("get_achievement", id)
	return null

func get_all_achievements() -> Array:
	return _achievement_defs

func _find_def(achievement_id: String) -> AchievementData:
	for ach in _achievement_defs:
		if ach is AchievementData and ach.id == achievement_id:
			return ach
	return null

## ============================================================================
## PLAYER ACHIEVEMENT STATE
## ============================================================================

func load_player_achievements(player_id: String) -> void:
	if not _player_achievements.has(player_id):
		_player_achievements[player_id] = {}
	_log("debug", "AchievementService: Loaded achievements for %s" % player_id)

func get_player_achievements(player_id: String) -> Dictionary:
	if not _player_achievements.has(player_id):
		load_player_achievements(player_id)
	return _player_achievements.get(player_id, {})

func get_unlocked_achievements(player_id: String) -> Array:
	var unlocked: Array = []
	var player_data: Dictionary = get_player_achievements(player_id)
	for ach_id in player_data:
		if player_data[ach_id].get("unlocked", false):
			unlocked.append(ach_id)
	return unlocked

func has_unlocked(player_id: String, achievement_id: String) -> bool:
	var player_data: Dictionary = get_player_achievements(player_id)
	return player_data.has(achievement_id) and player_data[achievement_id].get("unlocked", false)

func get_achievement_progress(player_id: String, achievement_id: String) -> Dictionary:
	var player_data: Dictionary = get_player_achievements(player_id)
	if player_data.has(achievement_id):
		return player_data[achievement_id]
	return {"progress": 0.0, "unlocked": false}

## ============================================================================
## ACHIEVEMENT TRACKING (INTERNAL)
## ============================================================================

func _track_event(player_id: String, event_category: String, amount: int) -> void:
	for ach in _achievement_defs:
		var achievement: AchievementData = ach
		# Check if this achievement tracks this event category
		if achievement.target_type != event_category:
			continue
		# Chain gating: required_achievements must all be unlocked first
		if not _requirements_met(player_id, achievement):
			continue
		# GLOBAL defs with target_type set (e.g. first_blood: target 1,
		# "enemy") unlock through tracking too; _do_unlock guards repeats.
		_increment_progress(player_id, achievement.id, amount)

func _do_unlock_event(player_id: String, target_type: String) -> void:
	for ach in _achievement_defs:
		var achievement: AchievementData = ach
		if achievement.achievement_type != AchievementData.AchievementType.GLOBAL:
			continue
		if achievement.target_type != target_type:
			continue
		if has_unlocked(player_id, achievement.id):
			continue
		if not _requirements_met(player_id, achievement):
			continue
		_do_unlock(player_id, achievement.id)
		return

func _requirements_met(player_id: String, def: AchievementData) -> bool:
	if def.required_achievements.is_empty():
		return true
	for req_id in def.required_achievements:
		if not has_unlocked(player_id, String(req_id)):
			return false
	return true

func _increment_progress(player_id: String, achievement_id: String, amount: int) -> void:
	var def := _find_def(achievement_id)
	if def == null:
		return
	if not _player_achievements.has(player_id):
		load_player_achievements(player_id)

	var player_data: Dictionary = _player_achievements[player_id]

	# Check if already unlocked
	if player_data.has(achievement_id) and player_data[achievement_id].get("unlocked", false):
		return

	var current: float = 0.0
	var last_bucket := 0
	if player_data.has(achievement_id):
		current = float(player_data[achievement_id].get("progress", 0.0))
		last_bucket = int(player_data[achievement_id].get("notified_pct", 0))

	# Cap at target
	current = minf(current + float(amount), float(def.target))
	var now_unlocked := current >= float(def.target)

	# NOTE: when the target is met, do NOT mark unlocked here -- _do_unlock
	# owns the unlock (state + rewards + signal) and its double-unlock guard
	# would see a pre-marked entry and skip the reward payout.
	player_data[achievement_id] = {
		"progress": current,
		"unlocked": false,
		"unlocked_at": 0,
		"notified_pct": last_bucket,
	}

	_persist_player_achievements(player_id)

	if now_unlocked:
		_do_unlock(player_id, achievement_id)
		return

	# Emit progress toasts only at 25/50/75% crossings so farming doesn't spam.
	var pct := current / float(def.target)
	var bucket := int(pct * 4.0)
	if bucket > last_bucket and bucket < 4:
		player_data[achievement_id]["notified_pct"] = bucket
		_persist_player_achievements(player_id)
		achievement_progressed.emit(player_id, achievement_id, pct)

func _do_unlock(player_id: String, achievement_id: String) -> void:
	var def := get_achievement(achievement_id)
	if def == null:
		_log("warn", "AchievementService: Unknown achievement id '%s' (no .tres def)" % achievement_id)
		return
	if not _player_achievements.has(player_id):
		load_player_achievements(player_id)
	var player_data: Dictionary = _player_achievements[player_id]

	# Double-unlock guard
	if player_data.has(achievement_id) and player_data[achievement_id].get("unlocked", false):
		return

	player_data[achievement_id] = {
		"progress": float(def.target),
		"unlocked": true,
		"unlocked_at": Time.get_unix_time_from_system(),
	}

	_persist_player_achievements(player_id)
	_grant_rewards(player_id, def)
	_announce(player_id, def)
	achievement_unlocked.emit(player_id, achievement_id)

## Unlock moment: system chat line with the display name (the HUD toast for
## ACHIEVEMENT_UNLOCKED already fires off the achievement_unlocked signal via
## hud_services). Chat is the durable record; toasts are transient.
func _announce(player_id: String, def: AchievementData) -> void:
	var chat := _service("ChatService")
	if chat == null or not chat.has_method("send_system_message"):
		return
	chat.send_system_message(
		player_id,
		"Achievement Unlocked: \"%s\"! Check your Hall of Valor [Y]." % def.display_name
	)

func _grant_rewards(player_id: String, def: AchievementData) -> void:
	var pm := _service("PlayerManager")
	if pm == null:
		return
	var local = pm.get("local_player")
	if local == null or not is_instance_valid(local):
		return
	var eid = local.get("entity_id")
	if eid == null or String(eid) != player_id:
		# Non-local player: the authoritative server applies these rewards.
		return
	if def.gold_reward > 0 and pm.has_method("add_gold"):
		pm.add_gold(def.gold_reward)
	if def.xp_reward > 0 and pm.has_method("add_experience"):
		pm.add_experience(def.xp_reward)
	if def.title_reward != "":
		var ts := _service("TitleService")
		if ts != null and ts.has_method("unlock"):
			ts.unlock(player_id, def.title_reward)

## Autoload lookup that works both in the running tree and from
## --script/test contexts (absolute /root/ paths are rejected outside
## the active scene tree; the main loop route always works).
func _service(autoload_name: String) -> Node:
	var ml: MainLoop = Engine.get_main_loop()
	if ml == null or not ml is SceneTree:
		return null
	var root_node: Window = (ml as SceneTree).root
	if root_node == null:
		return null
	return root_node.get_node_or_null(autoload_name)

func _load_player_achievements() -> void:
	var store := DictStore.new()
	_player_achievements.clear()
	for key in store.all_keys():
		if not key.begins_with(_kv_prefix):
			continue
		var player_id: String = key.replace(_kv_prefix, "")
		var data: Dictionary = store.get_value(key) as Dictionary
		if data == null:
			data = {}
		if not data.is_empty():
			_player_achievements[player_id] = data

func _persist_player_achievements(player_id: String) -> void:
	var store := DictStore.new()
	var achievements: Dictionary = _player_achievements.get(player_id, {})
	if achievements.is_empty():
		store.erase(_kv_prefix + player_id)
	else:
		store.set_value(_kv_prefix + player_id, achievements)
