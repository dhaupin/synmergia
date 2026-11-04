## DialogUI - NPC dialog system
## Quest offers, conversation, choices
## Extends UIPanel with bottom-anchored positioning
extends "res://ui/components/ui_panel.gd"
class_name DialogUI
# NOTE: DialogService is an autoload; reference it directly.

## Dialog state
var _current_npc: String = ""
var _current_npc_id: String = ""
var _dialogue_id: String = ""
var _current_dialogue_id: String = ""
var _current_node: int = 0
var _choices: Array = []
var _npc_position: Vector3 = Vector3.ZERO  # For distance-based close

## Escape BBCode brackets in user-supplied content.
static func _esc(text: String) -> String:
	return text.replace("[", "[lb]")

## Components
var _speaker_label: Label
var _text_rich_label: RichTextLabel
var _choice_buttons: VBoxContainer
var _continue_btn: Button
var _portrait: TextureRect

func _ready() -> void:
	super._ready()
	_bind_signals()
	panel_closed.connect(_on_panel_closed)

## Script-class reference (script-mode-safe; the bare autoload
## identifier fails compile when autoloads are absent).
const DialogServiceClass = preload("res://core/services/dialog_service.gd")

func _bind_signals() -> void:
	if DialogServiceClass:
		var svc = DialogServiceClass.singleton()
		if svc:
			svc.node_changed.connect(_on_node_changed)
			svc.dialogue_started.connect(_on_dialogue_started)
			svc.dialogue_ended.connect(_on_dialogue_ended)

func _on_panel_closed() -> void:
	_current_npc = ""
	_dialogue_id = ""
	_npc_position = Vector3.ZERO

func _process(_delta: float) -> void:
	# Canonical distance check for dialog auto-close
	if _is_open and _npc_position != Vector3.ZERO:
		var player := _get_local_player()
		if player != null:
			check_interact_distance(player.global_position, _npc_position)

func _get_npc_position(npc_id: String) -> Vector3:
	# Look up NPC position via EntityService at runtime.
	var entity_svc = get_node_or_null("/root/EntityService")
	if entity_svc:
		var npc = entity_svc.get_entity(npc_id)
		if npc and is_instance_valid(npc):
			return npc.global_position
	return Vector3.ZERO

func _setup_panel() -> void:
	# Bottom-anchored positioning (unlike center UIPanel default)
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	offset_left = 50
	offset_top = -200
	offset_right = -50
	offset_bottom = -20

	# Background panel
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.name = "Panel"
	add_child(panel)

	var style := StyleBoxFlat.new()
	style.bg_color = UIStyles.COLORS.background
	style.border_color = UIStyles.COLORS.accent_gold
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(vbox)

	# Portrait row
	var portrait_row := HBoxContainer.new()
	portrait_row.custom_minimum_size.y = 60
	vbox.add_child(portrait_row)

	_portrait = TextureRect.new()
	_portrait.name = "Portrait"
	_portrait.custom_minimum_size = Vector2(60, 60)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_row.add_child(_portrait)

	var portrait_spacer := Control.new()
	portrait_spacer.custom_minimum_size.x = 10
	portrait_row.add_child(portrait_spacer)

	_speaker_label = Label.new()
	_speaker_label.name = "Speaker"
	_speaker_label.add_theme_font_size_override("font_size", 16)
	_speaker_label.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	portrait_row.add_child(_speaker_label)

	# Dialog text
	_text_rich_label = RichTextLabel.new()
	_text_rich_label.name = "DialogText"
	_text_rich_label.bbcode_enabled = true
	_text_rich_label.custom_minimum_size.y = 60
	_text_rich_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text_rich_label.add_theme_color_override("default_color", UIStyles.COLORS.text_primary)
	vbox.add_child(_text_rich_label)

	# Choices container
	_choice_buttons = VBoxContainer.new()
	_choice_buttons.name = "Choices"
	vbox.add_child(_choice_buttons)

	# Continue button
	_continue_btn = Button.new()
	_continue_btn.name = "Continue"
	_continue_btn.text = "Continue..."
	_continue_btn.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_continue_btn.pressed.connect(_on_continue_pressed)
	# A11y: reader hears the verb and its consequence, not just text.
	var A11yStyles = load("res://ui/components/ui_styles.gd")
	if A11yStyles:
		A11yStyles.apply_accessibility(_continue_btn, "Continue dialog", "Advances the conversation to the next line")
	vbox.add_child(_continue_btn)

func show_dialog(npc_id: String, dialogue_id: String) -> void:
	_current_npc = npc_id
	_dialogue_id = dialogue_id
	# Store NPC position for distance check
	_npc_position = _get_npc_position(npc_id)
	set_max_interact_distance(5.0)  # Default dialog range
	var svc = DialogServiceClass.singleton()
	if svc and svc.start_dialogue(npc_id, dialogue_id):
		open("")
		return
	# Fallback: demo mode
	_show_node(0)
	open("")

func _show_node(node_index: int) -> void:
	# DialogService handles loading from .tres; this is the demo fallback
	# For demo, show placeholder
	_speaker_label.text = "NPC"
	_text_rich_label.clear()
	_text_rich_label.append_text("[color=%s]Hello, traveler![/color]" % UIStyles.COLORS.text_primary.to_html())

	# Clear choices
	for child in _choice_buttons.get_children():
		child.queue_free()
	_choices.clear()

	# Show demo choices
	var demo_choices := [
		{"text": "What do you have for me?", "next": 1},
		{"text": "I need to go.", "next": -1}
	]

	for choice in demo_choices:
		var btn := Button.new()
		btn.text = choice.text
		btn.pressed.connect(_on_choice_selected.bind(choice))
		# A11y: name the REPLY, not the widget (reader hears the words).
		var A11yStyles = load("res://ui/components/ui_styles.gd")
		if A11yStyles:
			A11yStyles.apply_accessibility(btn, "Say: %s" % choice.text, "Replies to the NPC with this choice")
		_choice_buttons.add_child(btn)
		_choices.append(choice)

	_continue_btn.visible = false

func _on_dialogue_started(npc_id: String, dialogue_id: String) -> void:
	_current_npc_id = npc_id
	_current_dialogue_id = dialogue_id
	open("")

func _on_dialogue_ended(npc_id: String, dialogue_id: String) -> void:
	_current_npc_id = ""
	_current_dialogue_id = ""
	close()

func _on_node_changed(node_index: int, node_data: Dictionary) -> void:
	_show_node_data(node_data)

func _show_node_data(node: Dictionary) -> void:
	_speaker_label.text = node.get("speaker", "NPC")
	_text_rich_label.clear()
	var text: String = node.get("text", "")
	_text_rich_label.append_text("[color=%s]%s[/color]" % [UIStyles.COLORS.text_primary.to_html(), _esc(text)])

	for child in _choice_buttons.get_children():
		child.queue_free()
	_choices.clear()

	var choices: Array = node.get("choices", [])
	if not choices.is_empty():
		for i in range(choices.size()):
			var choice: Dictionary = choices[i]
			var btn := Button.new()
			btn.text = choice.get("text", "")
			btn.pressed.connect(_on_choice_selected.bind(i))
			_choice_buttons.add_child(btn)
		_continue_btn.visible = false
	else:
		_continue_btn.visible = true

func _on_choice_selected(choice_index: int) -> void:
	var svc = DialogServiceClass.singleton()
	if svc:
		svc.select_choice(choice_index)
		return
	# Fallback
	var demo_choices := [
		{"text": "What do you have for me?", "next": 1},
		{"text": "I need to go.", "next": -1}
	]
	if choice_index >= 0 and choice_index < demo_choices.size():
		var next: int = demo_choices[choice_index].get("next", -1)
		if next < 0:
			close()
			return
		_show_node(next)

func _on_continue_pressed() -> void:
	# Advance the REAL dialogue service (the same call the receipt/tree walk
	# uses). The old body called the demo fallback _show_node(), so pressing
	# Continue on a choice-less node (every authored dialogue ends on one)
	# painted the placeholder "Hello, traveler!" and never advanced or closed
	# the conversation -- the demo path is only for a service-less boot.
	var svc = DialogServiceClass.singleton()
	if svc and svc.get_current_node() != {}:
		svc.advance()
		return
	_current_node += 1
	_show_node(_current_node)
