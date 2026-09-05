## QuestService - Player quest management
## Handles quest acceptance, progress tracking, and completion
extends Node

const QuestData = preload("res://core/schemas/quest_data.gd")
static func _esc(text: String) -> String:
	return text.replace('[', '［').replace(']', '］')

## Singleton
static var instance: QuestService

## Player quests: player_id -> {quest_id -> quest_state}
var _player_quests: Dictionary = {}

## Available quests per player: player_id -> [quest_ids]
var _available_quests: Dictionary = {}

## Signals
signal quest_accepted(player_id: String, quest_id: String)
signal quest_updated(player_id: String, quest_id: String, objective_id: String, progress: int)
signal quest_completed(player_id: String, quest_id: String)
signal quest_rewarded(player_id: String, quest_id: String, rewards: Dictionary)
signal quest_failed(player_id: String, quest_id: String, reason: String)

# Frame-level notification dispatch (typed-Kind pipeline).
const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind

func _ready() -> void:
	instance = self
	GameLog.info("QuestService: Ready")

## ============================================================================
## QUEST LOADING
## ============================================================================

func load_player_quests(player_id: String) -> void:
	# TODO: Load from database
	if not _player_quests.has(player_id):
		_player_quests[player_id] = {}
	if not _available_quests.has(player_id):
		_available_quests[player_id] = []
	GameLog.debug("QuestService: Loaded quests for %s" % player_id)

func get_player_quests(player_id: String) -> Dictionary:
	return _player_quests.get(player_id, {})

func get_active_quests(player_id: String) -> Array:
	var quests := []
	var player_data: Dictionary = _player_quests.get(player_id, {})
	for quest_id in player_data:
		var state: int = player_data[quest_id].get("state", QuestData.QuestState.LOCKED)
		if state == QuestData.QuestState.IN_PROGRESS:
			quests.append(quest_id)
	return quests

## ============================================================================
## QUEST AVAILABILITY
## ============================================================================

func get_available_quests(player_id: String) -> Array:
	# Return quests that can be accepted
	var available := []
	var player_data: Dictionary = _player_quests.get(player_id, {})

	# TODO: Load from quest database and check prerequisites
	# For now, return empty or test quests
	return available

func check_quest_availability(player_id: String, quest_id: String) -> Dictionary:
	var result := {
		"available": false,
		"reason": ""
	}

	var quest := _load_quest_data(quest_id)
	if not quest:
		result.reason = "Quest not found"
		return result

	var player_data: Dictionary = _player_quests.get(player_id, {})

	# Check if already has quest
	if player_data.has(quest_id):
		var state: int = player_data[quest_id].get("state", QuestData.QuestState.LOCKED)
		if state == QuestData.QuestState.IN_PROGRESS:
			result.reason = "Already in progress"
			return result
		elif state == QuestData.QuestState.REWARDED:
			result.reason = "Already completed"
			return result

	# Check level requirements
	# TODO: Get player level
	# var player_level := _get_player_level(player_id)
	# if player_level < quest.min_level:
	#	result.reason = "Level too low (need %d)" % quest.min_level
	#	return result

	result.available = true
	return result

func _load_quest_data(quest_id: String) -> QuestData:
	if DataService:
		return DataService.get_quest(quest_id)
	return null

## ============================================================================
## QUEST ACCEPTANCE
## ============================================================================

func accept_quest(player_id: String, quest_id: String) -> bool:
	var availability := check_quest_availability(player_id, quest_id)
	if not availability.available:
		GameLog.warn("QuestService: Cannot accept quest - %s" % availability.reason)
		return false

	var quest := _load_quest_data(quest_id)
	if not quest:
		return false

	# Initialize quest state
	if not _player_quests.has(player_id):
		_player_quests[player_id] = {}

	var objectives := []
	for obj in quest.objectives:
		if not obj is Dictionary:
			continue
		objectives.append({
			"id": obj.get("id", str(objectives.size())),
			"type": int(obj.get("type", QuestData.ObjectiveType.KILL)),
			"target": str(obj.get("target", obj.get("target_id", ""))),
			"required": int(obj.get("count", 1)),
			"current": 0,
			"completed": false
		})

	_player_quests[player_id][quest_id] = {
		"state": QuestData.QuestState.IN_PROGRESS,
		"accepted_at": Time.get_unix_time_from_system(),
		"objectives": objectives,
		"data": quest
	}

	quest_accepted.emit(player_id, quest_id)
	GameLog.info("QuestService: %s accepted quest %s" % [player_id, quest_id])
	return true

func abandon_quest(player_id: String, quest_id: String) -> bool:
	var player_data: Dictionary = _player_quests.get(player_id, {})
	if not player_data.has(quest_id):
		return false

	var state: int = player_data[quest_id].get("state", QuestData.QuestState.LOCKED)
	if state != QuestData.QuestState.IN_PROGRESS:
		return false

	# Remove quest
	player_data.erase(quest_id)
	GameLog.info("QuestService: %s abandoned quest %s" % [player_id, quest_id])
	return true

## ============================================================================
## QUEST PROGRESS
## ============================================================================

func update_quest_progress(player_id: String, objective_type: int, target: String, amount: int = 1) -> void:
	var player_data: Dictionary = _player_quests.get(player_id, {})
	var updated := []

	for quest_id in player_data:
		var quest_state: Dictionary = player_data[quest_id]
		if quest_state.get("state") != QuestData.QuestState.IN_PROGRESS:
			continue

		var objectives: Array = quest_state.get("objectives", [])
		var changed := false

		for obj in objectives:
			if obj.get("completed", false):
				continue
			if obj.get("type") != objective_type:
				continue
			if obj.get("target") != target:
				continue

			# Update progress
			obj["current"] = mini(obj["current"] + amount, obj["required"])
			obj["completed"] = obj["current"] >= obj["required"]
			changed = true

			quest_updated.emit(player_id, quest_id, obj["id"], obj["current"])
			updated.append({"quest": quest_id, "objective": obj["id"]})

		# Check if all objectives complete
		if changed and _are_all_objectives_complete(objectives):
			quest_state["state"] = QuestData.QuestState.COMPLETE
			quest_completed.emit(player_id, quest_id)

			# Frame-level dispatch. QUEST_COMPLETED → NotifKind.QUEST
			# (autoload maps the kind to NotificationType.QUEST for the
			# legacy render path). Dedupe on (player, quest_id) so a
			# follow-up objective tick that re-evaluates to complete
			# does not double-toast.
			if is_instance_valid(NotificationService):
				NotificationService.notify(
					NotifKind.QUEST_COMPLETED,
					"Quest Complete: %s - Return to quest giver!" % quest_state.get("data", {}).get("display_name", "Unknown"),
					"QuestService",
					"quest_complete:%s:%s" % [player_id, quest_id],
					{"quest_id": quest_id, "player_id": player_id},
					player_id
				)

	if updated.is_empty():
		return

	GameLog.debug("QuestService: Updated %d quest(s) for %s" % [updated.size(), player_id])

func _are_all_objectives_complete(objectives: Array) -> bool:
	for obj in objectives:
		if not obj.get("completed", false):
			return false
	return true

## ============================================================================
## QUEST COMPLETION
## ============================================================================

func turn_in_quest(player_id: String, quest_id: String) -> bool:
	var player_data: Dictionary = _player_quests.get(player_id, {})
	if not player_data.has(quest_id):
		return false

	var quest_state: Dictionary = player_data[quest_id]
	if quest_state.get("state") != QuestData.QuestState.COMPLETE:
		return false

	var quest: QuestData = quest_state.get("data")
	if not quest:
		return false

	# Apply rewards
	var rewards := _apply_rewards(player_id, quest)

	# Mark as rewarded
	quest_state["state"] = QuestData.QuestState.REWARDED
	quest_state["rewarded_at"] = Time.get_unix_time_from_system()

	quest_rewarded.emit(player_id, quest_id, rewards)
	GameLog.info("QuestService: %s turned in quest %s" % [player_id, quest_id])
	return true

func _apply_rewards(player_id: String, quest: QuestData) -> Dictionary:
	# quest.rewards is Array[Reward] (one entry per reward line). We
	# fold the array into a summary dict the rest of the game can read
	# without depending on the Reward schema. Inventory/XP/gold grants
	# are TODO and live in their respective services.
	var summary := {
		"experience": 0,
		"gold": 0,
		"items": [],
		"reputation": {},
		"titles": []
	}
	for reward in quest.rewards:
		if not reward is Dictionary:
			continue
		var rtype: String = str(reward.get("type", ""))
		match rtype:
			"experience":
				summary["experience"] += int(reward.get("quantity", 0))
			"gold":
				summary["gold"] += int(reward.get("quantity", 0))
			"item":
				summary["items"].append({
					"id": reward.get("id", ""),
					"quantity": int(reward.get("quantity", 1)),
				})
			"reputation":
				summary["reputation"][reward.get("id", "")] = int(reward.get("quantity", 0))
			"title":
				summary["titles"].append(reward.get("id", ""))
	return summary

## ============================================================================
## QUEST TRACKING
## ============================================================================

func get_quest_progress(player_id: String, quest_id: String) -> Dictionary:
	var player_data: Dictionary = _player_quests.get(player_id, {})
	if not player_data.has(quest_id):
		return {}

	var quest_state: Dictionary = player_data[quest_id]
	return {
		"state": quest_state.get("state"),
		"objectives": quest_state.get("objectives", []),
		"data": quest_state.get("data")
	}

func get_quest_objectives_text(player_id: String, quest_id: String) -> Array:
	var progress := get_quest_progress(player_id, quest_id)
	if progress.is_empty():
		return []

	var objectives: Array = progress.get("objectives", [])
	var result := []

	for obj in objectives:
		var obj_type: int = obj.get("type", QuestData.ObjectiveType.KILL)
		var target: String = obj.get("target", "")
		var current: int = obj.get("current", 0)
		var required: int = obj.get("required", 1)
		var completed: bool = obj.get("completed", false)

		var text := ""
		match obj_type:
			QuestData.ObjectiveType.KILL:
				text = "Kill %s: %d/%d" % [_esc(target), current, required]
			QuestData.ObjectiveType.COLLECT:
				text = "Collect %s: %d/%d" % [_esc(target), current, required]
			QuestData.ObjectiveType.TALK:
				text = "Talk to %s" % _esc(target)
			QuestData.ObjectiveType.EXPLORE:
				text = "Explore %s" % _esc(target)
			_:
				text = "%s: %d/%d" % [_esc(target), current, required]

		if completed:
			text = "[color=%s]%s[/color]" % [UIStyles.COLORS.success.to_html(), text]
		else:
			text = "[color=%s]%s[/color]" % [UIStyles.COLORS.text_primary.to_html(), text]

		result.append(text)

	return result
