## AchievementService - Player achievements and progression
class_name AchievementService
extends Node

signal achievement_unlocked(player_id: String, achievement_id: String)
signal achievement_progressed(player_id: String, achievement_id: String, progress: float)

func _ready() -> void:
	GameLog.info("AchievementService: Initialized")

func unlock_achievement(player_id: String, achievement_id: String) -> void:
	achievement_unlocked.emit(player_id, achievement_id)

func update_progress(player_id: String, achievement_id: String, progress: float) -> void:
	achievement_progressed.emit(player_id, achievement_id, progress)
