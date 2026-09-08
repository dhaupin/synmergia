## AchievementData - Achievement definition
extends Resource
class_name AchievementData

## Achievement Types
enum AchievementType {
		GLOBAL,        # One-time unlock (first blood, etc.)
		PROGRESS,      # Track progress toward a goal (defeat 100 enemies)
		COLLECTIBLE,   # Collect X items
}

## Achievement Categories
enum Category {
		COMBAT,       # Combat-related achievements
		SOCIAL,       # Party, guild, friends
		ECONOMY,      # Trading, crafting, collecting
		EXPLORATION,  # Discovering zones, locations
		ACHIEVEMENT,  # Meta-achievements (other achievements)
}

## Difficulty/Rarity
enum Rarity {
		COMMON,
		UNCOMMON,
		RARE,
		EPIC,
		LEGENDARY,
}

@export var id: String = ""
@export var display_name: String = "Achievement"
@export var description: String = ""
@export var achievement_type: AchievementType = AchievementType.GLOBAL
@export var category: Category = Category.COMBAT
@export var rarity: Rarity = Rarity.COMMON

## Progress target (for PROGRESS and COLLECTIBLE types)
@export var target: int = 1
@export var target_type: String = ""

## Prerequisites
@export var required_achievements: Array = []
@export var min_level: int = 1

## Rewards
@export var gold_reward: int = 0
@export var xp_reward: int = 0
@export var title_reward: String = ""
@export var item_rewards: Array = []

## Display
@export var icon_path: String = ""
@export var hidden: bool = false
@export var secret_description: String = ""

## Ordering
@export var sort_order: int = 0

func _init() -> void:
		if id == "":
				id = display_name.to_lower().replace(" ", "_")

func get_progress_percentage(current_progress: int) -> float:
		if achievement_type == AchievementType.GLOBAL:
				return 1.0 if current_progress >= 1 else 0.0
		if target <= 0:
				return 1.0
		return clampf(float(current_progress) / float(target), 0.0, 1.0)

func is_complete(current_progress: int) -> bool:
		if achievement_type == AchievementType.GLOBAL:
				return current_progress >= 1
		return current_progress >= target

func get_reward_summary() -> Array[Dictionary]:
		var summary: Array[Dictionary] = []
		if xp_reward > 0:
				summary.append({"type": "xp", "amount": xp_reward})
		if gold_reward > 0:
				summary.append({"type": "gold", "amount": gold_reward})
		if title_reward != "":
				summary.append({"type": "title", "title": title_reward})
		for reward in item_rewards:
				if reward is Dictionary:
						summary.append({
								"type": "item",
								"id": reward.get("id", ""),
								"quantity": reward.get("quantity", 1),
								"chance": float(reward.get("chance", 1.0)) * 100.0
						})
		return summary
