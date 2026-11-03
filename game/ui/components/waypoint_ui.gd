## WaypointUI - UI for managing player waypoints
## Handles creation, editing, deletion, and display of waypoints
extends Control
# NOTE: WaypointService is an autoload; reference it directly.

const UIStyles = preload("res://ui/components/ui_styles.gd")

## Security: Escape text to prevent BBCode injection
static func _esc(text: String) -> String:
	return text.replace("[", "[lb]")

# UI Elements
@onready var panel: PanelContainer
@onready var waypoint_list: VBoxContainer
@onready var create_btn: Button
@onready var clear_btn: Button
@onready var close_btn: Button

# Edit panel
@onready var edit_panel: PanelContainer
@onready var edit_name: LineEdit
@onready var edit_color: OptionButton
@onready var edit_icon: OptionButton
@onready var edit_beacon: CheckBox
@onready var edit_locked: CheckBox
@onready var save_btn: Button
@onready var cancel_btn: Button

# Create panel
@onready var create_panel: PanelContainer
@onready var create_name: LineEdit
@onready var create_color: OptionButton
@onready var create_icon: OptionButton
@onready var create_beacon: CheckBox
@onready var create_save_btn: Button
@onready var create_cancel_btn: Button

# Confirm dialog
@onready var confirm_dialog: ConfirmationDialog

# State
var _editing_waypoint_id: String = ""
var _is_visible: bool = false

func _ready() -> void:
	_setup_ui()
	_connect_signals()
	visible = false

func _setup_ui() -> void:
	# Main panel
	panel = PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -320
	panel.offset_top = 50
	panel.offset_right = -20
	panel.offset_bottom = 600
	add_child(panel)

	var style := StyleBoxFlat.new()
	style.bg_color = UIStyles.COLORS.background_dark
	style.border_color = UIStyles.COLORS.border
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", style)

	# Main VBox
	var main_vbox := VBoxContainer.new()
	main_vbox.name = "MainVBox"
	panel.add_child(main_vbox)

	# Header
	var header := HBoxContainer.new()
	header.name = "Header"
	var title := Label.new()
	title.text = "Waypoints"
	title.add_theme_font_size_override("font_size", 16)
	header.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	close_btn = Button.new()
	close_btn.text = "X"
	close_btn.pressed.connect(hide_panel)
	header.add_child(close_btn)
	main_vbox.add_child(header)

	var sep := HSeparator.new()
	main_vbox.add_child(sep)

	# Waypoint list scroll
	var scroll := preload("res://ui/components/drag_scroll.gd").new()
	scroll.name = "Scroll"
	scroll.custom_minimum_size.y = 400
	main_vbox.add_child(scroll)

	waypoint_list = VBoxContainer.new()
	waypoint_list.name = "WaypointList"
	waypoint_list.custom_minimum_size.y = 380
	scroll.add_child(waypoint_list)

	# Buttons
	var btn_hbox := HBoxContainer.new()
	btn_hbox.name = "ButtonHBox"
	create_btn = Button.new()
	create_btn.text = "+ New Waypoint"
	create_btn.pressed.connect(_on_create_pressed)
	btn_hbox.add_child(create_btn)
	clear_btn = Button.new()
	clear_btn.text = "Clear All"
	clear_btn.pressed.connect(_on_clear_pressed)
	btn_hbox.add_child(clear_btn)
	main_vbox.add_child(btn_hbox)

	_setup_edit_panel()
	_setup_create_panel()
	_setup_confirm_dialog()

func _setup_edit_panel() -> void:
	edit_panel = PanelContainer.new()
	edit_panel.name = "EditPanel"
	edit_panel.visible = false
	panel.get_node("MainVBox").add_child(edit_panel)

	var edit_vbox := VBoxContainer.new()
	edit_vbox.name = "EditVBox"
	edit_panel.add_child(edit_vbox)

	var edit_header := Label.new()
	edit_header.text = "Edit Waypoint"
	edit_vbox.add_child(edit_header)

	edit_name = LineEdit.new()
	edit_name.placeholder_text = "Waypoint name"
	edit_name.max_length = 32
	edit_vbox.add_child(edit_name)

	edit_color = OptionButton.new()
	for color_name in ["Red", "Orange", "Yellow", "Green", "Blue", "Purple", "Pink", "White"]:
		edit_color.add_item(color_name)
	edit_vbox.add_child(edit_color)

	edit_icon = OptionButton.new()
	for icon_name in ["Flag", "Star", "Chest", "Skull", "House", "Cave", "Quest", "Player", "Compass", "Custom"]:
		edit_icon.add_item(icon_name)
	edit_vbox.add_child(edit_icon)

	edit_beacon = CheckBox.new()
	edit_beacon.text = "Show beacon"
	edit_vbox.add_child(edit_beacon)

	edit_locked = CheckBox.new()
	edit_locked.text = "Lock waypoint"
	edit_vbox.add_child(edit_locked)

	var edit_btn_hbox := HBoxContainer.new()
	save_btn = Button.new()
	save_btn.text = "Save"
	save_btn.pressed.connect(_on_save_pressed)
	edit_btn_hbox.add_child(save_btn)
	cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(_on_cancel_edit)
	edit_btn_hbox.add_child(cancel_btn)
	edit_vbox.add_child(edit_btn_hbox)

func _setup_create_panel() -> void:
	create_panel = PanelContainer.new()
	create_panel.name = "CreatePanel"
	create_panel.visible = false
	panel.get_node("MainVBox").add_child(create_panel)

	var create_vbox := VBoxContainer.new()
	create_vbox.name = "CreateVBox"
	create_panel.add_child(create_vbox)

	var create_header := Label.new()
	create_header.text = "Create Waypoint Here"
	create_vbox.add_child(create_header)

	create_name = LineEdit.new()
	create_name.placeholder_text = "Waypoint name"
	create_name.max_length = 32
	create_vbox.add_child(create_name)

	create_color = OptionButton.new()
	for color_name in ["Red", "Orange", "Yellow", "Green", "Blue", "Purple", "Pink", "White"]:
		create_color.add_item(color_name)
	create_color.selected = 4  # Blue default
	create_vbox.add_child(create_color)

	create_icon = OptionButton.new()
	for icon_name in ["Flag", "Star", "Chest", "Skull", "House", "Cave", "Quest", "Player", "Compass", "Custom"]:
		create_icon.add_item(icon_name)
	create_vbox.add_child(create_icon)

	create_beacon = CheckBox.new()
	create_beacon.text = "Show beacon"
	create_beacon.button_pressed = true
	create_vbox.add_child(create_beacon)

	var create_btn_hbox := HBoxContainer.new()
	create_save_btn = Button.new()
	create_save_btn.text = "Create"
	create_save_btn.pressed.connect(_on_create_save_pressed)
	create_btn_hbox.add_child(create_save_btn)
	create_cancel_btn = Button.new()
	create_cancel_btn.text = "Cancel"
	create_cancel_btn.pressed.connect(_on_cancel_create)
	create_btn_hbox.add_child(create_cancel_btn)
	create_vbox.add_child(create_btn_hbox)

func _setup_confirm_dialog() -> void:
	confirm_dialog = ConfirmationDialog.new()
	confirm_dialog.name = "ConfirmDialog"
	confirm_dialog.title = "Confirm"
	confirm_dialog.dialog_text = "Delete all waypoints?"
	confirm_dialog.confirmed.connect(_on_confirm_clear)
	add_child(confirm_dialog)

func _connect_signals() -> void:
	if WaypointService:
		WaypointService.waypoint_created.connect(_on_waypoint_created)
		WaypointService.waypoint_updated.connect(_on_waypoint_updated)
		WaypointService.waypoint_deleted.connect(_on_waypoint_deleted)
		WaypointService.waypoints_cleared.connect(_on_waypoints_cleared)

func show_panel() -> void:
	visible = true
	_is_visible = true
	edit_panel.visible = false
	create_panel.visible = false
	_refresh_waypoint_list()

func hide_panel() -> void:
	visible = false
	_is_visible = false
	edit_panel.visible = false
	create_panel.visible = false

func toggle_panel() -> void:
	if visible:
		hide_panel()
	else:
		show_panel()

func _refresh_waypoint_list() -> void:
	# Clear existing
	for child in waypoint_list.get_children():
		child.queue_free()

	if not PlayerManager or not WaypointService:
		return

	var player_id := str(PlayerManager.get_local_player_id())
	var waypoints: Array = WaypointService.get_waypoints(player_id)

	if waypoints.is_empty():
		var empty := Label.new()
		empty.text = "No waypoints.\nClick 'New Waypoint' to create one at your current location."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		waypoint_list.add_child(empty)
		return

	for wp_data in waypoints:
		var row := _create_waypoint_row(wp_data)
		waypoint_list.add_child(row)

func _create_waypoint_row(wp_data: Dictionary) -> Control:
	var hbox := HBoxContainer.new()
	hbox.custom_minimum_size.y = 40

	var color := WaypointService.get_color_value(wp_data.get("color", 4))
	var icon := WaypointService.get_icon_string(wp_data.get("icon", 0))

	var icon_label := Label.new()
	icon_label.text = icon
	hbox.add_child(icon_label)

	var 	name_label := Label.new()
	name_label.text = _esc(str(wp_data.get("name", "Waypoint")))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(name_label)

	# Lock indicator
	if wp_data.get("is_locked", false):
		var lock := Label.new()
		lock.text = ""
		hbox.add_child(lock)

	# Quest indicator
	if wp_data.get("is_quest_waypoint", false):
		var quest := Label.new()
		quest.text = ""
		hbox.add_child(quest)

	# Set row background color
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(color.r, color.g, color.b, 0.1)
	hbox.add_theme_stylebox_override("panel", bg)

	# Activate button
	var active_btn := Button.new()
	var wp_id: String = wp_data.get("id", "")
	var is_active: bool = WaypointService.get_active_waypoint(str(PlayerManager.get_local_player_id())).get("id", "") == wp_id
	active_btn.text = "" if is_active else ""
	active_btn.pressed.connect(func(): _on_activate_pressed(wp_id))
	hbox.add_child(active_btn)

	# Edit button
	var edit_btn := Button.new()
	edit_btn.text = ""
	edit_btn.pressed.connect(func(): _on_edit_pressed(wp_data))
	hbox.add_child(edit_btn)

	# Delete button
	if not wp_data.get("is_locked", false) and not wp_data.get("is_quest_waypoint", false):
		var del_btn := Button.new()
		del_btn.text = ""
		del_btn.pressed.connect(func(): _on_delete_pressed(wp_id))
		hbox.add_child(del_btn)

	return hbox

func _on_create_pressed() -> void:
	edit_panel.visible = false
	create_panel.visible = true
	create_name.text = ""

func _on_edit_pressed(wp_data: Dictionary) -> void:
	_editing_waypoint_id = wp_data.get("id", "")
	edit_name.text = wp_data.get("name", "")
	edit_color.selected = wp_data.get("color", 4)
	edit_icon.selected = wp_data.get("icon", 0)
	edit_beacon.button_pressed = wp_data.get("show_beacon", true)
	edit_locked.button_pressed = wp_data.get("is_locked", false)

	create_panel.visible = false
	edit_panel.visible = true

func _on_activate_pressed(waypoint_id: String) -> void:
	if not PlayerManager or not WaypointService:
		return
	WaypointService.activate_waypoint(str(PlayerManager.get_local_player_id()), waypoint_id)
	_refresh_waypoint_list()

func _on_delete_pressed(waypoint_id: String) -> void:
	if not PlayerManager or not WaypointService:
		return
	WaypointService.delete_waypoint(str(PlayerManager.get_local_player_id()), waypoint_id)

func _on_clear_pressed() -> void:
	confirm_dialog.dialog_text = "Delete all non-locked waypoints?"
	confirm_dialog.popup_centered()

func _on_confirm_clear() -> void:
	if not PlayerManager or not WaypointService:
		return
	WaypointService.clear_waypoints(str(PlayerManager.get_local_player_id()))

func _on_save_pressed() -> void:
	if not PlayerManager or not WaypointService or _editing_waypoint_id.is_empty():
		return

	var updates := {
		"name": edit_name.text,
		"color": edit_color.selected,
		"icon": edit_icon.selected,
		"show_beacon": edit_beacon.button_pressed,
		"is_locked": edit_locked.button_pressed
	}

	WaypointService.update_waypoint(str(PlayerManager.get_local_player_id()), _editing_waypoint_id, updates)
	edit_panel.visible = false
	_refresh_waypoint_list()

func _on_cancel_edit() -> void:
	edit_panel.visible = false
	_editing_waypoint_id = ""

func _on_create_save_pressed() -> void:
	if not PlayerManager or not WaypointService:
		return

	var name := create_name.text
	if name.is_empty():
		name = "Waypoint %d" % Time.get_unix_time_from_system()

	var updates := {
		"color": create_color.selected,
		"icon": create_icon.selected,
		"show_beacon": create_beacon.button_pressed
	}

	# Create waypoint at current position
	var result := WaypointService.create_waypoint_here(str(PlayerManager.get_local_player_id()), name)
	if result.get("success", false):
		# Apply additional settings
		var wp_id: String = result.waypoint.get("id", "")
		if not wp_id.is_empty():
			WaypointService.update_waypoint(str(PlayerManager.get_local_player_id()), wp_id, updates)

	create_panel.visible = false
	_refresh_waypoint_list()

func _on_cancel_create() -> void:
	create_panel.visible = false

func _on_waypoint_created(player_id: String, waypoint: Dictionary) -> void:
	if PlayerManager and str(PlayerManager.get_local_player_id()) == player_id:
		_refresh_waypoint_list()

func _on_waypoint_updated(player_id: String, waypoint: Dictionary) -> void:
	if PlayerManager and str(PlayerManager.get_local_player_id()) == player_id:
		_refresh_waypoint_list()

func _on_waypoint_deleted(player_id: String, waypoint_id: String) -> void:
	if PlayerManager and str(PlayerManager.get_local_player_id()) == player_id:
		_refresh_waypoint_list()

func _on_waypoints_cleared(player_id: String, count: int) -> void:
	if PlayerManager and str(PlayerManager.get_local_player_id()) == player_id:
		_refresh_waypoint_list()
