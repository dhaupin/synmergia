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

## ============================================================================
## PUBLIC API
## ============================================================================

static func get_instance() -> CombatLog:
return instance

func log_damage(target: String, amount: int, damage_type: String = "Physical") -> void:
if not _show_damage:
return
var color := UIStyles.COLORS.error.to_html()
var text := "[color=%s]%s took %d %s damage[/color]" % [color, target, amount, damage_type]
_add_entry(text, EntryType.DAMAGE)

func log_critical(target: String, amount: int) -> void:
if not _show_damage:
return
var color := UIStyles.COLORS.warning.to_html()
var text := "[color=%s][CRITICAL] %s took %d damage![/color]" % [color, target, amount]
_add_entry(text, EntryType.DAMAGE)

func log_miss(target: String) -> void:
if not _show_damage:
return
var color := UIStyles.COLORS.text_secondary.to_html()
var text := "[color=%s]Attack missed %s[/color]" % [color, target]
_add_entry(text, EntryType.DAMAGE)

func log_heal(target: String, amount: int, source: String = "") -> void:
if not _show_healing:
return
var color := UIStyles.COLORS.success.to_html()
var src_text := " from %s" % source if not source.is_empty() else ""
var text := "[color=%s]%s healed%s for %d[/color]" % [color, target, src_text, amount]
_add_entry(text, EntryType.HEAL)

func log_system(message: String) -> void:
if not _show_system:
return
var color := UIStyles.COLORS.info.to_html()
var text := "[color=%s]%s[/color]" % [color, message]
_add_entry(text, EntryType.SYSTEM)

func log_loot(item_name: String, quantity: int = 1) -> void:
if not _show_loot:
return
var color := UIStyles.COLORS.accent_gold.to_html()
var qty_text := " x%d" % quantity if quantity > 1 else ""
var text := "[color=%s]Looted: %s%s[/color]" % [color, item_name, qty_text]
_add_entry(text, EntryType.LOOT)

func log_quest(message: String) -> void:
var color := UIStyles.COLORS.warning.to_html()
var text := "[color=%s][Quest] %s[/color]" % [color, message]
_add_entry(text, EntryType.QUEST)

func log_achievement(name: String) -> void:
var color := UIStyles.COLORS.rarity_legendary.to_html()
var text := "[color=%s][Achievement] %s[/color]" % [color, name]
_add_entry(text, EntryType.ACHIEVEMENT)
_show_achievement_popup(name)

func log_guild(message: String) -> void:
var color := UIStyles.COLORS.info.to_html()
var text := "[color=%s][Guild] %s[/color]" % [color, message]
_add_entry(text, EntryType.GUILD)

func log_trade(message: String) -> void:
var color := UIStyles.COLORS.success.to_html()
var text := "[color=%s][Trade] %s[/color]" % [color, message]
_add_entry(text, EntryType.TRADE)

func clear() -> void:
_entries.clear()
_rich_label.clear()

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
# TODO: Create achievement popup animation
pass

func set_show_damage(show: bool) -> void:
_show_damage = show

func set_show_healing(show: bool) -> void:
_show_healing = show

func set_show_system(show: bool) -> void:
_show_system = show

func set_show_loot(show: bool) -> void:
_show_loot = show
