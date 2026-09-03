## DialogService - NPC dialogue loading and state management
## Loads dialogue trees from .tres files and drives DialogUI.
class_name DialogService
extends Node

## Dialogue tree entry
## nodes: Array of {speaker, text, choices: [{text, next}]}
## next=-1 means end conversation

var _dialogues: Dictionary = {}
var _current_dialogue: Dictionary = {}
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
		_create_default_dialogues()
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var path := "res://data/dialogues/" + file_name
			var dialogue = load(path)
			if dialogue:
				_dialogues[dialogue.id] = dialogue
		file_name = dir.get_next()
	dir.list_dir_end()

func _create_default_dialogues() -> void:
	# Create a default greeting dialogue
	var greeting := {
		"id": "default_greeting",
		"speaker": "NPC",
		"nodes": [
			{
				"speaker": "Friendly NPC",
				"text": "Greetings, traveler! Welcome to our village.",
				"choices": [
					{"text": "What can you tell me about this place?", "next": 1},
					{"text": "Do you have any work for me?", "next": 2},
					{"text": "Farewell.", "next": -1}
				]
			},
			{
				"speaker": "Friendly NPC",
				"text": "This village has stood for generations. To the north lies the Darkwood Forest, and to the east the Shattered Mountains.",
				"choices": [
					{"text": "Tell me about the forest.", "next": 3},
					{"text": "Thanks for the info.", "next": -1}
				]
			},
			{
				"speaker": "Friendly NPC",
				"text": "Indeed! Talk to the Village Elder — he always has work for capable adventurers.",
				"choices": [
					{"text": "I will seek him out.", "next": -1},
					{"text": "Maybe later.", "next": -1}
				]
			},
			{
				"speaker": "Friendly NPC",
				"text": "The Darkwood is treacherous. Wolves prowl its edges, and darker things lurk in its depths. Tread carefully.",
				"choices": [
					{"text": "I will keep that in mind. Farewell.", "next": -1}
				]
			}
		]
	}
	_dialogues[greeting.id] = greeting

func get_dialogue(dialogue_id: String) -> Dictionary:
	return _dialogues.get(dialogue_id, {})

func start_dialogue(npc_id: String, dialogue_id: String) -> bool:
	var dialogue := get_dialogue(dialogue_id)
	if dialogue.is_empty():
		GameLog.warn("DialogService: Dialogue not found: %s" % dialogue_id)
		return false
	_current_dialogue = dialogue
	_current_node = 0
	dialogue_started.emit(npc_id, dialogue_id)
	node_changed.emit(_current_node, get_current_node())
	return true

func advance() -> Dictionary:
	var node := get_current_node()
	if not node.is_empty() and node.get("choices", []).is_empty():
		_current_node += 1
		node = get_current_node()
	if node.is_empty() or _current_node < 0 or _current_node >= _current_dialogue.get("nodes", []).size():
		end_dialogue()
		return {}
	node_changed.emit(_current_node, node)
	return node

func select_choice(choice_index: int) -> Dictionary:
	var node := get_current_node()
	var choices: Array = node.get("choices", [])
	if choice_index < 0 or choice_index >= choices.size():
		return {}
	var choice: Dictionary = choices[choice_index]
	var next: int = choice.get("next", -1)
	if next < 0:
		end_dialogue()
		return {}
	_current_node = next
	var new_node := get_current_node()
	node_changed.emit(_current_node, new_node)
	return new_node

func get_current_node() -> Dictionary:
	var nodes: Array = _current_dialogue.get("nodes", [])
	if _current_node < 0 or _current_node >= nodes.size():
		return {}
	return nodes[_current_node]

func end_dialogue() -> void:
	var npc_id: String = _current_dialogue.get("npc_id", "")
	var dialogue_id: String = _current_dialogue.get("id", "")
	_current_dialogue = {}
	_current_node = 0
	dialogue_ended.emit(npc_id, dialogue_id)

func has_dialogue(dialogue_id: String) -> bool:
	return _dialogues.has(dialogue_id)
