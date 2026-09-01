## TargetFrame - Target information display
## Shows HP, name, level, and effects for selected target
class_name TargetFrame
extends Control

## Components
var _name_label: Label
var _level_label: Label
var _hp_bar: ProgressBar
var _mp_bar: ProgressBar
var _buff_container: HBoxContainer
var _debuff_container: HBoxContainer
var _class_label: Label
var _guild_label: Label

## Target data
var _target_id: String = ""
var _current_hp: int = 100
var _max_hp: int = 100
var _current_mp: int = 50
var _max_mp: int = 50

func _ready() -> void:
	_setup_ui()
	_connect_signals()
	hide()

func _setup_ui() -> void:
	name = "TargetFrame"
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	offset_left = -150
	offset_top = 80
	offset_right = 150
	offset_bottom = 180

	# Main container
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(vbox)

	# Name and level row
	var name_row := HBoxContainer.new()
	vbox.add_child(name_row)

	_name_label = Label.new()
	_name_label.text = "No Target"
	_name_label.add_theme_font_size_override("font_size", 16)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_name_label)
	
	_level_label = Label.new()
	_level_label.text = ""
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
	
	# Buffs row
	var buffs_row := HBoxContainer.new()
	vbox.add_child(buffs_row)
	
	var buffs_label := Label.new()
	buffs_label.text = "Buffs:"
	buffs_label.add_theme_font_size_override("font_size", 10)
	buffs_row.add_child(buffs_label)
	
	_buff_container = HBoxContainer.new()
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
	debuffs_row.add_child(_debuff_container)

func _connect_signals() -> void:
	if TargetingManager:
		TargetingManager.target_acquired.connect(_on_target_acquired)
		TargetingManager.target_cleared.connect(_on_target_cleared)

func _on_target_acquired(target) -> void:
		_target_id = target.entity_id if target and "entity_id" in target else ""
		if _target_id.is_empty():
			hide()
	
func _on_target_cleared(_previous_target) -> void:
		_target_id = ""
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

	_class_label.text = data.get("class", "")
	_guild_label.text = data.get("guild", "")

	_current_hp = data.get("health", 100)
	_max_hp = data.get("max_health", 100)
	_current_mp = data.get("mana", 50)
	_max_mp = data.get("max_mana", 50)

	_update_bars()
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


# ── Faction coloring ─────────────────────────────────────────────────────

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
		"friendly", "ally":
			color = UIStyles.COLORS.success
		"neutral":
			color = UIStyles.COLORS.text_primary
		_:
			if data.has("color") and data["color"] is Color:
				color = data["color"]
			else:
				color = UIStyles.COLORS.text_primary
	_name_label.add_theme_color_override("font_color", color)
