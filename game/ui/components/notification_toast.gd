## NotificationToast - Toast notification system
## Stacks from top-right, slide animations, 6 types, progress bar, click actions, Notification Center
extends Control
class_name NotificationToast
const UIStyles = preload("res://ui/components/ui_styles.gd")

## Toast types with colors
enum ToastType {
	INFO = 0,        # Blue
	WARNING = 1,     # Yellow
	ERROR = 2,       # Red
	SUCCESS = 3,     # Green
	LOOT = 4,        # Gold
	ACHIEVEMENT = 5  # Purple
}

## Bare enum members do not resolve inside const-dict literals (GDScript
## const-context scoping); keys must be ToastType-qualified or the whole
## script fails to parse and the toast face silently dies.
const TOAST_COLORS: Dictionary = {
	ToastType.INFO: Color(0.3, 0.6, 1.0),
	ToastType.WARNING: Color(1.0, 0.8, 0.2),
	ToastType.ERROR: Color(1.0, 0.3, 0.3),
	ToastType.SUCCESS: Color(0.2, 0.8, 0.3),
	ToastType.LOOT: Color(1.0, 0.85, 0.1),
	ToastType.ACHIEVEMENT: Color(0.8, 0.3, 1.0)
}

const TOAST_ICONS: Dictionary = {
	ToastType.INFO: "[i]",
	ToastType.WARNING: "[!]",
	ToastType.ERROR: "[X]",
	ToastType.SUCCESS: "[+]",
	ToastType.LOOT: "[*]",
	ToastType.ACHIEVEMENT: "[A]"
}

## Configuration
const MAX_VISIBLE_TOASTS: int = 5
const DEFAULT_DURATION: float = 5.0
const SLIDE_DURATION: float = 0.3
const FADE_DURATION: float = 0.25

## Components
var _toast_stack: VBoxContainer
var _notification_center: Control
var _center_visible: bool = false

## State
var _active_toasts: Array[Control] = []
var _toast_queue: Array[Dictionary] = []
var _notification_history: Array[Dictionary] = []
var _max_history: int = 100

## Signals
signal toast_clicked(toast_data: Dictionary)
signal notification_center_toggled(visible: bool)
signal history_cleared()

func _ready() -> void:
	_setup_ui()
	_connect_input()
	_setup_accessibility()

func _setup_accessibility() -> void:
	focus_mode = Control.FOCUS_ALL
	# Apply default accessibility settings via the settings updater.
	update_accessibility_settings(false, 1.0, false)
func update_accessibility_settings(high_contrast: bool, text_scale: float, reduce_motion: bool) -> void:
	# Update toast stack children
	if _toast_stack:
		for child in _toast_stack.get_children():
			if child is PanelContainer:
				child.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
				var style: StyleBoxFlat = child.get_theme_stylebox("panel")
				if style:
					if high_contrast:
						style.bg_color = UIStyles.HIGH_CONTRAST_COLORS.background
						style.border_color = UIStyles.HIGH_CONTRAST_COLORS.border
					else:
						style.bg_color = UIStyles.TEXT_COLORS.toast_bg
						style.border_color = UIStyles.COLORS.border

			# Update text sizes
			var scale = UIStyles.get_text_scale()
			for label_name in ["Message", "ProgressBar"]:
				var label: Label = child.get_node_or_null(label_name)
				if label:
					var current_size: int = label.get_theme_font_size("font_size")
					if current_size > 0:
						label.add_theme_font_size_override("font_size", int(current_size * scale))

	# Update notification center
	if _notification_center and is_instance_valid(_notification_center):
		_notification_center.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
		for child in _notification_center.get_children():
			if child is PanelContainer:
				child.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
				var style: StyleBoxFlat = child.get_theme_stylebox("panel")
				if style:
					if high_contrast:
						style.bg_color = UIStyles.HIGH_CONTRAST_COLORS.background
						style.border_color = UIStyles.HIGH_CONTRAST_COLORS.border
			elif child is Button:
				child.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
				var scale = UIStyles.get_text_scale()
				var current_size: int = child.get_theme_font_size("font_size")
				if current_size > 0:
					child.add_theme_font_size_override("font_size", int(current_size * scale))
			elif child is Label:
				var scale = UIStyles.get_text_scale()
				var current_size: int = child.get_theme_font_size("font_size")
				if current_size > 0:
					child.add_theme_font_size_override("font_size", int(current_size * scale))

func _setup_ui() -> void:
	name = "NotificationToast"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Toast stack (top-right)
	_toast_stack = VBoxContainer.new()
	_toast_stack.name = "ToastStack"
	_toast_stack.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_toast_stack.anchor_left = 1.0
	_toast_stack.anchor_right = 1.0
	_toast_stack.offset_left = -400
	_toast_stack.offset_top = 80
	_toast_stack.offset_right = -20
	_toast_stack.add_theme_constant_override("separation", 8)
	_toast_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast_stack)

	# Notification Center panel (hidden by default)
	_notification_center = _create_notification_center()
	_notification_center.visible = false
	add_child(_notification_center)

func _create_notification_center() -> Control:
	var panel := PanelContainer.new()
	panel.name = "NotificationCenter"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -250
	panel.offset_top = -200
	panel.offset_right = 250
	panel.offset_bottom = 200
	panel.focus_mode = Control.FOCUS_ALL
	var style := StyleBoxFlat.new()
	style.bg_color = UIStyles.COLORS.background_dark
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
	panel.add_theme_stylebox_override("focus", UIStyles.create_focus_style())

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	# Header
	var header := HBoxContainer.new()
	header.custom_minimum_size.y = 40
	vbox.add_child(header)

	var title := Label.new()
	title.text = "Notification Center"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "[X]"
	close_btn.custom_minimum_size = Vector2(30, 30)
	close_btn.focus_mode = Control.FOCUS_ALL
	close_btn.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
	close_btn.pressed.connect(_close_notification_center)
	header.add_child(close_btn)

	var clear_all_btn := Button.new()
	clear_all_btn.text = "Clear All"
	clear_all_btn.custom_minimum_size = Vector2(80, 30)
	clear_all_btn.focus_mode = Control.FOCUS_ALL
	clear_all_btn.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
	close_btn.pressed.connect(_clear_all_notifications)
	header.add_child(clear_all_btn)

	# History list
	var scroll := preload("res://ui/components/drag_scroll.gd").new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var history_container := VBoxContainer.new()
	history_container.name = "HistoryContainer"
	history_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history_container.add_theme_constant_override("separation", 4)
	scroll.add_child(history_container)

	return panel

func _connect_input() -> void:
	# N key toggles notification center (InputMap law: register the
	# action once; Input has no static map_action). The _input() handler
	# below still reads the raw keycode, so the action is only here for
	# other UI consumers to query.
	if not InputMap.has_action("toggle_notifications"):
		InputMap.add_action("toggle_notifications")
		var ev := InputEventKey.new()
		ev.keycode = KEY_N
		InputMap.action_add_event("toggle_notifications", ev)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_N and not event.ctrl_pressed and not event.shift_pressed and not event.alt_pressed:
			_toggle_notification_center()

func _toggle_notification_center() -> void:
	_center_visible = not _center_visible
	_notification_center.visible = _center_visible
	if _center_visible:
		_refresh_history_list()
		_notification_center.grab_focus()
	notification_center_toggled.emit(_center_visible)

func _close_notification_center() -> void:
	_center_visible = false
	_notification_center.visible = false
	notification_center_toggled.emit(false)

func _clear_all_notifications() -> void:
	_notification_history.clear()
	_refresh_history_list()
	history_cleared.emit()

func _refresh_history_list() -> void:
	var container: VBoxContainer = _notification_center.get_node("VBoxContainer/ScrollContainer/HistoryContainer")
	if not container:
		return

	for child in container.get_children():
		child.queue_free()

	for i in range(_notification_history.size() - 1, -1, -1):
		var entry = _notification_history[i]
		var item = _create_history_item(entry, i)
		container.add_child(item)

func _create_history_item(entry: Dictionary, index: int) -> Control:
	var item := PanelContainer.new()
	item.custom_minimum_size.y = 60
	item.mouse_filter = Control.MOUSE_FILTER_PASS
	item.focus_mode = Control.FOCUS_ALL
	item.add_theme_stylebox_override("focus", UIStyles.create_focus_style())

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.8)
	style.border_color = UIStyles.COLORS.border
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	item.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 8)
	item.add_child(hbox)

	var type_color: Color = TOAST_COLORS.get(entry.get("type", 0), UIStyles.COLORS.text_primary)
	var icon_text: String = TOAST_ICONS.get(entry.get("type", 0), "[*]")

	var icon := Label.new()
	icon.text = icon_text
	icon.custom_minimum_size = Vector2(30, 30)
	icon.add_theme_font_size_override("font_size", 18)
	icon.add_theme_color_override("font_color", type_color)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(icon)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.text = entry.get("title", "Notification")
	title_lbl.add_theme_font_size_override("font_size", 12)
	title_lbl.add_theme_color_override("font_color", UIStyles.COLORS.text_primary)
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(title_lbl)

	var msg_lbl := Label.new()
	msg_lbl.text = entry.get("message", "")
	msg_lbl.add_theme_font_size_override("font_size", 10)
	msg_lbl.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	msg_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(msg_lbl)

	var time_lbl := Label.new()
	var timestamp: int = entry.get("timestamp", 0)
	if timestamp > 0:
		var elapsed = Time.get_ticks_msec() - timestamp
		var seconds = elapsed / 1000
		if seconds < 60:
			time_lbl.text = "%ds ago" % int(seconds)
		elif seconds < 3600:
			time_lbl.text = "%dm ago" % int(seconds / 60)
		else:
			time_lbl.text = "%dh ago" % int(seconds / 3600)
	else:
		time_lbl.text = ""
	time_lbl.add_theme_font_size_override("font_size", 8)
	time_lbl.add_theme_color_override("font_color", UIStyles.COLORS.text_disabled)
	hbox.add_child(time_lbl)

	var read_btn := Button.new()
	read_btn.text = "Read" if entry.get("read", false) else "Mark Read"
	read_btn.custom_minimum_size = Vector2(70, 24)
	read_btn.disabled = entry.get("read", false)
	read_btn.focus_mode = Control.FOCUS_ALL
	read_btn.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
	read_btn.pressed.connect(func(): _mark_history_read(index))
	hbox.add_child(read_btn)

	var delete_btn := Button.new()
	delete_btn.text = "[X]"
	delete_btn.custom_minimum_size = Vector2(24, 24)
	delete_btn.add_theme_color_override("font_color", UIStyles.COLORS.error)
	delete_btn.focus_mode = Control.FOCUS_ALL
	delete_btn.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
	delete_btn.pressed.connect(func(): _remove_history_item(index))
	hbox.add_child(delete_btn)

	item.gui_input.connect(func(e): _on_history_item_click(e, entry))
	return item

func _on_history_item_click(event: InputEvent, entry: Dictionary) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if entry.has("action") and entry.action != "":
			toast_clicked.emit(entry)

func _mark_history_read(index: int) -> void:
	var actual_index = _notification_history.size() - 1 - index
	if actual_index >= 0 and actual_index < _notification_history.size():
		_notification_history[actual_index].read = true
		_refresh_history_list()

func _remove_history_item(index: int) -> void:
	var actual_index = _notification_history.size() - 1 - index
	if actual_index >= 0 and actual_index < _notification_history.size():
		_notification_history.remove_at(actual_index)
		_refresh_history_list()

## Public API

func show_toast(message: String, toast_type: int = ToastType.INFO, title: String = "", duration: float = DEFAULT_DURATION, action: String = "", action_data: Dictionary = {}) -> void:
	var toast_data := {
		"message": message,
		"type": toast_type,
		"title": title,
		"duration": duration,
		"action": action,
		"action_data": action_data,
		"timestamp": Time.get_ticks_msec(),
		"read": false
	}

	# Add to history
	_notification_history.append(toast_data.duplicate())
	while _notification_history.size() > _max_history:
		_notification_history.pop_front()

	# If at max visible, queue it
	if _active_toasts.size() >= MAX_VISIBLE_TOASTS:
		_toast_queue.append(toast_data)
		return

	_create_and_show_toast(toast_data)

func _create_and_show_toast(data: Dictionary) -> void:
	var toast_type: int = data.get("type", ToastType.INFO)
	var type_color: Color = TOAST_COLORS.get(toast_type, UIStyles.COLORS.info)
	var icon_text: String = TOAST_ICONS.get(toast_type, "[*]")

	var panel := PanelContainer.new()
	panel.name = "Toast_%d" % Time.get_ticks_msec()
	panel.modulate = Color(1, 1, 1, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.focus_mode = Control.FOCUS_ALL
	panel.set_meta("toast_data", data)

	var style := StyleBoxFlat.new()
	style.bg_color = UIStyles.TEXT_COLORS.toast_bg
	style.border_color = type_color
	style.border_width_left = 3
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	panel.add_theme_stylebox_override("focus", UIStyles.create_focus_style())

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	panel.add_child(hbox)

	# Icon
	var icon := Label.new()
	icon.text = icon_text
	icon.custom_minimum_size = Vector2(24, 24)
	icon.add_theme_font_size_override("font_size", 18)
	icon.add_theme_color_override("font_color", type_color)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(icon)

	# Content
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(vbox)

	var title_text: String = data.get("title", "")
	if title_text != "":
		var title_lbl := Label.new()
		title_lbl.text = title_text
		title_lbl.add_theme_font_size_override("font_size", 12)
		title_lbl.add_theme_color_override("font_color", UIStyles.COLORS.text_primary)
		title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(title_lbl)

	var msg_lbl := Label.new()
	msg_lbl.text = data.get("message", "")
	msg_lbl.add_theme_font_size_override("font_size", 11)
	msg_lbl.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	msg_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg_lbl.custom_minimum_size = Vector2(280, 0)
	vbox.add_child(msg_lbl)

	# Progress bar
	var progress := ProgressBar.new()
	progress.name = "ProgressBar"
	progress.min_value = 0
	progress.max_value = 100
	progress.value = 100
	progress.custom_minimum_size = Vector2(0, 4)
	progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var progress_style = StyleBoxFlat.new()
	progress_style.bg_color = Color(0, 0, 0, 0.3)
	progress_style.corner_radius_top_left = 2
	progress_style.corner_radius_top_right = 2
	progress_style.corner_radius_bottom_left = 2
	progress_style.corner_radius_bottom_right = 2
	progress.add_theme_stylebox_override("background", progress_style)

	var fill_style = StyleBoxFlat.new()
	fill_style.bg_color = type_color
	fill_style.corner_radius_top_left = 2
	fill_style.corner_radius_top_right = 2
	fill_style.corner_radius_bottom_left = 2
	fill_style.corner_radius_bottom_right = 2
	progress.add_theme_stylebox_override("fill", fill_style)

	vbox.add_child(progress)

	_toast_stack.add_child(panel)
	_active_toasts.append(panel)

	# Get animation durations respecting reduce motion
	var slide_dur = UIStyles.get_animation_duration(SLIDE_DURATION)
	var fade_dur = UIStyles.get_animation_duration(FADE_DURATION)

	# Slide in from right
	var start_pos = panel.position + Vector2(420, 0)
	panel.position = start_pos

	var tween: Tween = UIStyles.create_accessible_tween(panel, slide_dur)
	tween.parallel().tween_property(panel, "modulate:a", 1.0, fade_dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Progress bar animation
	var dur = data.get("duration", DEFAULT_DURATION)
	var progress_tween = progress.create_tween()
	progress_tween.tween_property(progress, "value", 0, dur).set_trans(Tween.TRANS_LINEAR)
	# THE WASM-TIMESTEP LAW (web round 18, "stuck 97% bars"): the phone's
	# wasm engine runs frames at 2-4/s, and the tween + dismiss pair
	# only advance inside process frames -- four stacked entry toasts
	# sat at ~97% visually while their cycle stretched over minutes of
	# wall time. A wall-clock TTL reader is bolted onto the bar so the
	# display always matches the actual lifetime regardless of frame
	# rate (the dismiss tween's own interval stays the authority).
	progress.set_meta("born_ms", Time.get_ticks_msec())
	progress.set_meta("dur_ms", int(dur * 1000.0))
	var ttl_reader := Timer.new()
	ttl_reader.name = "TtlReader"
	ttl_reader.wait_time = 0.25
	ttl_reader.timeout.connect(func():
		if not is_instance_valid(progress):
			return
		var born := int(progress.get_meta("born_ms", 0))
		var ttl_ms := int(progress.get_meta("dur_ms", 0))
		if ttl_ms <= 0:
			return
		var remaining := 1.0 - clampf(float(Time.get_ticks_msec() - born) / float(ttl_ms), 0.0, 1.0)
		progress.value = remaining * 100.0
	)
	progress.add_child(ttl_reader)
	ttl_reader.start()

	# Auto-dismiss
	var dismiss_tween: Tween = UIStyles.create_accessible_tween(panel, slide_dur)
	dismiss_tween.tween_interval(dur)
	dismiss_tween.tween_callback(func(): _dismiss_toast(panel))

	# Click handler
	panel.gui_input.connect(func(e): _on_toast_click(e, panel))

func _on_toast_click(event: InputEvent, panel: Control) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var data: Dictionary = panel.get_meta("toast_data", {})
		if data.has("action") and data.action != "":
			toast_clicked.emit(data)
		_dismiss_toast(panel)

func _dismiss_toast(panel: Control) -> void:
	if not is_instance_valid(panel):
		return

	var index = _active_toasts.find(panel)
	if index >= 0:
		_active_toasts.remove_at(index)

	var slide_dur = UIStyles.get_animation_duration(SLIDE_DURATION)
	var fade_dur = UIStyles.get_animation_duration(FADE_DURATION)

	var tween: Tween = UIStyles.create_accessible_tween(panel, slide_dur)
	tween.parallel().tween_property(panel, "modulate:a", 0.0, fade_dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(panel.queue_free).set_delay(fade_dur)

	# Process queue
	_process_queue()

func _process_queue() -> void:
	if _toast_queue.is_empty():
		return
	if _active_toasts.size() >= MAX_VISIBLE_TOASTS:
		return

	var next_toast = _toast_queue.pop_front()
	_create_and_show_toast(next_toast)

## Convenience methods

func info(message: String, title: String = "Info", duration: float = DEFAULT_DURATION, action: String = "", action_data: Dictionary = {}) -> void:
	show_toast(message, ToastType.INFO, title, duration, action, action_data)

func warning(message: String, title: String = "Warning", duration: float = DEFAULT_DURATION, action: String = "", action_data: Dictionary = {}) -> void:
	show_toast(message, ToastType.WARNING, title, duration, action, action_data)

func error(message: String, title: String = "Error", duration: float = DEFAULT_DURATION, action: String = "", action_data: Dictionary = {}) -> void:
	show_toast(message, ToastType.ERROR, title, duration, action, action_data)

func success(message: String, title: String = "Success", duration: float = DEFAULT_DURATION, action: String = "", action_data: Dictionary = {}) -> void:
	show_toast(message, ToastType.SUCCESS, title, duration, action, action_data)

func loot(message: String, title: String = "Loot", duration: float = DEFAULT_DURATION, action: String = "", action_data: Dictionary = {}) -> void:
	show_toast(message, ToastType.LOOT, title, duration, action, action_data)

func achievement(message: String, title: String = "Achievement", duration: float = DEFAULT_DURATION, action: String = "", action_data: Dictionary = {}) -> void:
	show_toast(message, ToastType.ACHIEVEMENT, title, duration, action, action_data)

func show_loot(item_name: String, rarity: String = "common", quantity: int = 1) -> void:
	var rarity_colors := {
		"common": Color(0.6, 0.6, 0.6),
		"rare": Color(0.3, 0.7, 1.0),
		"epic": Color(0.8, 0.3, 1.0),
		"legendary": Color(1.0, 0.8, 0.2),
		"mythic": Color(1.0, 0.4, 0.1)
	}
	var color = rarity_colors.get(rarity.to_lower(), UIStyles.COLORS.text_primary)
	var msg = "%s x%d" % [item_name, quantity] if quantity > 1 else item_name
	show_toast(msg, ToastType.LOOT, "[%s] %s" % [rarity.capitalize(), "Loot Received"], 6.0, "open_inventory", {"item": item_name})

func show_quest_update(quest_name: String, status: String) -> void:
	var titles = {
		"accepted": "Quest Accepted",
		"progress": "Quest Progress",
		"completed": "Quest Completed",
		"failed": "Quest Failed"
	}
	var icons = {
		"accepted": "[Q]",
		"progress": "[>]",
		"completed": "[+]",
		"failed": "[X]"
	}
	var msg = "%s %s" % [icons.get(status, ""), quest_name]
	show_toast(msg, ToastType.INFO, titles.get(status, "Quest Update"), 7.0, "open_quest_log", {"quest": quest_name})

func show_achievement(achievement_name: String, description: String = "") -> void:
	var msg = "%s\n%s" % [achievement_name, description] if description != "" else achievement_name
	show_toast(msg, ToastType.ACHIEVEMENT, "Achievement Unlocked!", 8.0, "open_achievements", {"achievement": achievement_name})

func get_history() -> Array:
	return _notification_history.duplicate()

func get_unread_count() -> int:
	var count = 0
	for entry in _notification_history:
		if not entry.get("read", false):
			count += 1
	return count

func clear_history() -> void:
	_notification_history.clear()
	_refresh_history_list()
	history_cleared.emit()

func is_center_visible() -> bool:
	return _center_visible
