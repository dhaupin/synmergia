## CharacterStatsUI - In-game character stats panel
## Shows all stats, allocated points, and allows allocation
class_name CharacterStatsUI
extends UIPanel

const HEADER_HEIGHT: int = 40
const ROW_HEIGHT: int = 32

var _stat_rows: Dictionary = {}
var _stat_points_label: Label
var _focal_label: Label
var _character_data: CharacterData = null

func _setup_panel() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(360, 420)
	panel.add_theme_stylebox_override("panel", UIStyles.create_panel_style())
	panel.name = "Panel"
	add_child(panel)

	var main := VBoxContainer.new()
	main.name = "Main"
	panel.add_child(main)

	# Header
	var header := HBoxContainer.new()
	header.name = "Header"
	header.custom_minimum_size.y = HEADER_HEIGHT
	
	var title := Label.new()
	title.text = "Character Stats"
	title.add_theme_font_size_override("font_size", 18)
	header.add_child(title)
	
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.pressed.connect(close)
	header.add_child(close_btn)
	
	main.add_child(header)

	# Stats scroll area
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(scroll)

	var content := VBoxContainer.new()
	content.name = "Content"
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)

	# Points available
	var points_box := HBoxContainer.new()
	points_box.name = "PointsBox"
	points_box.custom_minimum_size.y = 40
	
	_stat_points_label = Label.new()
	_stat_points_label.name = "StatPointsLabel"
	_stat_points_label.text = "Available Points: --"
	_stat_points_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
	points_box.add_child(_stat_points_label)
	
	content.add_child(points_box)

	# Focal stats info
	_focal_label = Label.new()
	_focal_label.name = "FocalLabel"
	_focal_label.text = ""
	_focal_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	content.add_child(_focal_label)

	# Stats
	var stats := ["strength", "agility", "intelligence", "vitality", "endurance", "wisdom"]
	for stat in stats:
		var row := _build_stat_row(stat)
		content.add_child(row)

	# Derived stats section
	var derived_header := Label.new()
	derived_header.text = "Derived Stats"
	derived_header.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	content.add_child(derived_header)

	var derived := ["max_health", "max_mana", "max_stamina"]
	for stat in derived:
		var row := _build_derived_row(stat)
		content.add_child(row)

func _build_stat_row(stat_name: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = stat_name.capitalize() + "Row"
	row.custom_minimum_size.y = ROW_HEIGHT

	# Stat name
	var name_lbl := Label.new()
	name_lbl.name = "Name"
	name_lbl.text = stat_name.capitalize()
	name_lbl.custom_minimum_size.x = 90
	row.add_child(name_lbl)

	# Value
	var value_lbl := Label.new()
	value_lbl.name = "Value"
	value_lbl.text = "--"
	value_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_lbl.custom_minimum_size.x = 70
	row.add_child(value_lbl)

	# Allocated indicator
	var alloc_lbl := Label.new()
	alloc_lbl.name = "Allocated"
	alloc_lbl.text = ""
	alloc_lbl.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
	alloc_lbl.custom_minimum_size.x = 40
	row.add_child(alloc_lbl)

	# Minus button
	var minus_btn := Button.new()
	minus_btn.name = "Minus"
	minus_btn.text = "-"
	minus_btn.custom_minimum_size.x = 28
	minus_btn.pressed.connect(func(): _on_stat_minus(stat_name))
	row.add_child(minus_btn)

	# Plus button
	var plus_btn := Button.new()
	plus_btn.name = "Plus"
	plus_btn.text = "+"
	plus_btn.custom_minimum_size.x = 28
	plus_btn.pressed.connect(func(): _on_stat_plus(stat_name))
	row.add_child(plus_btn)

	# Focal indicator
	var focal_lbl := Label.new()
	focal_lbl.name = "Focal"
	focal_lbl.text = ""
	focal_lbl.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	row.add_child(focal_lbl)

	_stat_rows[stat_name] = {
		"row": row,
		"value_lbl": value_lbl,
		"alloc_lbl": alloc_lbl,
		"plus_btn": plus_btn,
		"minus_btn": minus_btn,
		"focal_lbl": focal_lbl
	}

	return row

func _build_derived_row(stat_name: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = stat_name + "Row"
	row.custom_minimum_size.y = ROW_HEIGHT

	var name_lbl := Label.new()
	name_lbl.name = "Name"
	name_lbl.text = stat_name.replace("_", " ").capitalize()
	name_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	row.add_child(name_lbl)

	var value_lbl := Label.new()
	value_lbl.name = "Value"
	value_lbl.text = "--"
	value_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_lbl.custom_minimum_size.x = 60
	value_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	row.add_child(value_lbl)

	_stat_rows[stat_name] = {"value_lbl": value_lbl}

	return row

func _refresh() -> void:
	if _character_data == null:
		return
	
	var cls := _character_data.class_data
	var focal1 := cls.focal_stat_1 if cls else ""
	var focal2 := cls.focal_stat_2 if cls else ""
	
	# Update focal label
	_focal_label.text = "Focal Stats: %s + %s" % [focal1.capitalize(), focal2.capitalize()]
	
	# Update available points
	var available := _character_data.get_available_stat_points()
	_stat_points_label.text = "Available Points: %d" % available
	
	# Update stats
	var all_stats := _character_data.get_all_stats_with_allocated()
	for stat_name in ["strength", "agility", "intelligence", "vitality", "endurance", "wisdom"]:
		var row_data := _stat_rows.get(stat_name)
		if not row_data:
			continue
		
		var total: int = all_stats.get(stat_name, 0)
		var allocated: int = _character_data.get_allocated_points(stat_name)
		
		row_data["value_lbl"].text = str(total)
		row_data["alloc_lbl"].text = "+%d" % allocated if allocated > 0 else ""
		
		# Focal indicator
		var is_focal := stat_name == focal1 or stat_name == focal2
		row_data["focal_lbl"].text = "★" if is_focal else ""
		
		# Button states
		row_data["plus_btn"].disabled = available <= 0
		row_data["minus_btn"].disabled = allocated <= 0
	
	# Update derived stats
	var entity := _get_entity()
	if entity:
		_stat_rows["max_health"]["value_lbl"].text = str(entity.max_health)
		_stat_rows["max_mana"]["value_lbl"].text = str(entity.max_mana)
		_stat_rows["max_stamina"]["value_lbl"].text = str(int(entity.max_stamina))

func _on_stat_plus(stat_name: String) -> void:
	if _character_data == null:
		return
	
	if _character_data.allocate_stat_point(stat_name):
		_refresh()
		_notify_change()

func _on_stat_minus(stat_name: String) -> void:
	if _character_data == null:
		return
	
	if _character_data.deallocate_stat_point(stat_name):
		_refresh()
		_notify_change()

func _notify_change() -> void:
	var entity := _get_entity()
	if entity and entity.has_method("on_stats_changed"):
		entity.on_stats_changed()

func _get_entity():
	if GameManager and _player_id != "":
		return GameManager.get_player_entity(_player_id)
	return null

func open(player_id: String) -> void:
	_player_id = player_id
	_character_data = null
	
	var entity := _get_entity()
	if entity and entity.character_data:
		_character_data = entity.character_data
	
	_refresh()
	super.open(player_id)

func refresh() -> void:
	_refresh()
