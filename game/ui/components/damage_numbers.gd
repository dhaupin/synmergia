## DamageNumbers - Floating combat text system
## Shows damage, healing, miss/block/parry with animations
extends CanvasLayer
class_name DamageNumbers
const UIStyles = preload("res://ui/components/ui_styles.gd")


## Singleton
static var instance: DamageNumbers

## Pool of reusable labels
var _label_pool: Array[Label] = []
const POOL_SIZE: int = 50

## Active floating numbers
var _active_numbers: Array[Dictionary] = []

## Settings
var _show_damage: bool = true
var _show_healing: bool = true
var _show_miss: bool = true
var _show_crit: bool = true
var _font_size: int = 18
var _float_distance: float = 80.0
var _float_duration: float = 1.5

func _ready() -> void:
	instance = self
	layer = 20
	_init_pool()

func _init_pool() -> void:
	for i in range(POOL_SIZE):
		var label := Label.new()
		label.name = "DamageNumber_%d" % i
		label.visible = false
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override("font_size", _font_size)
		label.add_theme_font_override("font", UIStyles.get_damage_font())
		add_child(label)
		_label_pool.append(label)

func _get_pooled_label() -> Label:
	for label in _label_pool:
		if not label.visible:
			return label
	
	# Pool exhausted, create new one
	var label := Label.new()
	label.name = "DamageNumber_Extra"
	label.visible = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", _font_size)
	add_child(label)
	_label_pool.append(label)
	return label

## ============================================================================
## PUBLIC API
## ============================================================================

func show_damage(target: Node3D, amount: int, is_crit: bool = false, damage_type: String = "Physical") -> void:
	if not _show_damage or not is_instance_valid(target):
		return
	
	var color := UIStyles.COLORS.error
	if is_crit:
		color = UIStyles.COLORS.warning
		if not _show_crit:
			return
	
	var text := "%s%d" % [is_crit and "CRIT! " or "", amount]
	_spawn_number(target, text, color, is_crit, damage_type)

func show_heal(target: Node3D, amount: int, is_crit: bool = false) -> void:
	if not _show_healing or not is_instance_valid(target):
		return
	
	var color := UIStyles.COLORS.success
	if is_crit:
		color = Color(1.0, 1.0, 0.5)
	
	var text := "+%d" % amount
	_spawn_number(target, text, color, is_crit, "Heal")

func show_miss(target: Node3D, miss_type: String = "Miss") -> void:
	if not _show_miss or not is_instance_valid(target):
		return
	
	var colors := {
		"Miss": UIStyles.COLORS.text_secondary,
		"Block": Color(0.5, 0.7, 1.0),
		"Parry": Color(1.0, 0.8, 0.3),
		"Dodge": Color(0.3, 1.0, 0.5),
		"Immune": Color(1.0, 0.3, 0.3),
		"Resist": Color(0.7, 0.5, 1.0)
	}
	
	var color := colors.get(miss_type, UIStyles.COLORS.text_secondary)
	_spawn_number(target, miss_type, color, false, "Miss")

func show_absorb(target: Node3D, amount: int) -> void:
	if not is_instance_valid(target):
		return
	_spawn_number(target, "Absorb %d" % amount, Color(0.5, 0.8, 1.0), false, "Absorb")

func set_show_damage(show: bool) -> void:
	_show_damage = show

func set_show_healing(show: bool) -> void:
	_show_healing = show

func set_show_miss(show: bool) -> void:
	_show_miss = show

func set_show_crit(show: bool) -> void:
	_show_crit = show

## ============================================================================
## PRIVATE
## ============================================================================

func _spawn_number(target: Node3D, text: String, color: Color, is_crit: bool, num_type: String) -> void:
	var label := _get_pooled_label()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.visible = true
	
	# Position at target's screen position with random offset
	var viewport := get_viewport()
	var screen_pos := viewport.get_camera_3d().unproject_position(target.global_position)
	
	var offset_x := randf_range(-30, 30)
	var offset_y := randf_range(-20, 20)
	
	label.global_position = screen_pos + Vector2(offset_x, offset_y)
	
	# Animation data
	var anim_data := {
		"label": label,
		"start_pos": label.global_position,
		"end_pos": label.global_position + Vector2(0, -_float_distance),
		"start_time": Time.get_ticks_msec() / 1000.0,
		"duration": _float_duration,
		"is_crit": is_crit,
		"scale": is_crit ? 1.5 : 1.0,
		"type": num_type
	}
	
	_active_numbers.append(anim_data)
	
	# Crit effects
	if is_crit:
		label.add_theme_font_size_override("font_size", int(_font_size * 1.5))
		# Add outline effect
		var outline := Label.new()
		outline.text = text
		outline.add_theme_font_size_override("font_size", int(_font_size * 1.5))
		outline.add_theme_color_override("font_color", Color(0, 0, 0, 0.8))
		outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
		outline.global_position = label.global_position + Vector2(2, 2)
		add_child(outline)
		anim_data["outline"] = outline

func _process(delta: float) -> void:
	var current_time := Time.get_ticks_msec() / 1000.0
	var to_remove: Array = []
	
	for i in range(_active_numbers.size()):
		var anim := _active_numbers[i]
		var elapsed := current_time - anim.start_time
		var progress := elapsed / anim.duration
		
		if progress >= 1.0:
			to_remove.append(i)
			continue
		
		var label: Label = anim.label
		if not is_instance_valid(label):
			to_remove.append(i)
			continue
		
		# Ease out animation
		var eased := 1.0 - pow(1.0 - progress, 3)
		
		# Position
		var pos := anim.start_pos.lerp(anim.end_pos, eased)
		label.global_position = pos
		
		# Update outline if crit
		if anim.has("outline") and is_instance_valid(anim.outline):
			anim.outline.global_position = pos + Vector2(2, 2)
		
		# Fade out
		var alpha := 1.0 - progress
		var color := label.get_theme_color_override("font_color")
		color.a = alpha
		label.add_theme_color_override("font_color", color)
		
		# Scale for crit
		if anim.is_crit:
			var scale := anim.scale * (1.0 - progress * 0.3)
			label.add_theme_font_size_override("font_size", int(_font_size * scale))
			if anim.has("outline") and is_instance_valid(anim.outline):
				anim.outline.add_theme_font_size_override("font_size", int(_font_size * scale))
	
	# Remove finished animations (reverse order to maintain indices)
	for i in to_remove.reverse():
		var anim := _active_numbers[i]
		anim.label.visible = false
		if anim.has("outline") and is_instance_valid(anim.outline):
			anim.outline.queue_free()
		_active_numbers.remove_at(i)

func clear_all() -> void:
	for anim in _active_numbers:
		if is_instance_valid(anim.label):
			anim.label.visible = false
		if anim.has("outline") and is_instance_valid(anim.outline):
			anim.outline.queue_free()
	_active_numbers.clear()