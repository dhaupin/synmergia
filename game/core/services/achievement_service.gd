## AchievementService - Player achievements and progression
extends Node
class_name AchievementService

const AchievementData = preload("res://core/schemas/achievement_data.gd")

## Achievement types
enum AchievementType {
    GLOBAL,        # One-time unlock (first blood, etc.)
    PROGRESS,      # Track progress toward a goal (defeat 100 enemies)
    COLLECTIBLE,   # Collect X items
}

## Player achievement state
var _player_achievements: Dictionary = {}

## Achievement definitions
var _achievement_defs: Dictionary = {}

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

## Static shim so callers that reference AchievementService as a class
## (because of class_name) can still hit an instance implementation.
static func unlock(player_id: String, achievement_id: String) -> void:
        var inst: Node = get_instance()
        if inst == null:
                return
        inst.call("unlock_achievement", player_id, achievement_id)

static func unlock_achievement(player_id: String, achievement_id: String) -> void:
        var inst: Node = get_instance()
        if inst == null:
                return
        inst.call("_do_unlock", player_id, achievement_id)

## Resolve an active AchievementService instance from the scene tree.
static func get_instance() -> Node:
        var ml: MainLoop = Engine.get_main_loop()
        if ml == null:
                return null
        if not ml is SceneTree:
                return null
        var root: Window = (ml as SceneTree).root
        if root == null:
                return null
        var n: Node = root.get_node_or_null("AchievementService")
        if n != null:
                return n
        return root.get_node_or_null("root/AchievementService")

func _do_unlock(player_id: String, achievement_id: String) -> void:
        achievement_unlocked.emit(player_id, achievement_id)

func update_progress(player_id: String, achievement_id: String, progress: float) -> void:
        achievement_progressed.emit(player_id, achievement_id, progress)

## ============================================================================
## ACHIEVEMENT DEFINITIONS
## ============================================================================

func get_achievement_definitions() -> Dictionary:
        return _achievement_defs

func get_achievement(id: String) -> AchievementData:
        return DataService.get_achievement(id) if DataService else null

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
        var result: Array = []
        var player_data: Dictionary = get_player_achievements(player_id)
        for achievement_id in player_data:
                if player_data[achievement_id].get("unlocked", false):
                        result.append(achievement_id)
        return result

func get_achievement_progress(player_id: String, achievement_id: String) -> Dictionary:
        var player_data: Dictionary = get_player_achievements(player_id)
        if player_data.has(achievement_id):
                return player_data[achievement_id]
        return {"progress": 0.0, "unlocked": false}

## ============================================================================
## ACHIEVEMENT TRACKING
## ============================================================================

func track_event(player_id: String, event_type: String, target: String, amount: int = 1) -> void:
        for ach_id in _achievement_defs:
                var def = _achievement_defs[ach_id]
                var ach_type: int
                var ach_target: int
                if def is AchievementData:
                        ach_type = def.achievement_type
                        ach_target = def.target
                else:
                        ach_type = def.get("type", AchievementType.GLOBAL)
                        ach_target = def.get("target", 1)
                if ach_type == AchievementType.GLOBAL:
                        continue
                var target_str: String = str(ach_target)
                if target_str != target:
                        continue
                _increment_progress(player_id, ach_id, amount)

func _increment_progress(player_id: String, achievement_id: String, amount: int) -> void:
        if not _achievement_defs.has(achievement_id):
                return
        var def = _achievement_defs[achievement_id]
        var target: int
        if def is AchievementData:
                target = def.target
        else:
                target = def.get("target", 1)
        if not _player_achievements.has(player_id):
                load_player_achievements(player_id)
        var player_data: Dictionary = _player_achievements[player_id]
        var current: float = 0.0
        if player_data.has(achievement_id):
                current = float(player_data[achievement_id].get("progress", 0))
                if player_data[achievement_id].get("unlocked", false):
                        return
        current = mini(current + amount, target)
        var progress: float = current / float(target) if target > 0 else 1.0
        player_data[achievement_id] = {
                "progress": current,
                "unlocked": current >= target,
                "unlocked_at": Time.get_unix_time_from_system() if current >= target else 0
        }
        _player_achievements[player_id] = player_data
        if current >= target:
                _do_unlock(player_id, achievement_id)
        else:
                update_progress(player_id, achievement_id, progress)
