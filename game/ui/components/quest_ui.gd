## QuestUI - Quest journal panel
## Shows active quests, objectives, and quest log
extends "res://ui/components/ui_panel.gd"
class_name QuestUI
const UIPanel = preload("res://ui/components/ui_panel.gd")
const QuestData = preload("res://core/schemas/quest_data.gd")

## Escape BBCode brackets in user-supplied content.
static func _esc(text: String) -> String:
	return text.replace("[", "[lb]").replace("]", "[rb]")

## Tab definitions
enum Tab { ACTIVE, COMPLETE, AVAILABLE }
var _current_tab: Tab = Tab.ACTIVE

## Components
var _tab_bar: HBoxContainer
var _quest_list: VBoxContainer
var _quest_detail: VBoxContainer
var _selected_quest: String = ""
var _tab_buttons: Array = []

func _ready() -> void:
	super._ready()
	set_title("Quest Journal")
	set_panel_size(Vector2(500, 450))
	_setup_accessibility()
	_setup_ui()
	_connect_signals()

func _setup_accessibility() -> void:
	accessible_name = "Quest Journal"
	accessible_description = "Quest journal panel. Use tabs to switch between Active, Complete, and Available quests. Select a quest to view details."

func update_accessibility_settings() -> void:
	# Update tab buttons
	if _tab_buttons:
		for btn in _tab_buttons:
			if btn and is_instance_valid(btn):
				btn.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
				var scale = UIStyles.get_text_scale()
				var current_size := btn.get_theme_font_size("font_size")
				if current_size > 0:
					btn.add_theme_font_size_override("font_size", int(current_size * scale))
	
	# Update quest list items
	if _quest_list:
		for child in _quest_list.get_children():
			if child is Button:
				child.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
				var scale = UIStyles.get_text_scale()
				var current_size := child.get_theme_font_size("font_size")
				if current_size > 0:
					child.add_theme_font_size_override("font_size", int(current_size * scale))
			elif child is PanelContainer:
				child.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
				var style: StyleBoxFlat = child.get_theme_stylebox("panel")
				if style:
					if UIStyles.is_high_contrast_enabled():
						style.bg_color = UIStyles.HIGH_CONTRAST_COLORS.background
						style.border_color = UIStyles.HIGH_CONTRAST_COLORS.border
					else:
						style.bg_color = UIStyles.COLORS.background_dark
						style.border_color = UIStyles.COLORS.border

func _setup_ui() -> void:
	var panel := get_panel()
	if not panel:
		return

	var main: VBoxContainer = panel.get_node_or_null("Main")
	if not main:
		return

	# Tab bar
	_tab_bar = HBoxContainer.new()
	_tab_bar.custom_minimum_size.y = 36
	_tab_bar.focus_mode = Control.FOCUS_ALL
	_tab_bar.accessible_name = "Quest Journal Tabs"
	_tab_bar.accessible_description = "Switch between Active, Complete, and Available quest tabs."
	_tab_bar.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
	main.add_child(_tab_bar)

	var tabs := [
		{"id": Tab.ACTIVE, "name": "Active"},
		{"id": Tab.COMPLETE, "name": "Complete"},
		{"id": Tab.AVAILABLE, "name": "Available"}
	]

	for tab_data in tabs:
		var btn := Button.new()
		btn.text = tab_data.name
		btn.toggle_mode = true
		btn.button_pressed = false
		btn.focus_mode = Control.FOCUS_ALL
		btn.accessible_name = "Quest Tab: %s" % tab_data.name
		btn.accessible_description = "Show %s quests." % tab_data.name
		btn.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
		btn.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
		btn.pressed.connect(_on_tab_clicked.bind(tab_data.id))
		_tab_buttons.append(btn)
		_tab_bar.add_child(btn)

	# Content area (split view)
	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(content)

	# Quest list (left)
	var list_scroll := ScrollContainer.new()
	list_scroll.custom_minimum_size.x = 180
	list_scroll.focus_mode = Control.FOCUS_ALL
	list_scroll.accessible_name = "Quest List"
	list_scroll.accessible_description = "List of quests. Use arrow keys to navigate, Enter to select."
	list_scroll.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
	content.add_child(list_scroll)

	_quest_list = VBoxContainer.new()
	_quest_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.add_child(_quest_list)

	# Quest detail (right)
	var detail_scroll := ScrollContainer.new()
	detail_scroll.focus_mode = Control.FOCUS_ALL
	detail_scroll.accessible_name = "Quest Details"
	detail_scroll.accessible_description = "Detailed view of the selected quest including description, objectives, and actions."
	detail_scroll.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
	content.add_child(detail_scroll)

	_quest_detail = VBoxContainer.new()
	_quest_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(_quest_detail)

	# Initialize with empty state
	_show_empty_detail()

func _connect_signals() -> void:
	if QuestService:
		QuestService.quest_accepted.connect(_on_quest_accepted)
		QuestService.quest_updated.connect(_on_quest_updated)
		QuestService.quest_completed.connect(_on_quest_completed)
		QuestService.quest_rewarded.connect(_on_quest_rewarded)

	# Load quests for local player
	var local_id := str(PlayerManager.local_player.entity_id) if PlayerManager.local_player else "" if PlayerManager else ""
	if not local_id.is_empty():
		refresh_quest_list()

func _on_tab_clicked(tab_id: int) -> void:
	_current_tab = tab_id

	# Update tab buttons
	for i in range(_tab_buttons.size()):
		var btn: Button = _tab_buttons[i]
		btn.button_pressed = (i == tab_id)
		if btn.button_pressed:
			btn.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
		else:
			btn.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)

	refresh_quest_list()

func refresh_quest_list() -> void:
	# Clear list
	for child in _quest_list.get_children():
		child.queue_free()

	var local_id := str(PlayerManager.local_player.entity_id) if PlayerManager.local_player else "" if PlayerManager else ""
	if local_id.is_empty():
		return

	var quests: Array = []
	match _current_tab:
		Tab.ACTIVE:
			quests = QuestService.get_active_quests(local_id)
		Tab.COMPLETE:
			quests = _get_completed_quests(local_id)
		Tab.AVAILABLE:
			quests = QuestService.get_available_quests(local_id)

	if quests.is_empty():
		var empty := Label.new()
		empty.text = "(No quests)"
		empty.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
		_quest_list.add_child(empty)
		return

	for quest_id in quests:
		var quest_btn := _create_quest_button(quest_id)
		_quest_list.add_child(quest_btn)

func _get_completed_quests(player_id: String) -> Array:
	var completed := []
	var player_quests: Dictionary = QuestService.get_player_quests(player_id)
	for quest_id in player_quests:
		var state: int = player_quests[quest_id].get("state", QuestData.QuestState.LOCKED)
		if state == QuestData.QuestState.COMPLETE:
			completed.append(quest_id)
	return completed

func _create_quest_button(quest_id: String) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size.y = 40
	btn.text_alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_color_override("font_color", UIStyles.COLORS.text_primary)
	btn.focus_mode = Control.FOCUS_ALL
	btn.accessible_name = "Quest: %s" % _get_quest_name(quest_id)
	btn.accessible_description = "Press Enter to view quest details."
	btn.add_theme_stylebox_override("focus", UIStyles.create_focus_style())

	# Get quest name
	var quest_name := _get_quest_name(quest_id)
	btn.text = "  " + quest_name

	btn.pressed.connect(_on_quest_selected.bind(quest_id))
	return btn

func _get_quest_name(quest_id: String) -> String:
	var progress := QuestService.get_quest_progress("", quest_id)
	if not progress.is_empty():
		var data: QuestData = progress.get("data")
		if data:
			return data.display_name
	# Fallback
	return quest_id

func _on_quest_selected(quest_id: String) -> void:
	_selected_quest = quest_id
	_show_quest_detail(quest_id)

func _show_quest_detail(quest_id: String) -> void:
	# Clear detail
	for child in _quest_detail.get_children():
		child.queue_free()

	var local_id := str(PlayerManager.local_player.entity_id) if PlayerManager.local_player else "" if PlayerManager else ""
	var progress := QuestService.get_quest_progress(local_id, quest_id)
	if progress.is_empty():
		_show_empty_detail()
		return

	var data: QuestData = progress.get("data")
	var state: int = progress.get("state", QuestData.QuestState.LOCKED)

	# Quest title
	var title := Label.new()
	title.text = data.display_name if data else quest_id
	title.add_theme_font_size_override("font_size", 16)
	_quest_detail.add_child(title)

	# Quest type badge
	var type_label := Label.new()
	if data:
		var type_names := ["Main", "Side", "Daily", "Weekly", "Event", "Guild"]
		type_label.text = "[%s]" % type_names[data.quest_type]
	else:
		type_label.text = "[Unknown]"
	type_label.add_theme_color_override("font_color", _get_quest_type_color(state))
	_quest_detail.add_child(type_label)

	# Separator
	var sep := HSeparator.new()
	_quest_detail.add_child(sep)

	# Description
	var desc := Label.new()
	desc.text = data.description if data else "No description"
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	_quest_detail.add_child(desc)

	# Objectives header
	var obj_header := Label.new()
	obj_header.text = "Objectives:"
	obj_header.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	_quest_detail.add_child(obj_header)

	# Objectives list
	var objectives: Array = progress.get("objectives", [])
	for obj_text in QuestService.get_quest_objectives_text(local_id, quest_id):
		var obj_label := RichTextLabel.new()
		obj_label.bbcode_enabled = true
		obj_label.text = "[bullet] %s" % _esc(str(obj_text))
		obj_label.add_theme_color_override("default_color", UIStyles.COLORS.text_primary)
		obj_label.custom_minimum_size.y = 20
		_quest_detail.add_child(obj_label)

	# State-specific actions
	var action_container := HBoxContainer.new()
	action_container.custom_minimum_size.y = 40
	_quest_detail.add_child(action_container)

	match state:
		QuestData.QuestState.AVAILABLE:
			var accept_btn := Button.new()
			accept_btn.text = "Accept Quest"
			accept_btn.focus_mode = Control.FOCUS_ALL
			accept_btn.accessible_name = "Accept Quest"
			accept_btn.accessible_description = "Accept this quest and add it to your active quests."
			accept_btn.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
			accept_btn.pressed.connect(_on_accept_quest.bind(quest_id))
			action_container.add_child(accept_btn)

		QuestData.QuestState.COMPLETE:
			var turn_in_btn := Button.new()
			turn_in_btn.text = "Turn In"
			turn_in_btn.add_theme_color_override("font_color", UIStyles.COLORS.success)
			turn_in_btn.focus_mode = Control.FOCUS_ALL
			turn_in_btn.accessible_name = "Turn In Quest"
			turn_in_btn.accessible_description = "Complete this quest and receive rewards."
			turn_in_btn.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
			turn_in_btn.pressed.connect(_on_turn_in_quest.bind(quest_id))
			action_container.add_child(turn_in_btn)

		QuestData.QuestState.IN_PROGRESS:
			var abandon_btn := Button.new()
			abandon_btn.text = "Abandon"
			abandon_btn.add_theme_color_override("font_color", UIStyles.COLORS.error)
			abandon_btn.focus_mode = Control.FOCUS_ALL
			abandon_btn.accessible_name = "Abandon Quest"
			abandon_btn.accessible_description = "Abandon this quest and lose all progress."
			abandon_btn.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
			abandon_btn.pressed.connect(_on_abandon_quest.bind(quest_id))
			action_container.add_child(abandon_btn)

func _show_empty_detail() -> void:
	for child in _quest_detail.get_children():
		child.queue_free()

	var empty := Label.new()
	empty.text = "Select a quest to view details"
	empty.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quest_detail.add_child(empty)

func _get_quest_type_color(state: int) -> Color:
	match state:
		QuestData.QuestState.AVAILABLE: return UIStyles.COLORS.info
		QuestData.QuestState.IN_PROGRESS: return UIStyles.COLORS.warning
		QuestData.QuestState.COMPLETE: return UIStyles.COLORS.success
		QuestData.QuestState.REWARDED: return UIStyles.COLORS.text_secondary
	return UIStyles.COLORS.text_primary

func _on_accept_quest(quest_id: String) -> void:
	var local_id := str(PlayerManager.local_player.entity_id) if PlayerManager.local_player else "" if PlayerManager else ""
	if local_id.is_empty():
		return

	if QuestService.accept_quest(local_id, quest_id):
		show_notification("Quest accepted!")
		_current_tab = Tab.ACTIVE
		refresh_quest_list()

func _on_turn_in_quest(quest_id: String) -> void:
	var local_id := str(PlayerManager.local_player.entity_id) if PlayerManager.local_player else "" if PlayerManager else ""
	if local_id.is_empty():
		return

	if QuestService.turn_in_quest(local_id, quest_id):
		show_notification("Quest completed! Rewards received.")
		_current_tab = Tab.COMPLETE
		refresh_quest_list()

func _on_abandon_quest(quest_id: String) -> void:
	var local_id := str(PlayerManager.local_player.entity_id) if PlayerManager.local_player else "" if PlayerManager else ""
	if local_id.is_empty():
		return

	if QuestService.abandon_quest(local_id, quest_id):
		show_notification("Quest abandoned.", false)
		refresh_quest_list()
		_show_empty_detail()

func _on_quest_accepted(player_id: String, quest_id: String) -> void:
	if player_id == str(PlayerManager.local_player.entity_id) if PlayerManager.local_player else "":
		refresh_quest_list()

func _on_quest_updated(player_id: String, quest_id: String, objective_id: String, progress: int) -> void:
	if player_id == str(PlayerManager.local_player.entity_id) if PlayerManager.local_player else "":
		if _selected_quest == quest_id:
			_show_quest_detail(quest_id)

func _on_quest_completed(player_id: String, quest_id: String) -> void:
	if player_id == str(PlayerManager.local_player.entity_id) if PlayerManager.local_player else "":
		refresh_quest_list()

func _on_quest_rewarded(player_id: String, quest_id: String, rewards: Dictionary) -> void:
	if player_id == str(PlayerManager.local_player.entity_id) if PlayerManager.local_player else "":
		refresh_quest_list()
