## BuffBar - Active effects display
## Shows buffs/debuffs with duration timers
extends Control
class_name BuffBar
const UIStyles = preload("res://ui/components/ui_styles.gd")
const IconResolver = preload("res://core/utils/icon_resolver.gd")


## Buff types
enum BuffType { BUFF, DEBUFF }

## Effect categories for filtering
enum EffectCategory {
	ALL = -1,
	MAGIC = 0,
	PHYSICAL = 1,
	POISON = 2,
	DISEASE = 3,
	CURSE = 4
}

## Max visible buffs/debuffs per row
const MAX_BUFFS: int = 16
const MAX_DEBUFFS: int = 16

var _buffs: Array = []
var _debuffs: Array = []
var _timer: Timer

## Filter state
var _show_only_player_cast: bool = false
var _filter_category: int = EffectCategory.ALL

## UI Components
var _buff_container: HBoxContainer
var _debuff_container: HBoxContainer
var _filter_bar: HBoxContainer

signal buff_added(buff_id: String)
signal buff_removed(buff_id: String)
signal filter_changed(category: int, player_only: bool)

func _ready() -> void:
	_setup_ui()
	_create_timer()
	_setup_accessibility()

func _setup_accessibility() -> void:
	focus_mode = Control.FOCUS_ALL
func update_accessibility_settings(high_contrast: bool, text_scale: float, reduce_motion: bool) -> void:
	# Update focus styles for filter buttons
	if _filter_bar:
		for child in _filter_bar.get_children():
			if child is Button:
				child.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
				var scale = UIStyles.get_text_scale()
				var current_size := child.get_theme_font_size("font_size")
				if current_size > 0:
					child.add_theme_font_size_override("font_size", int(current_size * scale))
	
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
				for label_name in ["Timer", "StackCount"]:
					var label: Label = child.get_node_or_null(label_name)
					if label:
						var current_size := label.get_theme_font_size("font_size")
						if current_size > 0:
							label.add_theme_font_size_override("font_size", int(current_size * scale))

func _setup_ui() -> void:
	name = "BuffBar"
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -380
	offset_top = 60
	offset_right = -20
	offset_bottom = 140

	# Main container
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(vbox)

	# Filter bar
	_filter_bar = HBoxContainer.new()
	_filter_bar.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(_filter_bar)

	# "Player Only" toggle
	var player_only_btn := Button.new()
	player_only_btn.name = "PlayerOnlyBtn"
	player_only_btn.text = "Mine"
	player_only_btn.toggle_mode = true
	player_only_btn.button_pressed = _show_only_player_cast
	player_only_btn.custom_minimum_size = Vector2(60, 20)
	player_only_btn.add_theme_font_size_override("font_size", 9)
	player_only_btn.tooltip_text = "Show only player-cast effects"
	player_only_btn.focus_mode = Control.FOCUS_ALL
	player_only_btn.
	player_only_btn.
	player_only_btn.add_theme_stylebox_override("focus", UIStyles.create_focus_style(4, false))
	player_only_btn.toggled.connect(_on_player_only_toggled)
	_filter_bar.add_child(player_only_btn)

	# Category filter dropdown
	var category_btn := Button.new()
	category_btn.name = "CategoryBtn"
	category_btn.text = "All"
	category_btn.custom_minimum_size = Vector2(80, 20)
	category_btn.add_theme_font_size_override("font_size", 9)
	category_btn.tooltip_text = "Filter by effect type"
	category_btn.focus_mode = Control.FOCUS_ALL
	category_btn.
	category_btn.
	category_btn.add_theme_stylebox_override("focus", UIStyles.create_focus_style(4, false))
	_filter_bar.add_child(category_btn)

	var category_menu := PopupMenu.new()
	category_menu.name = "CategoryMenu"
	category_menu.add_item("All Types", EffectCategory.ALL)
	category_menu.add_item("Magic", EffectCategory.MAGIC)
	category_menu.add_item("Physical", EffectCategory.PHYSICAL)
	category_menu.add_item("Poison", EffectCategory.POISON)
	category_menu.add_item("Disease", EffectCategory.DISEASE)
	category_menu.add_item("Curse", EffectCategory.CURSE)
	category_menu.id_pressed.connect(_on_category_selected)
	category_btn.pressed.connect(func(): category_menu.popup_())
	add_child(category_menu)

	# Buffs row (green border)
	var buffs_row := HBoxContainer.new()
	vbox.add_child(buffs_row)

	var buffs_label := Label.new()
	buffs_label.text = "Buffs:"
	buffs_label.add_theme_font_size_override("font_size", 10)
	buffs_label.add_theme_color_override("font_color", UIStyles.COLORS.success)
	buffs_row.add_child(buffs_label)

	_buff_container = HBoxContainer.new()
	_buff_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buffs_row.add_child(_buff_container)

	# Style buff container with green border
	var buff_container_style := StyleBoxFlat.new()
	buff_container_style.border_color = UIStyles.COLORS.success
	buff_container_style.border_width_left = 1
	buff_container_style.border_width_right = 1
	buff_container_style.border_width_top = 1
	buff_container_style.border_width_bottom = 1
	buff_container_style.corner_radius_top_left = 4
	buff_container_style.corner_radius_top_right = 4
	buff_container_style.corner_radius_bottom_left = 4
	buff_container_style.corner_radius_bottom_right = 4
	_buff_container.add_theme_stylebox_override("background", buff_container_style)

	# Debuffs row (red border)
	var debuffs_row := HBoxContainer.new()
	vbox.add_child(debuffs_row)

	var debuffs_label := Label.new()
	debuffs_label.text = "Debuffs:"
	debuffs_label.add_theme_font_size_override("font_size", 10)
	debuffs_label.add_theme_color_override("font_color", UIStyles.COLORS.error)
	debuffs_row.add_child(debuffs_label)

	_debuff_container = HBoxContainer.new()
	_debuff_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	debuffs_row.add_child(_debuff_container)

	# Style debuff container with red border
	var debuff_container_style := StyleBoxFlat.new()
	debuff_container_style.border_color = UIStyles.COLORS.error
	debuff_container_style.border_width_left = 1
	debuff_container_style.border_width_right = 1
	debuff_container_style.border_width_top = 1
	debuff_container_style.border_width_bottom = 1
	debuff_container_style.corner_radius_top_left = 4
	debuff_container_style.corner_radius_top_right = 4
	debuff_container_style.corner_radius_bottom_left = 4
	debuff_container_style.corner_radius_bottom_right = 4
	_debuff_container.add_theme_stylebox_override("background", debuff_container_style)

func _create_timer() -> void:
	_timer = Timer.new()
	_timer.wait_time = 0.5
	_timer.timeout.connect(_on_timer_tick)
	add_child(_timer)
	_timer.start()

func _on_timer_tick() -> void:
	_update_buffs()
	_update_debuffs()

func _on_player_only_toggled(pressed: bool) -> void:
	_show_only_player_cast = pressed
	_refresh_display()
	filter_changed.emit(_filter_category, _show_only_player_cast)

func _on_category_selected(id: int) -> void:
	_filter_category = id
	var category_btn: Button = _filter_bar.get_node("CategoryBtn")
	var names := ["All", "Magic", "Physical", "Poison", "Disease", "Curse"]
	if id >= 0 and id < names.size():
		category_btn.text = names[id]
	_refresh_display()
	filter_changed.emit(_filter_category, _show_only_player_cast)

func _should_show_effect(effect: Dictionary) -> bool:
	# Check player-only filter
	if _show_only_player_cast:
		var is_player_cast := effect.get("is_player_cast", false)
		if not is_player_cast:
			return false
	
	# Check category filter
	if _filter_category != EffectCategory.ALL:
		var effect_category := effect.get("category", EffectCategory.MAGIC)
		if effect_category != _filter_category:
			return false
	
	return true

func _refresh_display() -> void:
	_clear_effects(_buff_container)
	_clear_effects(_debuff_container)
	
	for buff in _buffs:
		if _should_show_effect(buff):
			_add_effect_icon(_buff_container, buff, false)
	
	for debuff in _debuffs:
		if _should_show_effect(debuff):
			_add_effect_icon(_debuff_container, debuff, true)

func add_buff(buff_id: String, icon: Texture2D, duration: float, stack_count: int = 1, is_debuff: bool = false, is_player_cast: bool = false, category: int = EffectCategory.MAGIC) -> void:
	var effect := {
	"id": buff_id,
	"icon": icon,
	"duration": duration,
	"remaining": duration,
	"stack": stack_count,
	"is_debuff": is_debuff,
	"is_player_cast": is_player_cast,
	"category": category,
	"is_new": true  # Flag for flash animation
	}

	if is_debuff:
		if _debuffs.size() < MAX_DEBUFFS:
			_debuffs.append(effect)
	else:
		if _buffs.size() < MAX_BUFFS:
			_buffs.append(effect)

	if _should_show_effect(effect):
		var container := _debuff_container if is_debuff else _buff_container
		_add_effect_icon(container, effect, is_debuff)

	buff_added.emit(buff_id)

func remove_buff(buff_id: String) -> void:
	var removed := false
	for i in range(_buffs.size()):
		if _buffs[i].id == buff_id:
			_buffs.remove_at(i)
			removed = true
			break
	if not removed:
		for j in range(_debuffs.size()):
			if _debuffs[j].id == buff_id:
				_debuffs.remove_at(j)
				removed = true
				break
	if removed:
		_refresh_display()
		buff_removed.emit(buff_id)

func update_buff_duration(buff_id: String, remaining: float) -> void:
	for buff in _buffs:
		if buff.id == buff_id:
			buff.remaining = remaining
			_update_icon_timer(buff, remaining)
			return
	for debuff in _debuffs:
		if debuff.id == buff_id:
			debuff.remaining = remaining
			_update_icon_timer(debuff, remaining)
			return

func _update_icon_timer(effect: Dictionary, remaining: float) -> void:
	# Find the icon in the container and update its timer
	var container := _debuff_container if effect.is_debuff else _buff_container
	for child in container.get_children():
		if child is TextureRect:
			var timer: Label = child.get_node_or_null("Timer")
			if timer:
				# Match by tooltip name
				var tooltip_name := child.tooltip_text.get_slice("[b]", 1).get_slice("[/b]", 0)
				if tooltip_name == effect.get("name", ""):
					timer.text = UIStyles.format_time_remaining(remaining)
					# Pulse if <5s remaining
					if remaining > 0 and remaining <= 5.0:
						_pulse_timer(timer)
					break

func _pulse_timer(timer: Label) -> void:
	if timer.has_meta("pulsing"):
		return
	# Respect reduce motion setting
	if UIStyles.is_reduce_motion_enabled():
		return
	timer.set_meta("pulsing", true)
	var tween := timer.create_tween()
	tween.set_loops()
	tween.tween_property(timer, "modulate:a", 0.3, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(timer, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _update_buffs() -> void:
	var to_remove := []
	for buff in _buffs:
		buff.remaining -= 0.5
		if buff.remaining <= 0:
			to_remove.append(buff.id)
		else:
			_update_icon_timer(buff, buff.remaining)
	for buff_id in to_remove:
		remove_buff(buff_id)

func _update_debuffs() -> void:
	var to_remove := []
	for debuff in _debuffs:
		debuff.remaining -= 0.5
		if debuff.remaining <= 0:
			to_remove.append(debuff.id)
		else:
			_update_icon_timer(debuff, debuff.remaining)
	for buff_id in to_remove:
		remove_buff(buff_id)

func _clear_effects(container: HBoxContainer) -> void:
	for child in container.get_children():
		child.queue_free()

func _add_effect_icon(container: HBoxContainer, effect: Dictionary, is_debuff: bool) -> void:
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(30, 30)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.focus_mode = Control.FOCUS_ALL
	icon.accessible_name = effect.get("name", "Unknown Effect")
	icon.accessible_description = _build_effect_tooltip(effect)
	
	# Use provided icon or resolve from effect data
	if effect.has("icon") and effect.icon:
		icon.texture = effect.icon
	else:
		icon.texture = IconResolver.get_effect_icon_from_dict(effect)
	
	icon.tooltip_text = _build_effect_tooltip(effect)
	icon.mouse_filter = Control.MOUSE_FILTER_PASS
	icon.add_theme_stylebox_override("focus", UIStyles.create_focus_style(4, false))
	container.add_child(icon)
	
	# Timer label
	var timer := Label.new()
	timer.custom_minimum_size = Vector2(30, 14)
	timer.add_theme_font_size_override("font_size", 9)
	timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	timer.add_theme_color_override("font_color", UIStyles.COLORS.text_primary)
	timer.name = "Timer"
	var remaining: float = effect.get("remaining", 0)
	timer.text = UIStyles.format_time_remaining(remaining)
	icon.add_child(timer)
	
	# Stack count label
	if effect.get("stack", 1) > 1:
		var stack_label := Label.new()
		stack_label.name = "StackLabel"
		stack_label.custom_minimum_size = Vector2(30, 14)
		stack_label.add_theme_font_size_override("font_size", 8)
		stack_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		stack_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		stack_label.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
		stack_label.text = "x%d" % effect.stack
		icon.add_child(stack_label)
	
	# Flash animation for new effects
	if effect.get("is_new", false):
		effect.is_new = false
		_flash_new_effect(icon)
	
	# Pulse if <5s remaining
	if remaining > 0 and remaining <= 5.0:
		_pulse_timer(timer)

func _flash_new_effect(icon: TextureRect) -> void:
	# Respect reduce motion setting
	if UIStyles.is_reduce_motion_enabled():
		return
	var tween := icon.create_tween()
	tween.tween_property(icon, "modulate", Color(1, 1, 0.5, 1), 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(icon, "modulate", Color(1, 1, 1, 1), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func _build_effect_tooltip(effect: Dictionary) -> String:
	var name := effect.get("name", "Unknown Effect")
	var desc := effect.get("description", "")
	var remaining := effect.get("remaining", 0)
	var stack := effect.get("stack", 1)
	var category := effect.get("category", 0)
	var category_names := ["Magic", "Physical", "Poison", "Disease", "Curse"]
	var cat_name := "Magic"
	if category >= 0 and category < category_names.size():
		cat_name = category_names[category]
	
	var text := "[b]%s[/b]\n" % name
	text += "Type: %s\n" % cat_name
	if stack > 1:
		text += "Stack: %d\n" % stack
	if remaining > 0:
		text += "Duration: %s\n" % UIStyles.format_time_remaining(remaining)
	if effect.get("is_player_cast", false):
		text += "Source: You\n"
	if desc != "":
		text += "\n%s" % desc
	return text

func get_buffs() -> Array:
	return _buffs

func get_debuffs() -> Array:
	return _debuffs

func has_buff(buff_id: String) -> bool:
	for buff in _buffs:
		if buff.id == buff_id:
			return true
	for debuff in _debuffs:
		if debuff.id == buff_id:
			return true
	return false

func set_filter_player_only(enabled: bool) -> void:
	_show_only_player_cast = enabled
	var btn: Button = _filter_bar.get_node("PlayerOnlyBtn")
	if btn:
		btn.button_pressed = enabled
	_refresh_display()

func set_filter_category(category: int) -> void:
	_filter_category = category
	var category_btn: Button = _filter_bar.get_node("CategoryBtn")
	if category_btn:
		var names := ["All", "Magic", "Physical", "Poison", "Disease", "Curse"]
		if category >= 0 and category < names.size():
			category_btn.text = names[category]
	_refresh_display()
