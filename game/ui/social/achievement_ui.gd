## AchievementUI - Achievement display and progress tracking
## Shows unlocked achievements and progress toward goals
extends Control
class_name AchievementUI

const UIStyles = preload("res://ui/components/ui_styles.gd")

var _player_id: String = ""
var _achievements: Array = []
var _unlocked: Array = []

signal panel_opened()
signal panel_closed()

func _ready() -> void:
	name = "AchievementUI"
	visible = false
	_setup_ui()
	_bind_signals()

func _setup_ui() -> void:
	# Main container
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	add_child(vbox)

	# Header
	var header := Label.new()
	header.name = "Header"
	header.text = "Achievements"
	header.add_theme_font_size_override("font_size", 18)
	vbox.add_child(header)

	# Stats row
	var stats := Label.new()
	stats.name = "Stats"
	stats.text = "Unlocked: 0 / 0"
	vbox.add_child(stats)

	# Achievement list (scrollable)
	var scroll := ScrollContainer.new()
	scroll.name = "AchievementScroll"
	scroll.custom_minimum_size.y = 350
	vbox.add_child(scroll)

	var list := VBoxContainer.new()
	list.name = "AchievementList"
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	# Close button
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(close)
	vbox.add_child(close_btn)

func _bind_signals() -> void:
	if AchievementService:
		AchievementService.achievement_unlocked.connect(_on_achievement_unlocked)
		AchievementService.achievement_progressed.connect(_on_achievement_progressed)

func _on_achievement_unlocked(player_id: String, achievement_id: String) -> void:
	if player_id != _player_id:
		return
	_unlocked.append(achievement_id)
	_update_stats()
	_refresh_achievements()

func _on_achievement_progressed(player_id: String, achievement_id: String, progress: float) -> void:
	if player_id != _player_id:
		return
	_refresh_achievements()

func open(panel_id: String = "") -> void:
	visible = true
	panel_opened.emit()
	_refresh_achievements()

func close() -> void:
	visible = false
	panel_closed.emit()

func toggle(panel_id: String = "") -> void:
	if visible:
		close()
	else:
		open(panel_id)

func is_open() -> bool:
	return visible

func set_player_id(player_id: String) -> void:
	_player_id = player_id
	if visible:
		_refresh_achievements()

func _refresh_achievements() -> void:
	var list: VBoxContainer = get_node_or_null("VBox/AchievementScroll/AchievementList")
	if not list:
		return
	
	# Clear existing
	for child in list.get_children():
		child.queue_free()
	
	# Load achievements (would come from a data source in full implementation)
	var all_achievements := _get_achievement_definitions()
	
	for ach in all_achievements:
		var row := _create_achievement_row(ach)
		list.add_child(row)
	
	_update_stats()

func _get_achievement_definitions() -> Array:
	# Placeholder - in full implementation, load from data files
	return [
		{"id": "first_blood", "name": "First Blood", "desc": "Defeat your first enemy", "category": "combat"},
		{"id": "slayer", "name": "Slayer", "desc": "Defeat 100 enemies", "category": "combat", "target": 100},
		{"id": "survivor", "name": "Survivor", "desc": "Survive a dangerous encounter", "category": "combat"},
		{"id": "social_butterfly", "name": "Social Butterfly", "desc": "Join a party", "category": "social"},
		{"id": "guild_member", "name": "Guild Member", "desc": "Join a guild", "category": "social"},
		{"id": "trader", "name": "Trader", "desc": "Complete your first trade", "category": "economy"},
		{"id": "collector", "name": "Collector", "desc": "Collect 50 items", "category": "economy", "target": 50},
		{"id": "explorer", "name": "Explorer", "desc": "Visit 10 zones", "category": "exploration", "target": 10},
	]

func _create_achievement_row(ach: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = 60
	
	var hbox := HBoxContainer.new()
	panel.add_child(hbox)
	
	var is_unlocked := _unlocked.has(ach.get("id", ""))
	
	# Unlocked indicator
	var icon := Label.new()
	icon.text = "★" if is_unlocked else "☆"
	icon.add_theme_color_override("font_color", Color.GOLD if is_unlocked else Color.DIM_GRAY)
	hbox.add_child(icon)
	
	# Achievement info
	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var name_lbl := Label.new()
	name_lbl.text = ach.get("name", "?")
	name_lbl.add_theme_color_override("font_color", Color.WHITE if is_unlocked else Color.DIM_GRAY)
	info_vbox.add_child(name_lbl)
	
	var desc_lbl := Label.new()
	desc_lbl.text = ach.get("desc", "")
	desc_lbl.add_theme_font_size_override("font_size", 10)
	desc_lbl.add_theme_color_override("font_color", Color.GRAY)
	info_vbox.add_child(desc_lbl)
	
	# Progress if applicable
	if ach.has("target"):
		var progress_lbl := Label.new()
		var progress := 0  # Would get actual progress from service
		progress_lbl.text = "%d / %d" % [progress, ach.target]
		progress_lbl.add_theme_font_size_override("font_size", 10)
		info_vbox.add_child(progress_lbl)
	
	hbox.add_child(info_vbox)
	
	return panel

func _update_stats() -> void:
	var stats: Label = get_node_or_null("VBox/Stats")
	if stats:
		stats.text = "Unlocked: %d / %d" % [_unlocked.size(), _get_achievement_definitions().size()]
