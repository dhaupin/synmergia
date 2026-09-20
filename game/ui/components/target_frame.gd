## TargetFrame - Target information display
## Shows HP, name, level, buffs/debuffs, cast bar, faction relation icon
extends Control
class_name TargetFrame
const UIStyles = preload("res://ui/components/ui_styles.gd")
const IconResolver = preload("res://core/utils/icon_resolver.gd")
const ActionMenu = preload("res://ui/components/action_menu.gd")
const Entity = preload("res://core/entities/entity.gd")


## Components
var _name_label: Label
var _level_label: Label
var _hp_bar: ProgressBar
var _mp_bar: ProgressBar
var _buff_container: HBoxContainer
var _debuff_container: HBoxContainer
var _class_label: Label
var _guild_label: Label
var _class_icon: TextureRect
var _faction_icon: TextureRect
var _cast_bar: ProgressBar
var _cast_label: Label
var _cast_container: Control
var _interruptible_indicator: TextureRect

## Target data
var _target_id: String = ""
var _target_schema_id: String = "enemy"
var _current_hp: int = 100
var _max_hp: int = 100
var _current_mp: int = 50
var _max_mp: int = 50
var _current_cast: float = 0.0
var _max_cast: float = 0.0
var _cast_skill_name: String = ""
var _target_effects: Dictionary = {}
var _is_interruptible: bool = false

func _ready() -> void:
	_setup_ui()
	_setup_accessibility()
	_connect_signals()
	hide()

func _setup_accessibility() -> void:
	focus_mode = Control.FOCUS_ALL
func update_accessibility_settings(high_contrast: bool, text_scale: float, reduce_motion: bool) -> void:
	# Update focus styles for progress bars
	for bar in [_hp_bar, _mp_bar, _cast_bar]:
		if bar and is_instance_valid(bar):
			bar.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
	
	# Update buff/debuff containers
	for container in [_buff_container, _debuff_container]:
		if container:
			for child in container.get_children():
				if child is PanelContainer:
					child.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
					var style: StyleBoxFlat = child.get_theme_stylebox("panel")
					if style:
						if high_contrast:
							style.bg_color = UIStyles.HIGH_CONTRAST_COLORS.background
							style.border_color = UIStyles.HIGH_CONTRAST_COLORS.border
						else:
							style.bg_color = UIStyles.COLORS.background_dark
							style.border_color = UIStyles.COLORS.border
	
	# Update text sizes
	var scale = UIStyles.get_text_scale()
	for label in [_name_label, _level_label, _class_label, _guild_label, _cast_label]:
		if label and is_instance_valid(label):
			var current_size: int = label.get_theme_font_size("font_size")
			if current_size > 0:
				label.add_theme_font_size_override("font_size", int(current_size * scale))

func _setup_ui() -> void:
	name = "TargetFrame"
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	offset_left = -200
	offset_top = 60
	offset_right = 200
	offset_bottom = 260

	# Main container
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(vbox)

	# Name and level row
	var name_row := HBoxContainer.new()
	vbox.add_child(name_row)

	# Faction relation icon
	_faction_icon = TextureRect.new()
	_faction_icon.name = "FactionIcon"
	_faction_icon.custom_minimum_size = Vector2(22, 22)
	_faction_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_faction_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	name_row.add_child(_faction_icon)

	# Class icon
	_class_icon = TextureRect.new()
	_class_icon.name = "ClassIcon"
	_class_icon.custom_minimum_size = Vector2(22, 22)
	_class_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_class_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_class_icon.visible = false
	name_row.add_child(_class_icon)

	_name_label = Label.new()
	_name_label.text = "No Target"
	_name_label.add_theme_font_size_override("font_size", 16)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_name_label)

	_level_label = Label.new()
	_level_label.text = ""
	_level_label.add_theme_font_size_override("font_size", 14)
	_level_label.add_theme_color_override("font_color", UIStyles.COLORS.warning)
	name_row.add_child(_level_label)

	# Class and guild
	var info_row := HBoxContainer.new()
	vbox.add_child(info_row)

	_class_label = Label.new()
	_class_label.text = ""
	_class_label.add_theme_font_size_override("font_size", 10)
	_class_label.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	info_row.add_child(_class_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_row.add_child(spacer)

	_guild_label = Label.new()
	_guild_label.text = ""
	_guild_label.add_theme_font_size_override("font_size", 10)
	_guild_label.add_theme_color_override("font_color", UIStyles.COLORS.info)
	info_row.add_child(_guild_label)

	# Health bar
	_hp_bar = ProgressBar.new()
	_hp_bar.name = "HPBar"
	_hp_bar.min_value = 0
	_hp_bar.max_value = 100
	_hp_bar.value = 100
	_hp_bar.custom_minimum_size.y = 20
	_hp_bar.show_percentage = false
	vbox.add_child(_hp_bar)

	# Mana bar (smaller)
	_mp_bar = ProgressBar.new()
	_mp_bar.name = "MPBar"
	_mp_bar.min_value = 0
	_mp_bar.max_value = 100
	_mp_bar.value = 50
	_mp_bar.custom_minimum_size.y = 12
	_mp_bar.show_percentage = false
	vbox.add_child(_mp_bar)

	# HP/MP text
	var hp_row := HBoxContainer.new()
	vbox.add_child(hp_row)

	var hp_label := Label.new()
	hp_label.name = "HPLabel"
	hp_label.add_theme_font_size_override("font_size", 11)
	hp_label.add_theme_color_override("font_color", UIStyles.COLORS.error)
	hp_row.add_child(hp_label)

	var mp_label := Label.new()
	mp_label.name = "MPLabel"
	mp_label.add_theme_font_size_override("font_size", 10)
	mp_label.add_theme_color_override("font_color", UIStyles.COLORS.info)
	hp_row.add_child(mp_label)

	# Cast bar (hidden by default)
	_cast_container = Control.new()
	_cast_container.name = "CastContainer"
	_cast_container.visible = false
	vbox.add_child(_cast_container)

	var cast_vbox := VBoxContainer.new()
	_cast_container.add_child(cast_vbox)

	var cast_header := HBoxContainer.new()
	cast_vbox.add_child(cast_header)

	_cast_label = Label.new()
	_cast_label.name = "CastLabel"
	_cast_label.text = ""
	_cast_label.add_theme_font_size_override("font_size", 10)
	_cast_label.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	cast_header.add_child(_cast_label)

	# Interruptible indicator
	_interruptible_indicator = TextureRect.new()
	_interruptible_indicator.name = "InterruptibleIndicator"
	_interruptible_indicator.custom_minimum_size = Vector2(16, 16)
	_interruptible_indicator.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_interruptible_indicator.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_interruptible_indicator.visible = false
	cast_header.add_child(_interruptible_indicator)

	_cast_bar = ProgressBar.new()
	_cast_bar.name = "CastBar"
	_cast_bar.min_value = 0
	_cast_bar.max_value = 100
	_cast_bar.value = 0
	_cast_bar.custom_minimum_size.y = 14
	_cast_bar.show_percentage = false
	cast_vbox.add_child(_cast_bar)

	# Style cast bar
	var cast_style := StyleBoxFlat.new()
	cast_style.bg_color = UIStyles.COLORS.background_dark
	cast_style.border_color = UIStyles.COLORS.border
	cast_style.corner_radius_top_left = 4
	cast_style.corner_radius_top_right = 4
	cast_style.corner_radius_bottom_left = 4
	cast_style.corner_radius_bottom_right = 4
	_cast_bar.add_theme_stylebox_override("background", cast_style)

	var cast_fill := StyleBoxFlat.new()
	cast_fill.bg_color = UIStyles.COLORS.accent_gold
	cast_fill.corner_radius_top_left = 4
	cast_fill.corner_radius_top_right = 4
	cast_fill.corner_radius_bottom_left = 4
	cast_fill.corner_radius_bottom_right = 4
	_cast_bar.add_theme_stylebox_override("fill", cast_fill)

	# Buffs row
	var buffs_row := HBoxContainer.new()
	vbox.add_child(buffs_row)

	var buffs_label := Label.new()
	buffs_label.text = "Buffs:"
	buffs_label.add_theme_font_size_override("font_size", 10)
	buffs_row.add_child(buffs_label)

	_buff_container = HBoxContainer.new()
	_buff_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buffs_row.add_child(_buff_container)

	# Debuffs row
	var debuffs_row := HBoxContainer.new()
	vbox.add_child(debuffs_row)

	var debuffs_label := Label.new()
	debuffs_label.text = "Debuffs:"
	debuffs_label.add_theme_font_size_override("font_size", 10)
	debuffs_label.add_theme_color_override("font_color", UIStyles.COLORS.warning)
	debuffs_row.add_child(debuffs_label)

	_debuff_container = HBoxContainer.new()
	_debuff_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	debuffs_row.add_child(_debuff_container)

	# Mouse input
	mouse_filter = Control.MOUSE_FILTER_PASS
	add_theme_stylebox_override("focus", UIStyles.create_focus_style())

func _connect_signals() -> void:
	if TargetingManager:
		TargetingManager.target_acquired.connect(_on_target_acquired)
		TargetingManager.target_cleared.connect(_on_target_cleared)
		TargetingManager.target_updated.connect(_on_target_updated)
	if EntityService:
		EntityService.entity_effect_added.connect(_on_effect_added)
		EntityService.entity_effect_removed.connect(_on_effect_removed)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# Left click - re-target with the entity's schema type
			if _target_id != "" and TargetingManager:
				TargetingManager.set_target(_target_id, _target_schema_id)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			# Right click - show action menu
			if _target_id != "" and ActionMenu:
				var action_menu: ActionMenu = ActionMenu.new()
				add_child(action_menu)
				var target_data: Dictionary = _target_effects.get("target_data", {})
				var target_type: int = target_data.get("entity_type", Entity.EntityType.ENEMY)
				action_menu.show_menu(get_global_mouse_position(), _target_id, target_type)

func set_target(target) -> void:
	if target == null:
		clear_target()
		return
	
	var schema_id: String = "enemy"
	if target and "entity_type" in target:
		match target.entity_type:
			Entity.EntityType.PLAYER:
				schema_id = "player"
			Entity.EntityType.NPC:
				schema_id = "npc"
	_target_schema_id = schema_id

	_target_id = target.entity_id if target and "entity_id" in target else ""
	if _target_id.is_empty():
		hide()
		return

	show()
	_target_effects.clear()
	_refresh_effects()

func _on_target_acquired(target) -> void:
	set_target(target)

func _on_target_updated(target) -> void:
	if target == null or _target_id != (target.entity_id if target and "entity_id" in target else ""):
		return
	_update_display(target)

func _on_effect_added(entity_id: String, effect_data: Dictionary) -> void:
	if entity_id != _target_id:
		return
	_target_effects[effect_data.get("id", "")] = effect_data
	_refresh_effects()

func _on_effect_removed(entity_id: String, effect_id: String) -> void:
	if entity_id != _target_id:
		return
	_target_effects.erase(effect_id)
	_refresh_effects()

func _refresh_effects() -> void:
	_clear_effects(_buff_container)
	_clear_effects(_debuff_container)
	
	for effect_id in _target_effects:
		var effect: Dictionary = _target_effects[effect_id]
		var is_debuff: bool = effect.get("is_debuff", false)
		var container := _debuff_container if is_debuff else _buff_container
		_add_effect_icon(container, effect)

func _clear_effects(container: HBoxContainer) -> void:
	for child in container.get_children():
		child.queue_free()

func _add_effect_icon(container: HBoxContainer, effect: Dictionary) -> void:
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(24, 24)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = IconResolver.get_effect_icon_from_dict(effect)
	icon.tooltip_text = _build_effect_tooltip(effect)
	icon.mouse_filter = Control.MOUSE_FILTER_PASS
	container.add_child(icon)
	
	# Timer label
	var timer := Label.new()
	timer.custom_minimum_size = Vector2(24, 12)
	timer.add_theme_font_size_override("font_size", 8)
	timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	timer.add_theme_color_override("font_color", UIStyles.COLORS.text_primary)
	timer.name = "Timer"
	var remaining: float = effect.get("remaining", 0)
	timer.text = UIStyles.format_time_remaining(remaining)
	icon.add_child(timer)

func _build_effect_tooltip(effect: Dictionary) -> String:
	var name: String = effect.get("name", "Unknown Effect")
	var desc: String = effect.get("description", "")
	var remaining: float = effect.get("remaining", 0)
	var stack: int = effect.get("stack", 1)
	var text := "[b]%s[/b]\n" % name
	if stack > 1:
		text += "Stack: %d\n" % stack
	if remaining > 0:
		text += "Duration: %s\n" % UIStyles.format_time_remaining(remaining)
	if desc != "":
		text += "\n%s" % desc
	return text

func _on_target_cleared(_previous_target) -> void:
	_target_id = ""
	_target_effects.clear()
	hide()

func _update_display(data: Dictionary) -> void:
	_name_label.text = data.get("name", "Unknown")
	_apply_faction_color(data)

	var level: int = data.get("level", 1)
	var elite_type: String = data.get("elite_type", "")
	if elite_type == "BOSS":
		_level_label.text = "[Boss] %d" % level
		_level_label.add_theme_color_override("font_color", UIStyles.COLORS.error)
	elif elite_type == "ELITE":
		_level_label.text = "[Elite] %d" % level
		_level_label.add_theme_color_override("font_color", UIStyles.COLORS.warning)
	else:
		_level_label.text = "Lv.%d" % level
		_level_label.add_theme_color_override("font_color", UIStyles.COLORS.warning)

	# Class icon and label
	var char_class_name: String = data.get("class", "")
	var class_icon_path: String = data.get("class_icon", "")
	if char_class_name != "":
		_class_label.text = char_class_name
		if class_icon_path != "":
			_class_icon.texture = load(class_icon_path)
			_class_icon.visible = true
		else:
			# Try to resolve class icon from IconResolver
			var icon := IconResolver.get_icon_for_path("res://ui/textures/classes/%s.png" % char_class_name.to_lower())
			if icon:
				_class_icon.texture = icon
				_class_icon.visible = true
	else:
		_class_icon.visible = false
	
	_guild_label.text = data.get("guild", "")

	_current_hp = data.get("health", 100)
	_max_hp = data.get("max_health", 100)
	_current_mp = data.get("mana", 50)
	_max_mp = data.get("max_mana", 50)

	_update_bars()

	# Store target data for action menu
	_target_effects["target_data"] = data
func _update_bars() -> void:
	if _hp_bar:
		_hp_bar.max_value = _max_hp if _max_hp > 0 else 1
		_hp_bar.value = _current_hp

		# HP bar color based on percentage
		var hp_percent: float = 0.0
		if _max_hp > 0:
			hp_percent = float(_current_hp) / float(_max_hp)
		if hp_percent > 0.5:
			_hp_bar.add_theme_color_override("fill", UIStyles.COLORS.success)
		elif hp_percent > 0.25:
			_hp_bar.add_theme_color_override("fill", UIStyles.COLORS.warning)
		else:
			_hp_bar.add_theme_color_override("fill", UIStyles.COLORS.error)

		if _mp_bar:
			_mp_bar.max_value = _max_mp if _max_mp > 0 else 1
			_mp_bar.value = _current_mp

			# Update HP/MP labels
			var vbox: VBoxContainer = get_child(0)
			if vbox:
				var hp_row: HBoxContainer = vbox.get_child(5)
				if hp_row:
					var hp_label: Label = hp_row.get_child(0)
					var mp_label: Label = hp_row.get_child(1)
					if hp_label:
						hp_label.text = "HP: %d / %d" % [_current_hp, _max_hp]
						if mp_label:
							mp_label.text = "  MP: %d / %d" % [_current_mp, _max_mp]

func update_health(current: int, maximum: int) -> void:
	_current_hp = current
	_max_hp = maximum
	_update_bars()

func update_mana(current: int, maximum: int) -> void:
	_current_mp = current
	_max_mp = maximum
	_update_bars()

func clear_target() -> void:
	_target_id = ""
	hide()

func get_target_id() -> String:
	return _target_id


# == Faction coloring =====================================================

# Tint the name label based on the target's relation to the local player.
# hostile = red (player can attack), friendly = green, neutral = white.
# Falls back to the data's pre-baked color if relation is unknown.
func _apply_faction_color(data: Dictionary) -> void:
	if not _name_label:
		return
	var relation: String = str(data.get("relation", "")).to_lower()
	var color: Color
	match relation:
		"hostile", "enemy":
			color = UIStyles.COLORS.error
			_faction_icon.texture = IconResolver.get_faction_icon("hostile")
		"friendly", "ally":
			color = UIStyles.COLORS.success
			_faction_icon.texture = IconResolver.get_faction_icon("friendly")
		"neutral":
			color = UIStyles.COLORS.text_primary
			_faction_icon.texture = IconResolver.get_faction_icon("neutral")
		_:
			if data.has("color") and data["color"] is Color:
				color = data["color"]
			else:
				color = UIStyles.COLORS.text_primary
			_faction_icon.texture = null
	_name_label.add_theme_color_override("font_color", color)


## == Cast Bar =============================================================

func start_cast(skill_name: String, cast_time: float, interruptible: bool = true) -> void:
	_cast_skill_name = skill_name
	_max_cast = cast_time
	_current_cast = 0.0
	_is_interruptible = interruptible
	_cast_label.text = "Casting: %s" % skill_name
	_cast_container.visible = true
	_cast_bar.max_value = cast_time
	_cast_bar.value = 0
	
	# Update interruptible indicator
	if _interruptible_indicator:
		_interruptible_indicator.visible = interruptible
		if interruptible:
			_interruptible_indicator.texture = IconResolver.get_icon_for_path("res://ui/textures/icons/interruptible.png")
			_interruptible_indicator.add_theme_color_override("modulate", UIStyles.COLORS.warning)
		else:
			_interruptible_indicator.add_theme_color_override("modulate", UIStyles.COLORS.text_disabled)

func update_cast(delta: float) -> void:
	if not _cast_container.visible:
		return
	_current_cast += delta
	if _current_cast >= _max_cast:
		stop_cast()
		return
	_cast_bar.value = _current_cast
	_cast_bar.max_value = _max_cast

func stop_cast() -> void:
	_cast_container.visible = false
	_cast_skill_name = ""
	_current_cast = 0.0
	_max_cast = 0.0
	_is_interruptible = false
	if _interruptible_indicator:
		_interruptible_indicator.visible = false

func interrupt_cast() -> void:
	_cast_label.text = "Interrupted"
	_cast_bar.add_theme_color_override("fill", UIStyles.COLORS.error)
	await get_tree().create_timer(0.5).timeout
	stop_cast()
	_cast_bar.add_theme_color_override("fill", UIStyles.COLORS.accent_gold)


## == Effect Timer Updates =================================================

func _process(delta: float) -> void:
	if not visible:
		return
	
	# Update cast bar
	if _cast_container.visible:
		update_cast(delta)
	
	# Update effect timers
	_update_effect_timers(delta)

func _update_effect_timers(delta: float) -> void:
	for container in [_buff_container, _debuff_container]:
		for child in container.get_children():
			if child is TextureRect:
				var timer: Label = child.get_node_or_null("Timer")
				if timer:
					# Use tooltip text to find matching effect (name is in tooltip)
					var tooltip_name: String = str(child.tooltip_text).get_slice("[b]", 1).get_slice("[/b]", 0)
					for eid in _target_effects:
						var effect: Dictionary = _target_effects[eid]
						if effect.get("name", "") == tooltip_name:
							var remaining: float = effect.get("remaining", 0) - delta
							effect.remaining = remaining
							if remaining <= 0:
								_target_effects.erase(eid)
								_refresh_effects()
								break
							timer.text = UIStyles.format_time_remaining(remaining)
							break
