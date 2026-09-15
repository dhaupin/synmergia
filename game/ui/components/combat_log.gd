## CombatLog - Floating combat log and notifications
## Shows damage, healing, events, achievements
extends Control
class_name CombatLog
const UIStyles = preload("res://ui/components/ui_styles.gd")


## Entry types
enum EntryType { DAMAGE, HEAL, SYSTEM, LOOT, QUEST, ACHIEVEMENT, GUILD, TRADE }

## Singleton
static var instance: CombatLog

## Components
var _rich_label: RichTextLabel
var _scroll: ScrollContainer
var _filter_bar: HBoxContainer
var _search_box: LineEdit
var _filter_buttons: Dictionary = {}
var _max_entries: int = 200
var _entries: Array = []

## Filter state
var _show_damage: bool = true
var _show_healing: bool = true
var _show_system: bool = true
var _show_loot: bool = true
var _show_quest: bool = true
var _show_achievement: bool = true
var _show_guild: bool = true
var _show_trade: bool = true
var _search_filter: String = ""

## Achievement popup
var _popup_queue: Array = []
var _popup_active: bool = false
var _popup_container: HBoxContainer
const _POPUP_DURATION: float = 3.0
const _POPUP_OFFSET_Y: float = 80.0

func _ready() -> void:
	instance = self
	_setup_ui()
	_setup_accessibility()
	hide()


func _setup_accessibility() -> void:
	focus_mode = Control.FOCUS_ALL
	accessible_name = "Combat Log"
	accessible_description = "Displays combat events, damage, healing, and system messages. Use Tab to navigate filters and scroll through history."

func update_accessibility_settings() -> void:
	# Update search box
	if _search_box:
		_search_box.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
		var scale = UIStyles.get_text_scale()
		var current_size := _search_box.get_theme_font_size("font_size")
		if current_size > 0:
			_search_box.add_theme_font_size_override("font_size", int(current_size * scale))
	
	# Update filter buttons
	for btn in _filter_buttons.values():
		if btn and is_instance_valid(btn):
			btn.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
			var scale = UIStyles.get_text_scale()
			var current_size := btn.get_theme_font_size("font_size")
			if current_size > 0:
				btn.add_theme_font_size_override("font_size", int(current_size * scale))
	
	# Update rich text label
	if _rich_label:
		var scale = UIStyles.get_text_scale()
		var current_size := _rich_label.get_theme_font_size("default_font_size")
		if current_size > 0:
			_rich_label.add_theme_font_size_override("default_font_size", int(current_size * scale))

func _setup_ui() -> void:
	name = "CombatLog"
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = 10
	offset_top = 10
	offset_right = 450
	offset_bottom = 350
	custom_minimum_size = Vector2(440, 340)

	# Container
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(vbox)

	# Header with title and controls
	var header := HBoxContainer.new()
	header.custom_minimum_size.y = 30
	vbox.add_child(header)

	var title := Label.new()
	title.text = "Combat Log"
	title.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	header.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	# Search box
	_search_box = LineEdit.new()
	_search_box.placeholder_text = "Search..."
	_search_box.custom_minimum_size = Vector2(150, 24)
	_search_box.text_changed.connect(_on_search_changed)
	header.add_child(_search_box)

	# Clear button
	var clear_btn := Button.new()
	clear_btn.text = "Clear"
	clear_btn.custom_minimum_size = Vector2(60, 24)
	clear_btn.pressed.connect(clear)
	header.add_child(clear_btn)

	# Filter bar
	_filter_bar = HBoxContainer.new()
	_filter_bar.custom_minimum_size.y = 28
	vbox.add_child(_filter_bar)

	var filter_label := Label.new()
	filter_label.text = "Filters:"
	filter_label.add_theme_font_size_override("font_size", 10)
	filter_label.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	_filter_bar.add_child(filter_label)

	_create_filter_button("Damage", EntryType.DAMAGE, UIStyles.COLORS.error)
	_create_filter_button("Healing", EntryType.HEAL, UIStyles.COLORS.success)
	_create_filter_button("System", EntryType.SYSTEM, UIStyles.COLORS.info)
	_create_filter_button("Loot", EntryType.LOOT, UIStyles.COLORS.accent_gold)
	_create_filter_button("Quest", EntryType.QUEST, UIStyles.COLORS.warning)
	_create_filter_button("Achievement", EntryType.ACHIEVEMENT, UIStyles.COLORS.rarity_legendary)
	_create_filter_button("Guild", EntryType.GUILD, UIStyles.COLORS.info)
	_create_filter_button("Trade", EntryType.TRADE, UIStyles.COLORS.success)

	# Scroll + RichTextLabel
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_scroll)

	_rich_label = RichTextLabel.new()
	_rich_label.name = "LogContent"
	_rich_label.bbcode_enabled = true
	_rich_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rich_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rich_label.scroll_following = true
	_rich_label.add_theme_color_override("default_color", UIStyles.COLORS.text_primary)
	_scroll.add_child(_rich_label)

## Escape BBCode brackets in user-supplied content.
static func _esc(text: String) -> String:
	return text.replace("[", "[lb]").replace("]", "[rb]")

func _create_filter_button(name: String, entry_type: int, color: Color) -> void:
	var btn := Button.new()
	btn.text = name
	btn.toggle_mode = true
	btn.button_pressed = true
	btn.custom_minimum_size = Vector2(80, 24)
	btn.add_theme_color_override("font_color", color)
	btn.toggled.connect(_on_filter_toggled.bind(entry_type))
	_filter_bar.add_child(btn)
	_filter_buttons[entry_type] = btn

func _on_filter_toggled(pressed: bool, entry_type: int) -> void:
	match entry_type:
		EntryType.DAMAGE: _show_damage = pressed
		EntryType.HEAL: _show_healing = pressed
		EntryType.SYSTEM: _show_system = pressed
		EntryType.LOOT: _show_loot = pressed
		EntryType.QUEST: _show_quest = pressed
		EntryType.ACHIEVEMENT: _show_achievement = pressed
		EntryType.GUILD: _show_guild = pressed
		EntryType.TRADE: _show_trade = pressed
	_refresh_display()

func _on_search_changed(text: String) -> void:
	_search_filter = text.to_lower()
	_refresh_display()

## ============================================================================
## PUBLIC API
## ============================================================================

static func singleton() -> CombatLog:
	return instance

func log_damage(target: String, amount: int, damage_type: String = "Physical") -> void:
	if not _show_damage or not UIStyles:
		return
	var color: String = UIStyles.COLORS.error.to_html()
	var text := "[color=%s]%s took %d %s damage[/color]" % [color, _esc(target), amount, _esc(damage_type)]
	_add_entry(text, EntryType.DAMAGE)

func log_critical(target: String, amount: int) -> void:
	if not _show_damage or not UIStyles:
		return
	var color: String = UIStyles.COLORS.warning.to_html()
	var text := "[color=%s][CRITICAL] %s took %d damage![/color]" % [color, _esc(target), amount]
	_add_entry(text, EntryType.DAMAGE)

func log_miss(target: String) -> void:
	if not _show_damage or not UIStyles:
		return
	var color: String = UIStyles.COLORS.text_secondary.to_html()
	var text := "[color=%s]Attack missed %s[/color]" % [color, _esc(target)]
	_add_entry(text, EntryType.DAMAGE)

func log_heal(target: String, amount: int, source: String = "") -> void:
	if not _show_healing or not UIStyles:
		return
	var color: String = UIStyles.COLORS.success.to_html()
	var src_text := " from %s" % _esc(source) if not source.is_empty() else ""
	var text := "[color=%s]%s healed%s for %d[/color]" % [color, _esc(target), src_text, amount]
	_add_entry(text, EntryType.HEAL)

func log_system(message: String) -> void:
	if not _show_system:
		return
	if not UIStyles:
		return
	var color: String = UIStyles.COLORS.info.to_html() if UIStyles else "#CCCCCC"
	var text := "[color=%s]%s[/color]" % [color, _esc(message)]
	_add_entry(text, EntryType.SYSTEM)

func log_loot(item_name: String, quantity: int = 1) -> void:
	if not _show_loot or not UIStyles:
		return
	var color: String = UIStyles.COLORS.accent_gold.to_html()
	var qty_text := " x%d" % quantity if quantity > 1 else ""
	var text := "[color=%s]Looted: %s%s[/color]" % [color, _esc(item_name), qty_text]
	_add_entry(text, EntryType.LOOT)

func log_quest(message: String) -> void:
	if not UIStyles:
		return
	var color: String = UIStyles.COLORS.warning.to_html()
	var text := "[color=%s][Quest] %s[/color]" % [color, _esc(message)]
	_add_entry(text, EntryType.QUEST)

func log_achievement(name: String) -> void:
	if not UIStyles:
		return
	var color: String = UIStyles.COLORS.rarity_legendary.to_html()
	var text := "[color=%s][Achievement] %s[/color]" % [color, _esc(name)]
	_add_entry(text, EntryType.ACHIEVEMENT)
	_show_achievement_popup(name)

func log_guild(message: String) -> void:
	if not UIStyles:
		return
	var color: String = UIStyles.COLORS.info.to_html()
	var text := "[color=%s][Guild] %s[/color]" % [color, _esc(message)]
	_add_entry(text, EntryType.GUILD)

func log_trade(message: String) -> void:
	if not UIStyles:
		return
	var color: String = UIStyles.COLORS.success.to_html()
	var text := "[color=%s][Trade] %s[/color]" % [color, _esc(message)]
	_add_entry(text, EntryType.TRADE)

func clear() -> void:
	_entries.clear()
	_rich_label.clear()


func get_message_count() -> int:
	return _entries.size()

func add_message(text: String, entry_type: int = 2) -> void:
	_add_entry(text, entry_type)



## ============================================================================
## PRIVATE
## ============================================================================

func _add_entry(text: String, entry_type: int) -> void:
	var timestamp := _get_timestamp()
	_entries.append({
	"text": text,
	"type": entry_type,
	"time": Time.get_unix_time_from_system()
	})

	# Trim old entries
	while _entries.size() > _max_entries:
		_entries.pop_front()

	# Update display
	_refresh_display()

func _refresh_display() -> void:
	_rich_label.clear()

	for entry in _entries:
		# Filter by type
		var show := true
		match entry.type:
			EntryType.DAMAGE: show = _show_damage
			EntryType.HEAL: show = _show_healing
			EntryType.SYSTEM: show = _show_system
			EntryType.LOOT: show = _show_loot
			EntryType.QUEST: show = _show_quest
			EntryType.ACHIEVEMENT: show = _show_achievement
			EntryType.GUILD: show = _show_guild
			EntryType.TRADE: show = _show_trade
		
		if not show:
			continue
		
		# Filter by search text
		if _search_filter != "" and _search_filter not in entry.text.to_lower():
			continue
		
		var timestamp := _get_timestamp_for(entry.time)
		var text := "[%s] %s" % [timestamp, entry.text]
		_rich_label.append_text(text + "\n")

func _get_timestamp() -> String:
	var time_dict := Time.get_time_dict_from_system()
	return "%02d:%02d:%02d" % [time_dict.hour, time_dict.minute, time_dict.second]

func _get_timestamp_for(unix_time: float) -> String:
	var time_dict := Time.get_datetime_dict_from_unix_time(unix_time)
	return "%02d:%02d:%02d" % [time_dict.hour, time_dict.minute, time_dict.second]

func _show_achievement_popup(name: String) -> void:
	if not _popup_container:
		_init_popup_container()
	var popup := _create_popup(name)
	_popup_container.add_child(popup)
	_popup_queue.append(popup)
	if not _popup_active:
		_display_next_popup()

func _init_popup_container() -> void:
	_popup_container = HBoxContainer.new()
	_popup_container.name = "PopupContainer"
	_popup_container.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_popup_container.offset_left = -320
	_popup_container.offset_top = _POPUP_OFFSET_Y
	_popup_container.offset_right = -10
	_popup_container.offset_bottom = _POPUP_OFFSET_Y + 200
	_popup_container.alignment = BoxContainer.ALIGNMENT_END
	_popup_container.z_index = 1000
	get_tree().get_root().add_child(_popup_container)

func _create_popup(name: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(300, 50)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.08, 0.05, 0.95)
	style.border_color = Color(1.0, 0.8, 0.0, 0.8)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 12
	style.content_margin_top = 8
	style.content_margin_right = 12
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	panel.add_child(hbox)

	var icon := Label.new()
	icon.text = "[A]"
	icon.add_theme_font_size_override("font_size", 18)
	icon.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0))
	hbox.add_child(icon)

	var label := Label.new()
	label.text = name
	label.add_theme_color_override("font_color", Color.WHITE)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(label)

	# Start off-screen (translated right by 310px)
	var tw := create_tween()
	tw.tween_property(panel, "offset_left", 0, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return panel

func _display_next_popup() -> void:
	if _popup_queue.is_empty():
		_popup_active = false
		return
	_popup_active = true
	var popup: PanelContainer = _popup_queue.pop_front()
	if not is_instance_valid(popup) or not is_instance_valid(_popup_container):
		_display_next_popup()
		return
	# Hold then slide out
	var slide_out := func() -> void:
		if not is_instance_valid(popup):
			_display_next_popup()
			return
		var tw := popup.create_tween()
		tw.tween_property(popup, "offset_left", 310, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(_display_next_popup)
		tw.tween_callback(popup.queue_free)
	var hold := popup.create_tween()
	hold.tween_callback(slide_out).set_delay(_POPUP_DURATION)

func set_show_damage(show: bool) -> void:
	_show_damage = show
	if _filter_buttons.has(EntryType.DAMAGE):
		_filter_buttons[EntryType.DAMAGE].button_pressed = show

func set_show_healing(show: bool) -> void:
	_show_healing = show
	if _filter_buttons.has(EntryType.HEAL):
		_filter_buttons[EntryType.HEAL].button_pressed = show

func set_show_system(show: bool) -> void:
	_show_system = show
	if _filter_buttons.has(EntryType.SYSTEM):
		_filter_buttons[EntryType.SYSTEM].button_pressed = show

func set_show_loot(show: bool) -> void:
	_show_loot = show
	if _filter_buttons.has(EntryType.LOOT):
		_filter_buttons[EntryType.LOOT].button_pressed = show

func set_show_quest(show: bool) -> void:
	_show_quest = show
	if _filter_buttons.has(EntryType.QUEST):
		_filter_buttons[EntryType.QUEST].button_pressed = show

func set_show_achievement(show: bool) -> void:
	_show_achievement = show
	if _filter_buttons.has(EntryType.ACHIEVEMENT):
		_filter_buttons[EntryType.ACHIEVEMENT].button_pressed = show

func set_show_guild(show: bool) -> void:
	_show_guild = show
	if _filter_buttons.has(EntryType.GUILD):
		_filter_buttons[EntryType.GUILD].button_pressed = show

func set_show_trade(show: bool) -> void:
	_show_trade = show
	if _filter_buttons.has(EntryType.TRADE):
		_filter_buttons[EntryType.TRADE].button_pressed = show
