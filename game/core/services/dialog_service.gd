## DialogService - NPC dialogue loading and state management
## Loads DialogueData resources from data/dialogues/*.tres and drives DialogUI.
extends Node

## Singleton instance (use get_instance() to access)
static var _instance: Node = null
static func get_instance() -> Node:
	if _instance == null:
		_instance = load("res://core/services/dialog_service.gd").new()
		_instance._ready()
	return _instance

const DialogueData = preload("res://core/schemas/dialogue_data.gd")

var _dialogues: Dictionary = {}
var _current_dialogue: DialogueData = null
var _current_node: int = 0

signal dialogue_started(npc_id: String, dialogue_id: String)
signal dialogue_ended(npc_id: String, dialogue_id: String)
signal node_changed(node_index: int, node_data: Dictionary)

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
	var dialogue: DialogueData = get_dialogue(dialogue_id)
	if dialogue == null:
		GameLog.warn("DialogService: Dialogue not found: %s" % dialogue_id)
		return false
	_current_dialogue = dialogue
	_current_node = 0
	dialogue_started.emit(npc_id, dialogue_id)
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
