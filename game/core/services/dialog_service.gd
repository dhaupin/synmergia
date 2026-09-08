## DialogService - NPC dialogue loading and state management
## Loads DialogueData resources from data/dialogues/*.tres and drives DialogUI.
extends Node

## Singleton instance (use singleton() to access)
static var _instance: Node = null
static func singleton() -> Node:
	if _instance == null:
		_instance = load("res://core/services/dialog_service.gd").new()
		_instance._ready()
	return _instance

## BBCode XSS escape (AGENTS.md "Security: BBCode XSS").
## DialogUI renders user-supplied text in RichLabels; unescaped [ and ]
## let a player inject formatting/color/URL tags. Full-width brackets
## are not recognized as BBCode and pass through as literal text.
static func _esc(text: String) -> String:
	return text.replace("[", "［").replace("]", "］")

const QoSService = preload("res://core/autoload/qos_service.gd")
const DialogueData = preload("res://core/schemas/dialogue_data.gd")
# ShopUI and UIStyles are not autoloads (class_name only).
# MenuManager is NOT preloaded here: it pulls in dialog_ui.gd at
# parse time, which preloads dialog_service.gd (this file), forming
# a 3-node cyclic preload that 4.7.2 rejects. MenuManager exposes a
# static open_menu() facade, so the call site below resolves it
# lazily via the class_name registered when menu_manager.gd loads.
const ShopUI = preload("res://ui/components/shop_ui.gd")
const UIStyles = preload("res://ui/components/ui_styles.gd")

var _dialogues: Dictionary = {}
var _current_dialogue: DialogueData = null
var _current_node: int = 0

signal dialogue_started(npc_id: String, dialogue_id: String)
signal dialogue_ended(npc_id: String, dialogue_id: String)
signal node_changed(node_index: int, node_data: Dictionary)
signal action_executed(action_type: int, action_data: Dictionary)

func _ready() -> void:
	_load_dialogues()
	GameLog.info("DialogService: Loaded %d dialogues" % _dialogues.size())

func _load_dialogues() -> void:
	var dir := DirAccess.open("res://data/dialogues/")
	if not dir:
		GameLog.warn("DialogService: No data/dialogues/ directory")
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var path := "res://data/dialogues/" + file_name
			var dialogue: DialogueData = load(path)
			if dialogue and dialogue.id != "":
				_dialogues[dialogue.id] = dialogue
		file_name = dir.get_next()
	dir.list_dir_end()

func get_dialogue(dialogue_id: String) -> DialogueData:
	return _dialogues.get(dialogue_id)

func start_dialogue(npc_id: String, dialogue_id: String) -> bool:
	# QoS: Rate limit dialogue starts
	var player_id := get_local_player_id()
	if QoSService and player_id and not QoSService.rate_limit(player_id, "dialogue"):
		return false

	var dialogue: DialogueData = get_dialogue(dialogue_id)
	if dialogue == null:
		GameLog.warn("DialogService: Dialogue not found: %s" % _esc(dialogue_id))
		return false
	_current_dialogue = dialogue
	_current_node = 0
	dialogue_started.emit(_esc(npc_id), _esc(dialogue_id))
	node_changed.emit(_current_node, _node_to_dict(dialogue.get_node(_current_node)))
	return true

func advance() -> Dictionary:
	if _current_dialogue == null or _current_dialogue.nodes.is_empty():
		end_dialogue()
		return {}
	var node := _current_dialogue.get_node(_current_node)
	if not _has_choices(node):
		_current_node += 1
	if _current_node < 0 or _current_node >= _current_dialogue.nodes.size():
		end_dialogue()
		return {}
	var node_dict := _node_to_dict(_current_dialogue.get_node(_current_node))
	node_changed.emit(_current_node, node_dict)
	return node_dict

func select_choice(choice_index: int) -> Dictionary:
	if _current_dialogue == null:
		return {}
	var choices: Array[Dictionary] = _current_dialogue.get_choices(_current_node)
	if choice_index < 0 or choice_index >= choices.size():
		return {}
	var next: int = choices[choice_index].get("next_node", -1)
	if next < 0:
		end_dialogue()
		return {}
	_current_node = next
	if _current_node < 0 or _current_node >= _current_dialogue.nodes.size():
		end_dialogue()
		return {}
	var node_dict := _node_to_dict(_current_dialogue.get_node(_current_node))
	node_changed.emit(_current_node, node_dict)
	return node_dict

func get_current_node() -> Dictionary:
	if _current_dialogue == null:
		return {}
	if _current_node < 0 or _current_node >= _current_dialogue.nodes.size():
		return {}
	return _node_to_dict(_current_dialogue.get_node(_current_node))

func _has_choices(node: Dictionary) -> bool:
	if not node.has("choices"):
		return false
	var choices: Array = node["choices"]
	return not choices.is_empty()

func _node_to_dict(node: Dictionary) -> Dictionary:
	var choices: Array[Dictionary] = []
	if node.has("choices"):
		for choice: Dictionary in node["choices"]:
			choices.append({
				"text": choice.get("text", ""),
				"next": choice.get("next_node", -1)
			})
	return {
		"speaker": node.get("speaker", ""),
		"text": node.get("text", ""),
		"choices": choices
	}

func end_dialogue() -> void:
	var npc_id: String = _current_dialogue.npc_id if _current_dialogue else ""
	var dialogue_id: String = _current_dialogue.id if _current_dialogue else ""
	_current_dialogue = null
	_current_node = 0
	dialogue_ended.emit(npc_id, dialogue_id)

func has_dialogue(dialogue_id: String) -> bool:
	return _dialogues.has(dialogue_id)

func execute_action(action_type: int, action_data: Dictionary, player_id: String = "") -> bool:
	var DialogActionType = DialogueData.DialogActionType
	match action_type:
		DialogActionType.NONE:
			return true
		DialogActionType.GIVE_QUEST:
			var quest_id: String = action_data.get("quest_id", "")
			if QuestService and quest_id:
				return QuestService.accept_quest(player_id, quest_id)
		DialogActionType.COMPLETE_QUEST:
			var quest_id: String = action_data.get("quest_id", "")
			if QuestService and quest_id:
				return QuestService.turn_in_quest(player_id, quest_id)
		DialogActionType.ABANDON_QUEST:
			var quest_id: String = action_data.get("quest_id", "")
			if QuestService and quest_id:
				QuestService.abandon_quest(player_id, quest_id)
				return true
		DialogActionType.START_FOLLOW:
			var target_id: String = action_data.get("target_id", "")
			if FollowService and target_id:
				return FollowService.request_follow(player_id, target_id)
		DialogActionType.STOP_FOLLOW:
			if FollowService:
				FollowService.cancel_follow(player_id)
				return true
		DialogActionType.OPEN_SHOP:
			var shop_id: String = action_data.get("shop_id", "")
			if ShopUI:
				ShopUI.open_shop(shop_id)
				return true
		DialogActionType.OPEN_VAULT:
			# The vault panel is registered as "bank" in MenuManager
			# (BankUI). There is no VaultUI class -- the old reference
			# was a dangling identifier that also made this branch
			# return a Node from a String-returning function.
			# MenuManager is NOT preloaded here (it would form a
			# cyclic preload: dialog_service -> menu_manager ->
			# dialog_ui -> dialog_service). Load it lazily at the
			# call site instead.
			var MenuManager = load("res://ui/components/menu_manager.gd")
			if MenuManager:
				MenuManager.open_menu("bank")
				return true
		DialogActionType.SET_WAYPOINT:
			var wp_name: String = action_data.get("name", "Marker")
			var color: int = action_data.get("color", 0)
			if WaypointService:
				# WaypointService.create_waypoint would be called with player pos
				GameLog.debug("DialogAction: SET_WAYPOINT '%s'" % wp_name)
				return true
		DialogActionType.GIVE_ITEM:
			var item_id: String = action_data.get("item_id", "")
			var quantity: int = action_data.get("quantity", 1)
			if InventoryService and item_id:
				InventoryService.add_item(player_id, item_id, quantity)
				return true
		DialogActionType.GIVE_CURRENCY:
			var amount: int = action_data.get("amount", 0)
			var currency: String = action_data.get("currency", "gold")
			GameLog.debug("DialogAction: GIVE_CURRENCY %d %s" % [amount, currency])
			return true
		DialogActionType.UNLOCK_TITLE:
			# Resource.get(key, default) was removed in 4.7.2; the
			# guard already exists, so drop the default arg.
			var title_id: String = action_data.get("title_id")
			if TitleService and title_id:
				TitleService.unlock_title(player_id, title_id)
				return true
		DialogActionType.TEACH_SKILL:
			var skill_id: String = action_data.get("skill_id")
			if SkillAcademyService and skill_id:
				SkillAcademyService.unlock_skill(player_id, skill_id)
				return true
		_:
			GameLog.warn("DialogAction: Unknown action type %d" % action_type)
			return false
	return false

func get_local_player_id() -> String:
	if PlayerManager:
		var player = PlayerManager.get_local_player()
		if player and "entity_id" in player:
			return player.entity_id
	return ""
