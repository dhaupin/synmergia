## TooltipManager - Centralized tooltip system for Synmergia
class_name TooltipManager
extends CanvasLayer

## Singleton instance
static var instance: TooltipManager = null

## Tooltip panel
var _tooltip: PanelContainer
var _tooltip_label: RichTextLabel
var _tooltip_timer: Timer
var _fade_tween: Tween

## Tooltip data
var _current_data: Dictionary = {}
var _tooltip_type: String = ""
var _position_offset: Vector2 = Vector2(15, 15)

## Tooltip types
enum Type { NONE, ITEM, SKILL, ENTITY, STATUS, QUEST }

func _ready() -> void:
	if instance == null:
		instance = self
	else:
		queue_free()
		return
	
	_setup_tooltip()
	_process_mode = Node.PROCESS_MODE_ALWAYS

func _setup_tooltip() -> void:
	_tooltip = PanelContainer.new()
	_tooltip.z_index = 5000
	_tooltip.hide()
	add_child(_tooltip)
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.95)
	style.border_color = Color(0.4, 0.35, 0.3)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	_tooltip.add_theme_stylebox_override("panel", style)
	
	_tooltip_label = RichTextLabel.new()
	_tooltip_label.bbcode_enabled = true
	_tooltip_label.fit_content = true
	_tooltip_label.custom_minimum_size = Vector2(200, 0)
	_tooltip_label.add_theme_color_override("default_color", Color(0.9, 0.9, 0.9))
	_tooltip.add_child(_tooltip_label)
	
	_tooltip_timer = Timer.new()
	_tooltip_timer.wait_time = 0.3
	_tooltip_timer.one_shot = true
	_tooltip_timer.timeout.connect(_on_tooltip_timer)
	add_child(_tooltip_timer)

## ============================================================================
## PUBLIC API
## ============================================================================

static func show_item(item_data: Dictionary, position: Vector2 = Vector2.ZERO) -> void:
	if instance:
		instance._show_tooltip_internal(item_data, Type.ITEM, position)

static func show_skill(skill_data: Dictionary, position: Vector2 = Vector2.ZERO) -> void:
	if instance:
		instance._show_tooltip_internal(skill_data, Type.SKILL, position)

static func show_entity(entity_data: Dictionary, position: Vector2 = Vector2.ZERO) -> void:
	if instance:
		instance._show_tooltip_internal(entity_data, Type.ENTITY, position)

static func show_status(status_data: Dictionary, position: Vector2 = Vector2.ZERO) -> void:
	if instance:
		instance._show_tooltip_internal(status_data, Type.STATUS, position)

static func show_custom(title: String, description: String, position: Vector2 = Vector2.ZERO) -> void:
	if instance:
		var data := {"title": title, "description": description}
		instance._show_tooltip_internal(data, Type.NONE, position)

static func hide_tooltip() -> void:
	if instance:
		instance._hide_tooltip_internal()

## ============================================================================
## INTERNAL METHODS
## ============================================================================

func _show_tooltip_internal(data: Dictionary, tooltip_type: int, position: Vector2) -> void:
	_current_data = data
	_tooltip_type = _tooltip_type_for(tooltip_type)
	
	# Reset timer to delay tooltip appearance
	_tooltip_timer.stop()
	_tooltip_timer.start()
	
	# Build content
	_tooltip_label.clear()
	_build_tooltip_content(data, tooltip_type)
	
	# Position
	if position != Vector2.ZERO:
		_tooltip.global_position = position + _position_offset
	else:
		# Show near mouse
		var mouse_pos := get_viewport().get_mouse_position()
		_tooltip.global_position = mouse_pos + _position_offset
	
	# Keep on screen
	_keep_on_screen()
	
	_tooltip.show()

func _on_tooltip_timer() -> void:
	pass  # Tooltip already shown

func _hide_tooltip_internal() -> void:
	_tooltip_timer.stop()
	
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	
	_tooltip.hide()
	_current_data = {}
	_tooltip_type = ""

func _keep_on_screen() -> void:
	var viewport_size := get_viewport_rect().size
	var tooltip_size := _tooltip.get_minimum_size()
	
	if _tooltip.global_position.x + tooltip_size.x > viewport_size.x:
		_tooltip.global_position.x = viewport_size.x - tooltip_size.x - 10
	if _tooltip.global_position.y + tooltip_size.y > viewport_size.y:
		_tooltip.global_position.y = viewport_size.y - tooltip_size.y - 10
	if _tooltip.global_position.x < 0:
		_tooltip.global_position.x = 10
	if _tooltip.global_position.y < 0:
		_tooltip.global_position.y = 10

func _tooltip_type_for(t: int) -> String:
	match t:
		Type.ITEM: return "item"
		Type.SKILL: return "skill"
		Type.ENTITY: return "entity"
		Type.STATUS: return "status"
		Type.QUEST: return "quest"
		_: return ""

func _build_tooltip_content(data: Dictionary, tooltip_type: int) -> void:
	var title: String = data.get("title", data.get("name", "Unknown"))
	var description: String = data.get("description", data.get("desc", ""))
	
	# Header
	_tooltip_label.append_text("[b]%s[/b]\n" % title)
	
	# Type-specific content
	match tooltip_type:
		Type.ITEM:
			_build_item_content(data)
		Type.SKILL:
			_build_skill_content(data)
		Type.ENTITY:
			_build_entity_content(data)
		Type.STATUS:
			_build_status_content(data)
	
	# Generic description
	if description != "":
		_tooltip_label.append_text("\n%s" % description)

func _build_item_content(data: Dictionary) -> void:
	var rarity: String = data.get("rarity", "common")
	var rarity_color := _rarity_color(rarity)
	
	_tooltip_label.append_text("[color=%s][%s][/color]\n" % [_color_to_hex(rarity_color), rarity.to_upper()])
	
	# Stats
	var stats: Dictionary = data.get("stats", {})
	for stat_name in stats.keys():
		var value = stats[stat_name]
		_tooltip_label.append_text("+ %s: %s\n" % [stat_name, str(value)])
	
	# Item type
	var item_type: String = data.get("type", "")
	if item_type != "":
		_tooltip_label.append_text("Type: %s\n" % item_type)
	
	# Requirements
	var level_req: int = data.get("level_req", 0)
	if level_req > 0:
		_tooltip_label.append_text("[color=#ff6666]Requires Level %d[/color]\n" % level_req)

func _build_skill_content(data: Dictionary) -> void:
	var skill_type: String = data.get("type", "")
	if skill_type != "":
		_tooltip_label.append_text("[color=#888888]%s[/color]\n" % skill_type)
	
	var damage: int = data.get("damage", 0)
	if damage > 0:
		_tooltip_label.append_text("Damage: %d\n" % damage)
	
	var mana_cost: int = data.get("mana_cost", 0)
	if mana_cost > 0:
		_tooltip_label.append_text("Mana Cost: %d\n" % mana_cost)
	
	var cooldown: float = data.get("cooldown", 0)
	if cooldown > 0:
		_tooltip_label.append_text("Cooldown: %.1fs\n" % cooldown)

func _build_entity_content(data: Dictionary) -> void:
	var level: int = data.get("level", 1)
	var health: int = data.get("health", 0)
	var max_health: int = data.get("max_health", 0)
	var entity_type: String = data.get("entity_type", "")
	
	_tooltip_label.append_text("[color=#888888]Level %d %s[/color]\n" % [level, entity_type])
	
	if max_health > 0:
		var health_pct := int((float(health) / float(max_health)) * 100)
		_tooltip_label.append_text("Health: %d/%d (%d%%)\n" % [health, max_health, health_pct])

func _build_status_content(data: Dictionary) -> void:
	var duration: float = data.get("duration", 0)
	var stacks: int = data.get("stacks", 1)
	var is_debuff: bool = data.get("is_debuff", false)
	
	var status_color := "66ff66" if not is_debuff else "ff6666"
	_tooltip_label.append_text("[color=#%s]%s[/color]\n" % [status_color, data.get("type", "Status")])
	
	if duration > 0:
		_tooltip_label.append_text("Duration: %.1fs\n" % duration)
	if stacks > 1:
		_tooltip_label.append_text("Stacks: x%d\n" % stacks)

func _rarity_color(rarity: String) -> Color:
	match rarity.to_lower():
		"common": return Color(0.6, 0.6, 0.6)
		"uncommon": return Color(0.2, 0.9, 0.2)
		"rare": return Color(0.2, 0.4, 1.0)
		"epic": return Color(0.6, 0.2, 0.9)
		"legendary": return Color(1.0, 0.6, 0.1)
		_: return Color.WHITE

func _color_to_hex(c: Color) -> String:
	return "#%02x%02x%02x" % [int(c.r * 255), int(c.g * 255), int(c.b * 255)]

func _process(_delta: float) -> void:
	if _tooltip.visible and _tooltip_type == "item":
		# Keep tooltip near mouse for items
		var mouse_pos := get_viewport().get_mouse_position()
		_tooltip.global_position = mouse_pos + _position_offset
		_keep_on_screen()
