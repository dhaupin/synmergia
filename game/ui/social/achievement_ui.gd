## AchievementUI - Achievement display and progress tracking
extends UIPanel
class_name AchievementUI
const UIStyles = preload("res://ui/components/ui_styles.gd")
const AchievementData = preload("res://core/schemas/achievement_data.gd")

var _achievement_defs: Dictionary = {}
var _current_category: int = -1  # -1 = all categories
var _category_buttons: Array[Button] = []

func _ready() -> void:
	super._ready()
	set_title("Achievements")
	set_panel_size(Vector2(500, 450))
	_setup_ui()
	_bind_signals()

func _setup_ui() -> void:
	var panel := get_panel()
	if not panel:
		return

	var main: VBoxContainer = panel.get_node_or_null("Main")
	if not main:
		return

	# Stats
	var stats := Label.new()
	stats.name = "Stats"
	stats.text = "Unlocked: 0 / 0"
	main.add_child(stats)

	# Category filter buttons
	var filter_hbox := HBoxContainer.new()
	filter_hbox.name = "FilterBar"
	main.add_child(filter_hbox)

	var categories := [
		{"id": -1, "name": "All"},
		{"id": 0, "name": "Combat"},
		{"id": 1, "name": "Social"},
		{"id": 2, "name": "Economy"},
		{"id": 3, "name": "Exploration"},
		{"id": 4, "name": "Meta"}
	]

	for cat in categories:
		var btn := Button.new()
		btn.text = cat.name
		btn.custom_minimum_size.x = 70
		btn.toggle_mode = true
		btn.button_pressed = (cat.id == -1)
		btn.pressed.connect(_on_category_selected.bind(cat.id))
		_category_buttons.append(btn)
		filter_hbox.add_child(btn)

	# Scroll area
	var scroll := ScrollContainer.new()
	scroll.name = "AchievementScroll"
	scroll.custom_minimum_size.y = 350
	main.add_child(scroll)

	var list := VBoxContainer.new()
	list.name = "AchievementList"
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

func _on_category_selected(category: int) -> void:
	_current_category = category
	_refresh_achievements()

func _bind_signals() -> void:
	var root := get_tree().root if get_tree() else null
	if root:
		var ach_inst: Node = root.get_node_or_null("AchievementService")
		if ach_inst:
			if ach_inst.has_signal("achievement_unlocked"):
				ach_inst.achievement_unlocked.connect(_on_achievement_unlocked)
			if ach_inst.has_signal("achievement_progressed"):
				ach_inst.achievement_progressed.connect(_on_achievement_progressed)

func _on_achievement_unlocked(player_id: String, achievement_id: String) -> void:
	if player_id != _player_id:
		return
	_refresh_achievements()

func _on_achievement_progressed(player_id: String, achievement_id: String, progress: float) -> void:
	if player_id != _player_id:
		return
	_refresh_achievements()

func _on_open() -> void:
	_load_achievement_definitions()
	_refresh_achievements()

func _load_achievement_definitions() -> void:
	var root := get_tree().root if get_tree() else null
	if root:
		var ach_inst: Node = root.get_node_or_null("AchievementService")
		if ach_inst and ach_inst.has_method("get_all_achievements"):
			_achievement_defs = ach_inst.get_all_achievements()

func _get_achievement_list() -> Array:
	var list: Array = []
	for ach_id in _achievement_defs:
		list.append(_achievement_defs[ach_id])
	list.sort_custom(func(a, b): return a.sort_order < b.sort_order)
	return list

func _get_player_progress(achievement_id: String) -> Dictionary:
	var root := get_tree().root if get_tree() else null
	if root:
		var ach_inst: Node = root.get_node_or_null("AchievementService")
		if ach_inst and ach_inst.has_method("get_achievement_progress"):
			return ach_inst.get_achievement_progress(_player_id, achievement_id)
	return {"progress": 0.0, "unlocked": false}

func _refresh_achievements() -> void:
	var list: VBoxContainer = get_node_or_null("Panel/Main/AchievementScroll/AchievementList")
	if not list:
		return

	for child in list.get_children():
		child.queue_free()

	var all_achievements: Array = _get_achievement_list()
	var unlocked_count := 0
	var visible_count := 0

	for ach in all_achievements:
		# Apply category filter
		if _current_category >= 0 and ach.category != _current_category:
			continue
		visible_count += 1

		var progress: Dictionary = _get_player_progress(ach.id)
		var row := _create_achievement_row(ach, progress)
		list.add_child(row)
		if progress.get("unlocked", false):
			unlocked_count += 1

	_update_stats(unlocked_count, visible_count)

func _create_achievement_row(ach: AchievementData, progress: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = 80

	var style := StyleBoxFlat.new()
	style.bg_color = UIStyles.COLORS.background_dark
	style.border_color = UIStyles.COLORS.border
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	panel.add_child(hbox)

	var is_unlocked: bool = progress.get("unlocked", false)

	# Icon
	var icon := Label.new()
	icon.text = "★" if is_unlocked else "☆"
	icon.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold if is_unlocked else UIStyles.COLORS.text_disabled)
	icon.custom_minimum_size.x = 30
	hbox.add_child(icon)

	# Info section
	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info_vbox)

	# Name
	var name_lbl := Label.new()
	name_lbl.text = ach.display_name
	name_lbl.add_theme_color_override("font_color", UIStyles.COLORS.text_primary if is_unlocked else UIStyles.COLORS.text_secondary)
	info_vbox.add_child(name_lbl)

	# Description
	var desc_lbl := Label.new()
	desc_lbl.text = ach.description if is_unlocked or not ach.hidden else "???"
	desc_lbl.add_theme_font_size_override("font_size", 10)
	desc_lbl.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	info_vbox.add_child(desc_lbl)

	# Progress bar (for non-GLOBAL achievements)
	if ach.achievement_type != AchievementData.AchievementType.GLOBAL:
		var progress_bar := ProgressBar.new()
		progress_bar.name = "ProgressBar"
		progress_bar.min_value = 0
		progress_bar.max_value = 100
		progress_bar.step = 1
		progress_bar.show_percentage = false

		var progress_val: float = progress.get("progress", 0.0)
		var percentage: float = ach.get_progress_percentage(progress_val)
		progress_bar.value = percentage * 100

		# Color based on completion
		if is_unlocked:
			progress_bar.add_theme_color_override("fill", UIStyles.COLORS.success)
		else:
			progress_bar.add_theme_color_override("fill", UIStyles.COLORS.info)

		progress_bar.custom_minimum_size.y = 8
		info_vbox.add_child(progress_bar)

	# Rewards section (right side)
	var rewards_vbox := VBoxContainer.new()
	rewards_vbox.name = "Rewards"
	rewards_vbox.custom_minimum_size.x = 80
	hbox.add_child(rewards_vbox)

	if ach.gold_reward > 0:
		var gold_lbl := Label.new()
		gold_lbl.text = "💰 %d" % ach.gold_reward
		gold_lbl.add_theme_font_size_override("font_size", 10)
		rewards_vbox.add_child(gold_lbl)

	if ach.xp_reward > 0:
		var xp_lbl := Label.new()
		xp_lbl.text = "⭐ %d XP" % ach.xp_reward
		xp_lbl.add_theme_font_size_override("font_size", 10)
		rewards_vbox.add_child(xp_lbl)

	if ach.title_reward != "":
		var title_lbl := Label.new()
		title_lbl.text = "🏆 Title"
		title_lbl.add_theme_font_size_override("font_size", 10)
		title_lbl.add_theme_color_override("font_color", UIStyles.COLORS.warning)
		rewards_vbox.add_child(title_lbl)

	return panel

func _update_stats(unlocked: int, total: int) -> void:
	var stats: Label = get_node_or_null("Panel/Main/Stats")
	if stats:
		stats.text = "Unlocked: %d / %d" % [unlocked, total]
