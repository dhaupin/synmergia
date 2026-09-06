## AchievementService - Player achievements and progression
extends Node
class_name AchievementService

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
	# Initialize default achievement definitions
	_achievement_defs = {
		"first_blood": {"id": "first_blood", "name": "First Blood", "description": "Defeat your first enemy", "type": AchievementType.GLOBAL, "target": 1, "category": "combat"},
		"slayer_10": {"id": "slayer_10", "name": "Slayer", "description": "Defeat 10 enemies", "type": AchievementType.PROGRESS, "target": 10, "category": "combat"},
		"slayer_100": {"id": "slayer_100", "name": "Master Slayer", "description": "Defeat 100 enemies", "type": AchievementType.PROGRESS, "target": 100, "category": "combat"},
		"social_butterfly": {"id": "social_butterfly", "name": "Social Butterfly", "description": "Join a party", "type": AchievementType.GLOBAL, "category": "social"},
		"guild_member": {"id": "guild_member", "name": "Guild Member", "description": "Join a guild", "type": AchievementType.GLOBAL, "category": "social"},
		"trader": {"id": "trader", "name": "Trader", "description": "Complete your first trade", "type": AchievementType.GLOBAL, "category": "economy"},
		"collector_50": {"id": "collector_50", "name": "Collector", "description": "Collect 50 items", "type": AchievementType.PROGRESS, "target": 50, "category": "economy"},
		"explorer": {"id": "explorer", "name": "Explorer", "description": "Visit 10 zones", "type": AchievementType.PROGRESS, "target": 10, "category": "exploration"},
	}

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

## Resolve an active AchievementService instance from the scene tree. Returns
## null if the service hasn't been instantiated yet (it's not autoloaded by
## default; this helper exists so callers that hold a class_name reference
## can still reach a live instance if one was added to the tree by the host).
static func get_instance() -> Node:
	var ml: MainLoop = Engine.get_main_loop()
	if ml == null:
		return null
	if not ml is SceneTree:
		return null
	var root: Window = (ml as SceneTree).root
	if root == null:
		return null
	# Try autoload path first, then a common scene-tree name
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
		var def: Dictionary = _achievement_defs[ach_id]
		if def.get("type") == AchievementType.GLOBAL:
			continue
		var ach_target: String = def.get("target", "")
		if ach_target != target:
			continue
		_increment_progress(player_id, ach_id, amount)

func _increment_progress(player_id: String, achievement_id: String, amount: int) -> void:
	if not _achievement_defs.has(achievement_id):
		return
	var def: Dictionary = _achievement_defs[achievement_id]
	var target: float = float(def.get("target", 1))
	if not _player_achievements.has(player_id):
		load_player_achievements(player_id)
	var player_data: Dictionary = _player_achievements[player_id]
	var current: float = 0.0
	if player_data.has(achievement_id):
		current = float(player_data[achievement_id].get("progress", 0))
		if player_data[achievement_id].get("unlocked", false):
			return
	current = mini(current + amount, target)
	var progress: float = current / target if target > 0 else 1.0
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
