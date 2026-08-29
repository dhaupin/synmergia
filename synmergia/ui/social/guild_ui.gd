## GuildUI - Guild management panel
class_name GuildUI
extends Control

var _player_id: String = ""
var _panel: PanelContainer
var _tab_container: TabContainer
var _members_list: ItemList
var _pending_list: ItemList

signal closed()

func _ready() -> void:
	_setup_ui()
	hide()

func _setup_ui() -> void:
	# Overlay
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.gui_input.connect(func(e): 
		if e is InputEventMouseButton and e.pressed: close()
	)
	add_child(overlay)
	
	# Panel
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(450, 550)
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.98)
	style.border_color = Color(0.3, 0.3, 0.4)
	style.border_width_left = 2
	style.corner_radius_top_left = 12
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	
	var main := VBoxContainer.new()
	_panel.add_child(main)
	
	# Header
	var header := HBoxContainer.new()
	main.add_child(header)
	
	var title := Label.new()
	title.text = "Guild Management"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1, 1, 1))
	header.add_child(title)
	
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.pressed.connect(close)
	header.add_child(close_btn)
	
	# Tabs
	_tab_container = TabContainer.new()
	_tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(_tab_container)
	
	_setup_members_tab()
	_setup_invites_tab()
	_setup_settings_tab()

func _setup_members_tab() -> void:
	var tab := Control.new()
	tab.name = "Members"
	_tab_container.add_child(tab)
	
	var vbox := VBoxContainer.new()
	tab.add_child(vbox)
	
	_members_list = ItemList.new()
	_members_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_members_list)
	
	var info_label := Label.new()
	info_label.text = "Guild members will appear here"
	info_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	vbox.add_child(info_label)

func _setup_invites_tab() -> void:
	var tab := Control.new()
	tab.name = "Invites"
	_tab_container.add_child(tab)
	
	var vbox := VBoxContainer.new()
	tab.add_child(vbox)
	
	var label := Label.new()
	label.text = "Pending Invites"
	label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	vbox.add_child(label)
	
	_pending_list = ItemList.new()
	_pending_list.custom_minimum_size.y = 150
	vbox.add_child(_pending_list)
	
	var btn_row := HBoxContainer.new()
	vbox.add_child(btn_row)
	
	var invite_btn := Button.new()
	invite_btn.text = "Invite Player"
	invite_btn.pressed.connect(_on_invite_player)
	btn_row.add_child(invite_btn)

func _setup_settings_tab() -> void:
	var tab := Control.new()
	tab.name = "Settings"
	_tab_container.add_child(tab)
	
	var vbox := VBoxContainer.new()
	tab.add_child(vbox)
	
	var label := Label.new()
	label.text = "Guild settings"
	label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	vbox.add_child(label)
	
	var leave_btn := Button.new()
	leave_btn.text = "Leave Guild"
	leave_btn.pressed.connect(_on_leave_guild)
	vbox.add_child(leave_btn)

func open(player_id: String) -> void:
	_player_id = player_id
	_refresh_all()
	show()

func _refresh_all() -> void:
	_refresh_members()
	_refresh_invites()

func _refresh_members() -> void:
	_members_list.clear()
	if not GuildService:
		return
	
	var guild_id := GuildService.get_player_guild(_player_id)
	if guild_id == "":
		_members_list.add_item("Not in a guild")
		return
	
	var members := GuildService.get_guild_members(guild_id)
	for member in members:
		var name: String = member.get("name", "?")
		var rank: String = member.get("rank", "?")
		_members_list.add_item("%s [%s]" % [name, rank])

func _refresh_invites() -> void:
	_pending_list.clear()
	if not GuildService:
		return
	
	var guild_id := GuildService.get_player_guild(_player_id)
	if guild_id == "":
		return
	
	var invites := GuildService.get_pending_invites(guild_id)
	for invite in invites:
		var name: String = invite.get("player_name", "?")
		_pending_list.add_item("Invite: %s" % name)

func _on_invite_player() -> void:
	var dialog := AcceptDialog.new()
	dialog.dialog_text = "Enter player name:"
	dialog.title = "Invite to Guild"
	add_child(dialog)
	dialog.popup_centered()
	
	await dialog.confirmed
	var target_name: String = dialog.dialog_text.strip_edges()
	dialog.queue_free()
	
	if target_name != "" and GuildService:
		var result := GuildService.invite_player(_player_id, target_name)
		show_notification(result.get("message", ""))

func _on_leave_guild() -> void:
	var confirm := ConfirmationDialog.new()
	confirm.dialog_text = "Are you sure you want to leave the guild?"
	add_child(confirm)
	confirm.popup_centered()
	
	await confirm.confirmed
	confirm.queue_free()
	
	if GuildService:
		var result := GuildService.leave_guild(_player_id)
		show_notification(result.get("message", ""))
		if result.get("success", false):
			close()

func show_notification(message: String) -> void:
	var notif := Label.new()
	notif.text = message
	notif.add_theme_color_override("font_color", Color(0.3, 0.8, 0.3))
	notif.z_index = 1000
	notif.global_position = Vector2(100, 100)
	get_tree().root.add_child(notif)
	await get_tree().create_timer(2.0).timeout
	notif.queue_free()

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not visible:
		closed.emit()
