## AchievementService - Player achievements and progression
class_name AchievementService
extends Node

signal achievement_unlocked(player_id: String, achievement_id: String)
signal achievement_progressed(player_id: String, achievement_id: String, progress: float)

func _ready() -> void:
	GameLog.info("AchievementService: Initialized")

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
