## BuffBar - HUD widget that displays active buffs/debuffs as a row of slots.
## Migrated onto UIWidget base class.
class_name BuffBar
extends UIWidget

var _buff_slots: Array = []
var _max_slots: int = 8

signal buff_clicked(buff_id: String)
signal buff_expired(buff_id: String)

func _setup_widget() -> void:
	custom_minimum_size.y = 40
	# The root is a UIWidget (Control). We embed an HBoxContainer to do
	# the actual horizontal layout that the original HBoxContainer root
	# provided.
	var layout := HBoxContainer.new()
	layout.name = "Layout"
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(layout)
	_setup_slots(layout)

func _setup_slots(parent: Container) -> void:
	for i in range(_max_slots):
		var slot: TextureRect = _create_buff_slot()
		slot.name = "BuffSlot%d" % i
		parent.add_child(slot)
		_buff_slots.append(slot)

func _create_buff_slot() -> TextureRect:
	var slot := TextureRect.new()
	slot.custom_minimum_size = Vector2(32, 32)
	slot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	slot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	slot.add_theme_stylebox_override("normal", UIStyles.create_panel_style(
		Color(0.1, 0.1, 0.15, 0.8),
		UIStyles.COLORS.border,
		1,
		4
	))
	return slot

func set_buffs(buffs: Array) -> void:
	for slot in _buff_slots:
		slot.texture = null
		slot.tooltip_text = ""

	for i in range(mini(buffs.size(), _max_slots)):
		var buff: Dictionary = buffs[i]
		_set_buff_slot(i, buff)

func _set_buff_slot(index: int, buff: Dictionary) -> void:
	if index >= _buff_slots.size():
		return

	var slot: TextureRect = _buff_slots[index]
	var icon_path: String = buff.get("icon", "")
	var buff_name: String = buff.get("name", "Unknown")
	var duration: float = buff.get("duration", 0)
	var stack_count: int = buff.get("stacks", 1)
	var is_debuff: bool = buff.get("is_debuff", false)

	var color: Color = UIStyles.COLORS.info if not is_debuff else UIStyles.COLORS.error
	var tex := _create_color_texture(color)
	slot.texture = tex

	var duration_str := "%.1fs" % duration if duration > 0 else "Permanent"
	var stack_str := " (x%d)" % stack_count if stack_count > 1 else ""
	slot.tooltip_text = "%s%s\nDuration: %s\n%s" % [
		buff_name, stack_str, duration_str,
		"[color=#ff6666]Debuff[/color]" if is_debuff else "[color=#66ff66]Buff[/color]"
	]

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
			return slot.tooltip_text
	return ""