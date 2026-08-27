## AdminToolbar - Quick access admin toolbar for HUD
## Minimal toolbar to open admin dashboard
class_name AdminToolbar
extends Control

## Reference to admin dashboard
var _dashboard: Control
var _dashboard_instance: AdminDashboard

## Toggle button
var _toggle_btn: Button

func _ready() -> void:
	_setup_ui()

func _setup_ui() -> void:
	# Create minimal toolbar
	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	hbox.anchor_left = 1.0
	hbox.anchor_bottom = 0.0
	hbox.offset_left = -120
	hbox.offset_bottom = 40
	hbox.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(hbox)
	
	# Admin button
	_toggle_btn = Button.new()
	_toggle_btn.text = "⚙ Admin"
	_toggle_btn.custom_minimum_size.x = 100
	_toggle_btn.pressed.connect(_toggle_dashboard)
	hbox.add_child(_toggle_btn)
	
	# Style the button
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.25, 0.9)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	_toggle_btn.add_theme_stylebox_override("normal", style)
	
	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(0.3, 0.3, 0.4, 0.9)
	hover_style.corner_radius_top_left = 4
	hover_style.corner_radius_top_right = 4
	hover_style.corner_radius_bottom_left = 4
	hover_style.corner_radius_bottom_right = 4
	_toggle_btn.add_theme_stylebox_override("hover", hover_style)

func _toggle_dashboard() -> void:
	if _dashboard_instance and is_instance_valid(_dashboard_instance):
		_close_dashboard()
	else:
		_open_dashboard()

func _open_dashboard() -> void:
	# Load and instantiate dashboard
	var scene_path := "res://ui/admin/admin_dashboard.tscn"
	var packed_scene := load(scene_path)
	if packed_scene:
		_dashboard_instance = packed_scene.instantiate()
		_dashboard_instance.closed.connect(_on_dashboard_closed)
		_dashboard_instance.set_admin_id(_get_admin_id())
		get_tree().root.add_child(_dashboard_instance)
		_toggle_btn.text = "✕ Admin"

func _close_dashboard() -> void:
	if _dashboard_instance and is_instance_valid(_dashboard_instance):
		_dashboard_instance.queue_free()
		_dashboard_instance = null
	_toggle_btn.text = "⚙ Admin"

func _on_dashboard_closed() -> void:
	_close_dashboard()

func _get_admin_id() -> String:
	# Get current admin ID from game state
	# This should be connected to your actual player session
	if PlayerManager and PlayerManager.local_player:
		return PlayerManager.local_player.get("id", "")
	return "admin_test"

func _input(event: InputEvent) -> void:
	# Quick toggle with F3
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_F3:
			_toggle_dashboard()
