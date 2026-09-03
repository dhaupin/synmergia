## CharacterStatsUI - In-game character stats panel
## Shows all stats, allocated points, and allows allocation

extends Control
class_name CharacterStatsUI

const UIStyles = preload("res://ui/components/ui_styles.gd")
const CharacterData = preload("res://core/schemas/character_data.gd")

var _player_id: String = ""
var _is_open: bool = false
signal panel_opened()
signal panel_closed()

func open(player_id: String) -> void:
	_open_impl(player_id)

func close() -> void:
	pass

func is_open() -> bool:
	return false

func toggle(player_id: String) -> void:
	pass

func get_panel() -> PanelContainer:
	return null

func get_content() -> VBoxContainer:
	return null

func set_title(title: String) -> void:
	pass

func set_panel_size(size: Vector2) -> void:
	pass

func show_notification(msg: String, success: bool = true) -> void:
	pass

const HEADER_HEIGHT: int = 40
const ROW_HEIGHT: int = 32

# Stat tier thresholds: Common/Rare/Epic/Legendary/Mythic
const TIER_THRESHOLDS: Dictionary = {
	"common": 0,
	"rare": 30,
	"epic": 60,
	"legendary": 90,
	"mythic": 120
}

const TIER_COLORS: Dictionary = {
	"common": Color(0.6, 0.6, 0.6),    # Gray
	"rare": Color(0.3, 0.7, 1.0),       # Blue
	"epic": Color(0.8, 0.3, 1.0),       # Purple
	"legendary": Color(1.0, 0.6, 0.1),  # Orange
	"mythic": Color(1.0, 0.2, 0.2)     # Red
}

const TIER_NAMES: Dictionary = {
	"common": "Common",
	"rare": "Rare",
	"epic": "Epic",
	"legendary": "Legendary",
	"mythic": "Mythic"
}

var _stat_rows: Dictionary = {}
var _stat_points_label: Label
var _focal_label: Label
var _academy_hint_label: Label
var _character_data: CharacterData = null

static func get_stat_tier(stat_value: int) -> Dictionary:
	if stat_value >= TIER_THRESHOLDS["mythic"]:
		return {"name": "mythic", "color": TIER_COLORS["mythic"], "label": "[M]"}
	elif stat_value >= TIER_THRESHOLDS["legendary"]:
		return {"name": "legendary", "color": TIER_COLORS["legendary"], "label": "[L]"}
	elif stat_value >= TIER_THRESHOLDS["epic"]:
		return {"name": "epic", "color": TIER_COLORS["epic"], "label": "[E]"}
	elif stat_value >= TIER_THRESHOLDS["rare"]:
		return {"name": "rare", "color": TIER_COLORS["rare"], "label": "[R]"}
	else:
		return {"name": "common", "color": TIER_COLORS["common"], "label": "[C]"}

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

	# Academy hint
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 10
	content.add_child(spacer)
	
	var academy_box := HBoxContainer.new()
	academy_box.name = "AcademyBox"
	academy_box.alignment = BoxContainer.ALIGNMENT_CENTER
	
	var hint_lbl := Label.new()
	hint_lbl.name = "AcademyHint"
	hint_lbl.text = "Visit the Skill Academy to respec stats"
	hint_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	hint_lbl.add_theme_font_size_override("font_size", 10)
	academy_box.add_child(hint_lbl)
	content.add_child(academy_box)
	_academy_hint_label = hint_lbl
	
	# Tier legend
	var legend_box := HBoxContainer.new()
	legend_box.name = "LegendBox"
	legend_box.alignment = BoxContainer.ALIGNMENT_CENTER
	
	var legend_lbl := Label.new()
	legend_lbl.name = "Legend"
	legend_lbl.text = "[C]Common  [R]Rare  [E]Epic  [L]Legendary  [M]Mythic"
	legend_lbl.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
	legend_lbl.add_theme_font_size_override("font_size", 9)
	legend_box.add_child(legend_lbl)
	content.add_child(legend_box)

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

	# Tier indicator
	var tier_lbl := Label.new()
	tier_lbl.name = "Tier"
	tier_lbl.text = "[C]"
	tier_lbl.add_theme_color_override("font_color", TIER_COLORS["common"])
	tier_lbl.custom_minimum_size.x = 30
	row.add_child(tier_lbl)

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
		"tier_lbl": tier_lbl,
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
	var all_stats: Dictionary = _character_data.get_all_stats_with_allocated()
	for stat_name in ["strength", "agility", "intelligence", "vitality", "endurance", "wisdom"]:
		var row_data: Dictionary = _stat_rows.get(stat_name)
		if not row_data:
			continue
		
		var total: int = all_stats.get(stat_name, 0)
		var allocated: int = _character_data.get_allocated_points(stat_name)
		
		row_data["value_lbl"].text = str(total)
		row_data["alloc_lbl"].text = "+%d" % allocated if allocated > 0 else ""
		
		# Update tier indicator
		var tier: Dictionary = get_stat_tier(total)
		row_data["tier_lbl"].text = tier["label"]
		row_data["tier_lbl"].add_theme_color_override("font_color", tier["color"])
		
		# Focal indicator
		var is_focal: bool = stat_name == focal1 or stat_name == focal2
		row_data["focal_lbl"].text = "★" if is_focal else ""
		
		# Button states
		row_data["plus_btn"].disabled = available <= 0
		row_data["minus_btn"].disabled = allocated <= 0
	
	# Update derived stats
	var entity: Node3D = _get_entity()
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
	var entity: Node3D = _get_entity()
	if entity and entity.has_method("on_stats_changed"):
		entity.on_stats_changed()

func _get_entity():
	if GameManager and _player_id != "":
		return GameManager.get_player_entity(_player_id)
	return null

func _open_impl(player_id: String) -> void:
	_player_id = player_id
	_character_data = null
	
	var entity: Node3D = _get_entity()
	if entity and entity.character_data:
		_character_data = entity.character_data
	
	_refresh()

func refresh() -> void:
	_refresh()
