## BuffBar - Displays active buffs/debuffs
class_name BuffBar
extends HBoxContainer

## Buff/debuff slots
var _buff_slots: Array = []
var _max_slots: int = 8

signal buff_clicked(buff_id: String)
signal buff_expired(buff_id: String)

func _ready() -> void:
	custom_minimum_size.y = 40
	_setup_slots()

func _setup_slots() -> void:
	for i in range(_max_slots):
		var slot := _create_buff_slot()
		slot.name = "BuffSlot%d" % i
		add_child(slot)
		_buff_slots.append(slot)

func _create_buff_slot() -> TextureRect:
	var slot := TextureRect.new()
	slot.custom_minimum_size = Vector2(32, 32)
	slot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	slot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.8)
	style.border_color = Color(0.3, 0.3, 0.3)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	slot.add_theme_stylebox_override("normal", style)
	
	return slot

func set_buffs(buffs: Array) -> void:
	# Clear all slots
	for slot in _buff_slots:
		slot.texture = null
		slot.tooltip_text = ""
	
	# Set buffs
	for i in range(mini(buffs.size(), _max_slots)):
		var buff: Dictionary = buffs[i]
		_set_buff_slot(i, buff)

func _set_buff_slot(index: int, buff: Dictionary) -> void:
	if index >= _buff_slots.size():
		return
	
	var slot: TextureRect = _buff_slots[index]
	var icon_path: String = buff.get("icon", "")
	var name: String = buff.get("name", "Unknown")
	var duration: float = buff.get("duration", 0)
	var stack_count: int = buff.get("stacks", 1)
	var is_debuff: bool = buff.get("is_debuff", false)
	
	# Set icon (placeholder colored rect for now)
	var color := Color(0.3, 0.6, 1) if not is_debuff else Color(1, 0.3, 0.3)
	var tex := _create_color_texture(color)
	slot.texture = tex
	
	# Set tooltip
	var duration_str := "%.1fs" % duration if duration > 0 else "Permanent"
	var stack_str := " (x%d)" % stack_count if stack_count > 1 else ""
	slot.tooltip_text = "%s%s\nDuration: %s\n%s" % [
		name, stack_str, duration_str,
		"[color=#ff6666]Debuff[/color]" if is_debuff else "[color=#66ff66]Buff[/color]"
	]
	
	# Update border color for debuffs
	var style := slot.get_theme_stylebox("normal")
	if style:
		style.border_color = color

func _create_color_texture(color: Color) -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(color)
	var tex := ImageTexture.create_from_image(img)
	return tex

func get_buff_at_position(local_pos: Vector2) -> String:
	for i in range(_buff_slots.size()):
		var slot: Control = _buff_slots[i]
		if slot.get_global_rect().has_point(local_pos + global_position):
			return slot.tooltip_text  # Return buff name from tooltip
	return ""
