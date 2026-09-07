## AchievementService - Player achievements and progression
extends Node

const AchievementData = preload("res://core/schemas/achievement_data.gd")

## Achievement definitions loaded from data/achievements via DataService
var _achievement_defs: Dictionary = {}

## Player achievement state: player_id -> {achievement_id -> {progress, unlocked, unlocked_at}}
var _player_achievements: Dictionary = {}

signal achievement_unlocked(player_id: String, achievement_id: String)
signal achievement_progressed(player_id: String, achievement_id: String, progress: float)

func _ready() -> void:
        GameLog.info("AchievementService: Initialized")
        _load_achievement_definitions()

func _load_achievement_definitions() -> void:
        if DataService and DataService.has_method("get_all_achievements"):
                _achievement_defs = DataService.get_all_achievements()
                GameLog.info("AchievementService: Loaded %d achievements from DataService" % _achievement_defs.size())
        else:
                GameLog.warn("AchievementService: DataService not available, achievements will not load")

## ============================================================================
## PUBLIC API
## ============================================================================

## Unlock a specific achievement for a player
static func unlock(player_id: String, achievement_id: String) -> void:
        var inst := singleton()
        if inst == null:
                return
        inst._do_unlock(player_id, achievement_id)

## Track an event (e.g., enemy killed, item collected) for a player
## event_category: what type of event ("enemy", "item", "zone", etc.)
## amount: how many to add (default 1)
static func track(player_id: String, event_category: String, amount: int = 1) -> void:
        var inst := singleton()
        if inst == null:
                return
        inst._track_event(player_id, event_category, amount)

## Convenience methods for quest/follow/waypoint integration
static func on_quest_completed(player_id: String, quest_id: String) -> void:
        track(player_id, "quest_completed", 1)

static func on_quest_started(player_id: String, quest_id: String) -> void:
        track(player_id, "quest_started", 1)

static func on_follow_started(player_id: String, target_id: String) -> void:
        track(player_id, "follow_started", 1)

static func on_follow_ended(player_id: String, reason: String = "manual") -> void:
        track(player_id, "follow_ended", 1)

static func on_waypoint_created(player_id: String) -> void:
        track(player_id, "waypoint_created", 1)

static func on_enemy_killed(player_id: String, enemy_type: String = "") -> void:
        track(player_id, "enemy_killed", 1)

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
        return DataService.get_achievement(id) if DataService else null

func get_all_achievements() -> Dictionary:
        return _achievement_defs

## ============================================================================
## PLAYER ACHIEVEMENT STATE
## ============================================================================

func load_player_achievements(player_id: String) -> void:
        if not _player_achievements.has(player_id):
                _player_achievements[player_id] = {}
        GameLog.debug("AchievementService: Loaded achievements for %s" % player_id)

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

func get_achievement_progress(player_id: String, achievement_id: String) -> Dictionary:
        var player_data: Dictionary = get_player_achievements(player_id)
        if player_data.has(achievement_id):
                return player_data[achievement_id]
        return {"progress": 0.0, "unlocked": false}

## ============================================================================
## ACHIEVEMENT TRACKING (INTERNAL)
## ============================================================================

func _track_event(player_id: String, event_category: String, amount: int) -> void:
        for ach_id in _achievement_defs:
                var ach: AchievementData = _achievement_defs[ach_id]
                # Skip GLOBAL achievements (they're unlocked directly, not tracked)
                if ach.achievement_type == AchievementData.AchievementType.GLOBAL:
                        continue
                # Check if this achievement tracks this event category
                if ach.target_type != event_category:
                        continue
                _increment_progress(player_id, ach_id, amount)

func _increment_progress(player_id: String, achievement_id: String, amount: int) -> void:
        if not _achievement_defs.has(achievement_id):
                return
        var ach: AchievementData = _achievement_defs[achievement_id]
        var target: int = ach.target
        
        if not _player_achievements.has(player_id):
                load_player_achievements(player_id)
        
        var player_data: Dictionary = _player_achievements[player_id]
        
        # Check if already unlocked
        if player_data.has(achievement_id) and player_data[achievement_id].get("unlocked", false):
                return
        
        var current: float = 0.0
        if player_data.has(achievement_id):
                current = float(player_data[achievement_id].get("progress", 0))
        
        # Cap at target
        current = mini(current + amount, target)
        
        player_data[achievement_id] = {
                "progress": current,
                "unlocked": current >= target,
                "unlocked_at": Time.get_unix_time_from_system() if current >= target else 0
        }
        
        if current >= target:
                _do_unlock(player_id, achievement_id)
        else:
                achievement_progressed.emit(player_id, achievement_id, current / float(target))

func _do_unlock(player_id: String, achievement_id: String) -> void:
        achievement_unlocked.emit(player_id, achievement_id)
