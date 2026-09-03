## CombatLog - Floating combat log and notifications
## Shows damage, healing, events, achievements
class_name CombatLog
extends Control

## Entry types
enum EntryType { DAMAGE, HEAL, SYSTEM, LOOT, QUEST, ACHIEVEMENT, GUILD, TRADE }

## Singleton
static var instance: CombatLog

## Components
var _rich_label: RichTextLabel
var _scroll: ScrollContainer
var _max_entries: int = 50
var _entries: Array = []

## Settings
var _show_damage: bool = true
var _show_healing: bool = true
var _show_system: bool = true
var _show_loot: bool = true

## Achievement popup
var _popup_queue: Array = []
var _popup_active: bool = false
var _popup_container: HBoxContainer
const _POPUP_DURATION: float = 3.0
const _POPUP_OFFSET_Y: float = 80.0

func _ready() -> void:
	instance = self
	_setup_ui()
	hide()

func _setup_ui() -> void:
	name = "CombatLog"
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = 10
	offset_top = 10
	offset_right = 350
	offset_bottom = 300
	custom_minimum_size = Vector2(340, 290)

	# Container
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "Combat Log"
	title.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	vbox.add_child(title)

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
	return text.replace("[", "［").replace("]", "］")

## ============================================================================
## PUBLIC API
## ============================================================================

static func get_instance() -> CombatLog:
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
	if not _show_system or not UIStyles:
		return
	var color: String = UIStyles.COLORS.info.to_html()
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
	var tw := Tween.new()
	panel.add_child(tw)
	tw.interpolate_property(panel, "offset_left", 310, 0, 0.4, Tween.TRANS_QUAD, Tween.EASE_OUT)
	tw.start()
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
	var tw := popup.get_node_or_null("Tween")
	if tw:
		tw.stop_all()
	# Hold then slide out
	var hold := Tween.new()
	popup.add_child(hold)
	var slide_out := func() -> void:
		if not is_instance_valid(popup):
			_display_next_popup()
			return
		var out := Tween.new()
		popup.add_child(out)
		out.interpolate_property(popup, "offset_left", 0, 310, 0.35, Tween.TRANS_QUAD, Tween.EASE_IN)
		out.start()
		out.tween_callback(_display_next_popup)
		out.tween_callback(popup.queue_free)
	hold.interpolate_callback(slide_out, _POPUP_DURATION)
	hold.start()

func set_show_damage(show: bool) -> void:
	_show_damage = show

func set_show_healing(show: bool) -> void:
	_show_healing = show

func set_show_system(show: bool) -> void:
	_show_system = show

func set_show_loot(show: bool) -> void:
	_show_loot = show
