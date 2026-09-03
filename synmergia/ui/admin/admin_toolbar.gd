## AdminToolbar - Quick access admin toolbar for HUD.
## Migrated onto UIWidget base class. F3 toggles the dashboard.
class_name AdminToolbar

const UIWidget = preload("res://ui/components/ui_widget.gd")
extends UIWidget

# Typed loosely because AdminDashboard itself has a pre-existing parse
# error (deferred to a dedicated session). All access is duck-typed.
var _dashboard_instance: Control
var _toggle_btn: Button

func _setup_widget() -> void:
	# Default hidden until F3 toggles it. UIWidget defaults to
	# always_visible=true; flip it for this widget.
	set_always_visible(false)
	# Add a hotkey for F3.
	set_hotkey(KEY_F3)
	_build_toolbar()

func _build_toolbar() -> void:
	# Anchor the toolbar to the top-right corner of the screen.
	var hbox := HBoxContainer.new()
	hbox.name = "Layout"
	hbox.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	hbox.anchor_left = 1.0
	hbox.anchor_bottom = 0.0
	hbox.offset_left = -120
	hbox.offset_bottom = 40
	hbox.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(hbox)

	_toggle_btn = Button.new()
	_toggle_btn.text = "⚙ Admin"
	_toggle_btn.custom_minimum_size.x = 100
	_toggle_btn.pressed.connect(_toggle_dashboard)
	hbox.add_child(_toggle_btn)

	UIStyles.apply_button_styles(_toggle_btn, UIStyles.create_button_style(
		Color(0.2, 0.2, 0.25, 0.9),
		Color(0.3, 0.3, 0.4, 0.9),
		Color(0.1, 0.1, 0.15, 0.9),
		Color(0.1, 0.1, 0.12, 0.9)
	))

func _toggle_dashboard() -> void:
	if _dashboard_instance and is_instance_valid(_dashboard_instance):
		_close_dashboard()
	else:
		_open_dashboard()

func _open_dashboard() -> void:
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
	# Get current admin ID from game state.
	# This should be connected to your actual player session.
	if PlayerManager and PlayerManager.local_player:
		var player: Node = PlayerManager.local_player
		# Duck-typed: Player entities expose either `.id` (var) or
		# `get_id()` (method) depending on the entity class.
		if "id" in player and player.id is String and player.id != "":
			return player.id
		if player.has_method("get_id"):
			var id_val: Variant = player.call("get_id")
			if id_val is String and id_val != "":
				return id_val
	return "admin_test"