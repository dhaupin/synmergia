## QuestData - Quest definition
## Defines quest requirements, objectives, and rewards
extends Resource
class_name QuestData

## Quest Types
enum QuestType {
	MAIN,       # Main story quest
	SIDE,       # Side quest
	DAILY,      # Daily repeatable
	WEEKLY,     # Weekly repeatable
	EVENT,      # Event-specific
	GUILD,      # Guild quest
}

## Quest States
enum QuestState {
	LOCKED,     # Prerequisites not met
	AVAILABLE,  # Can be accepted
	IN_PROGRESS,# Active quest
	COMPLETE,   # Objectives done, turn in
	REWARDED,   # Turned in, done
	FAILED      # Failed/expired
}

## Objective Types
enum ObjectiveType {
	KILL,           # Kill X enemies
	COLLECT,        # Collect X items
	ESCORT,         # Escort NPC to location
	DEFEND,         # Defend something for time
	EXPLORE,        # Visit location
	TALK,           # Talk to NPC
	DELIVER,        # Deliver item to NPC
	USE_ITEM,       # Use item X times
	CRAFT,          # Craft X items
	REACH_LEVEL,    # Reach certain level
	ACHIEVE_STEP,   # Progress in achievement
}

## Difficulty
enum Difficulty {
	TRIVIAL,
	EASY,
	MEDIUM,
	HARD,
	EXPERT,
	MASTER,
}

@export var id: String = ""
@export var display_name: String = "Quest"
@export var description: String = ""
@export var quest_type: QuestType = QuestType.SIDE
@export var difficulty: Difficulty = Difficulty.MEDIUM

# Quest giver
@export var giver_npc_id: String = ""       # NPC who gives quest
@export var turn_in_npc_id: String = ""     # NPC to turn in (if different)

# Requirements
@export var min_level: int = 1
@export var max_level: int = 100
@export var required_quests: Array = []  # Quest IDs that must be complete
@export var required_faction: String = ""         # Faction required
@export var required_faction_rank: int = 0         # Minimum faction rank
@export var zone_restriction: String = ""         # Must be in zone to accept

# Objectives
class Objective extends Resource:
	@export var type: ObjectiveType = ObjectiveType.KILL
	@export var target_id: String = ""              # Enemy ID, item ID, NPC ID, etc.
	@export var target_name: String = ""            # Display name of target
	@export var count: int = 1                      # Number needed
	@export var optional: bool = false              # Can skip this objective
	@export var description: String = ""             # Custom description

@export var objectives: Array = []

# Rewards
class Reward extends Resource:
	@export var type: String = "item"               # item, gold, xp, faction, title
	@export var id: String = ""
	@export var quantity: int = 1
	@export var chance: float = 1.0                  # 0.0-1.0, for random rewards

@export var rewards: Array = []
@export var reward_choice_count: int = 0            # Choose X from rewards
@export var gold_reward: int = 0
@export var xp_reward: int = 0
@export var faction_reward: String = ""              # Faction to gain rep with
@export var faction_amount: int = 0                 # Reputation amount
@export var title_reward: String = ""               # Title to unlock

# Quest flow
@export var next_quest_id: String = ""              # Quest to unlock on complete
@export var previous_quest_id: String = ""         # Required quest before this

# Timing
@export var time_limit: float = 0.0                # 0 = no limit
@export var cooldown: float = 0.0                  # Cooldown before re-accept (for dailies)
@export var auto_complete: bool = false             # Complete without turn-in NPC

# Visuals
@export var icon_path: String = ""
@export var map_marker: String = ""                 # Waypoint marker type

# Repeatability
@export var is_repeatable: bool = false
@export var max_completions: int = 0               # 0 = infinite

func _init() -> void:
	if id == "":
		id = display_name.to_lower().replace(" ", "_")

## Get total objective count
func get_total_objective_count() -> int:
	return objectives.size()

## Get required (non-optional) objective count
func get_required_objective_count() -> int:
	var count: int = 0
	for obj in objectives:
		if obj is Objective and not obj.optional:
			count += 1
	return count

## Check if all required objectives are met (given current progress)
func check_completion(progress: Dictionary) -> bool:
	for obj in objectives:
		if obj is Objective:
			if obj.optional:
				continue
			var current: int = progress.get(obj.id, 0)
			if current < obj.count:
				return false
	return true

## Get progress percentage
func get_progress_percentage(progress: Dictionary) -> float:
	var required := get_required_objective_count()
	if required == 0:
		return 1.0
	
	var completed := 0
	for obj in objectives:
		if obj is Objective:
			if obj.optional:
				continue
			var current: int = progress.get(obj.id, 0)
			if current >= obj.count:
				completed += 1
	
	return float(completed) / float(required)

## Get reward summary for UI
func get_reward_summary() -> Array[Dictionary]:
	var summary: Array[Dictionary] = []
	
	if xp_reward > 0:
		summary.append({"type": "xp", "amount": xp_reward})
	
	if gold_reward > 0:
		summary.append({"type": "gold", "amount": gold_reward})
	
	if faction_reward != "" and faction_amount != 0:
		summary.append({"type": "faction", "faction": faction_reward, "amount": faction_amount})
	
	if title_reward != "":
		summary.append({"type": "title", "title": title_reward})
	
	for reward in rewards:
		if reward is Reward:
			var chance_pct: float = float(reward.chance) * 100.0
			summary.append({
				"type": reward.type,
				"id": reward.id,
				"quantity": reward.quantity,
				"chance": chance_pct
			})
	
	return summary
