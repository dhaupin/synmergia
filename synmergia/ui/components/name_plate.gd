## NamePlate - Floating name plate for entities
## Shows name, health bar, level, guild above entities
class_name NamePlate
extends Control

## Plate types
enum PlateType { PLAYER, NPC, ENEMY, OBJECT }

## Singleton
static var instance: NamePlate

## State
var _target_entity: Node = null
var _plate_type: PlateType = PlateType.PLAYER
var _health_percent: float = 1.0

## Components
var _name_label: Label
var _guild_label: Label
var _level_label: Label
var _health_bar: ProgressBar

## Settings
var _show_health: bool = true
var _show_guild: bool = true
var _show_level: bool = true

func _ready() -> void:
instance = self
_setup_ui()
hide()

func _setup_ui() -> void:
name = "NamePlate"

# Container
var vbox := VBoxContainer.new()
vbox.alignment = BoxContainer.ALIGNMENT_CENTER
add_child(vbox)

# Guild name (top)
_guild_label = Label.new()
_guild_label.name = "Guild"
_guild_label.text = ""
_guild_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
_guild_label.add_theme_font_size_override("font_size", 10)
_guild_label.add_theme_color_override("font_color", UIStyles.COLORS.info)
vbox.add_child(_guild_label)

# Level + Name row
var name_row := HBoxContainer.new()
name_row.alignment = BoxContainer.ALIGNMENT_CENTER
vbox.add_child(name_row)

_level_label = Label.new()
_level_label.name = "Level"
_level_label.text = ""
_level_label.add_theme_font_size_override("font_size", 10)
_level_label.add_theme_color_override("font_color", UIStyles.COLORS.warning)
name_row.add_child(_level_label)

var spacer := Label.new()
spacer.text = " "
name_row.add_child(spacer)

_name_label = Label.new()
_name_label.name = "Name"
_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
_name_label.add_theme_font_size_override("font_size", 12)
_name_label.add_theme_color_override("font_color", UIStyles.COLORS.text_primary)
name_row.add_child(_name_label)

# Health bar
_health_bar = ProgressBar.new()
_health_bar.name = "HealthBar"
_health_bar.min_value = 0
_health_bar.max_value = 100
_health_bar.value = 100
_health_bar.custom_minimum_size = Vector2(80, 6)
_health_bar.show_percentage = false
vbox.add_child(_health_bar)

## ============================================================================
## PUBLIC API
## ============================================================================

static func get_instance() -> NamePlate:
return instance

func show_for(entity: Node, plate_type: int, name: String, level: int = 0, guild: String = "") -> void:
_target_entity = entity
_plate_type = plate_type

_name_label.text = name

if level > 0 and _show_level:
_level_label.text = "[%d]" % level
_level_label.visible = true
else:
_level_label.visible = false

if not guild.is_empty() and _show_guild:
_guild_label.text = "[%s]" % guild
_guild_label.visible = true
else:
_guild_label.visible = false

# Color by type
match plate_type:
PlateType.PLAYER:
_name_label.add_theme_color_override("font_color", UIStyles.COLORS.text_primary)
PlateType.NPC:
_name_label.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
PlateType.ENEMY:
_name_label.add_theme_color_override("font_color", UIStyles.COLORS.error)
PlateType.OBJECT:
_name_label.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)

show()

func hide_for(entity: Node) -> void:
if _target_entity == entity:
_target_entity = null
hide()

func update_health(current: int, maximum: int) -> void:
if maximum <= 0:
maximum = 1

_health_percent = float(current) / float(maximum)
_health_bar.value = _health_percent * 100

# Color based on health
if _health_percent > 0.5:
_health_bar.add_theme_color_override("fill", UIStyles.COLORS.success)
elif _health_percent > 0.25:
_health_bar.add_theme_color_override("fill", UIStyles.COLORS.warning)
else:
_health_bar.add_theme_color_override("fill", UIStyles.COLORS.error)

func set_show_health(show: bool) -> void:
_show_health = show
_health_bar.visible = show

func set_show_guild(show: bool) -> void:
_show_guild = show
if not show:
_guild_label.visible = false

func set_show_level(show: bool) -> void:
_show_level = show
if not show:
_level_label.visible = false

func is_visible_for(entity: Node) -> bool:
return visible and _target_entity == entity

func get_target() -> Node:
return _target_entity
