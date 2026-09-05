## DialogService - NPC dialogue loading and state management
## Loads DialogueData resources from data/dialogues/*.tres and drives DialogUI.
extends Node
class_name DialogService

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
	node_changed.emit(_current_node, _node_to_dict(_current_dialogue.nodes[_current_node]))
	return true

func advance() -> Dictionary:
	if _current_dialogue == null or _current_dialogue.nodes.is_empty():
		end_dialogue()
		return {}
	if _current_dialogue.nodes[_current_node].choices.is_empty():
		_current_node += 1
	if _current_node < 0 or _current_node >= _current_dialogue.nodes.size():
		end_dialogue()
		return {}
	var node_dict := _node_to_dict(_current_dialogue.nodes[_current_node])
	node_changed.emit(_current_node, node_dict)
	return node_dict

func select_choice(choice_index: int) -> Dictionary:
	if _current_dialogue == null:
		return {}
	var node: DialogueData.DialogueNode = _current_dialogue.nodes[_current_node]
	if choice_index < 0 or choice_index >= node.choices.size():
		return {}
	var next: int = node.choices[choice_index].next_node
	if next < 0:
		end_dialogue()
		return {}
	_current_node = next
	if _current_node < 0 or _current_node >= _current_dialogue.nodes.size():
		end_dialogue()
		return {}
	var node_dict := _node_to_dict(_current_dialogue.nodes[_current_node])
	node_changed.emit(_current_node, node_dict)
	return node_dict

func get_current_node() -> Dictionary:
	if _current_dialogue == null:
		return {}
	if _current_node < 0 or _current_node >= _current_dialogue.nodes.size():
		return {}
	return _node_to_dict(_current_dialogue.nodes[_current_node])

func _node_to_dict(node: DialogueData.DialogueNode) -> Dictionary:
	var choices: Array[Dictionary] = []
	for choice: DialogueData.DialogueChoice in node.choices:
		choices.append({"text": choice.text, "next": choice.next_node})
	return {
		"speaker": node.speaker,
		"text": node.text,
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
