## GuildUI - Guild management panel
## Migrated onto UIPanel base class.
extends "res://ui/components/ui_panel.gd"
class_name GuildUI
const UIPanel = preload("res://ui/components/ui_panel.gd")

var _tab_container: TabContainer
var _members_list: ItemList
var _pending_list: ItemList

signal closed()  # Alias of panel_closed for back-compat.

func _ready() -> void:
	super._ready()
	_setup_accessibility()
	panel_closed.connect(func() -> void: closed.emit())
	_bind_service_signals()


func _setup_accessibility() -> void:
	pass

func update_accessibility_settings(high_contrast: bool, text_scale: float, reduce_motion: bool) -> void:
	pass

func _bind_service_signals() -> void:
	if not GuildService:
		return
	var sigs := {
		"guild_info_updated": _on_guild_updated,
		"player_joined_guild": _on_guild_updated,
		"player_left_guild": _on_guild_updated,
		"player_kicked": _on_player_kicked,
		"guild_disbanded": _on_guild_disbanded,
		"rank_changed": _on_guild_updated,
		"leader_changed": _on_guild_updated,
		"guildMOTD_updated": _on_guild_updated,
		"guild_notice_updated": _on_guild_updated,
		"guild_invite_sent": _on_guild_updated,
		"guild_invite_accepted": _on_guild_updated,
		"guild_invite_declined": _on_guild_updated,
		"alliance_created": _on_guild_updated,
		"alliance_disbanded": _on_guild_updated,
		"alliance_guild_joined": _on_guild_updated,
		"alliance_guild_left": _on_guild_updated,
	}
	for sig_name in sigs:
		if GuildService.has_signal(sig_name):
			var handler = sigs[sig_name]
			if not GuildService.get(sig_name).is_connected(handler):
				GuildService.get(sig_name).connect(handler)


func _on_guild_updated(_guild_id: String = "") -> void:
	if is_open():
		_refresh_all()


func _on_player_kicked(_guild_id: String, player_id: String, _kicker_id: String) -> void:
	if player_id == _player_id:
		close()


func _on_guild_disbanded(_guild_id: String) -> void:
	close()

func _setup_panel() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(450, 550)
	panel.add_theme_stylebox_override("panel", UIStyles.create_panel_style(
		UIStyles.COLORS.background_dark,
		UIStyles.COLORS.border,
		2,
		12
	))
	panel.name = "Panel"
	add_child(panel)

	var main := VBoxContainer.new()
	main.name = "Main"
	panel.add_child(main)

	_tab_container = TabContainer.new()
	_tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(_tab_container)

	_setup_members_tab()
	_setup_invites_tab()
	_setup_settings_tab()

func _setup_header() -> void:
	var panel := get_panel()
	if not panel:
		return
	var main := panel.get_node_or_null("Main") as VBoxContainer
	if not main:
		return

	var header := HBoxContainer.new()
	header.name = "Header"
	main.add_child(header)
	main.move_child(header, 0)

	var title := Label.new()
	title.text = "Guild Management"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", UIStyles.COLORS.text_primary)
	header.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.pressed.connect(close)
	header.add_child(close_btn)

func _on_open() -> void:
	_refresh_all()

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
	info_label.add_theme_color_override("font_color", UIStyles.COLORS.text_disabled)
	vbox.add_child(info_label)

func _setup_invites_tab() -> void:
	var tab := Control.new()
	tab.name = "Invites"
	_tab_container.add_child(tab)

	var vbox := VBoxContainer.new()
	tab.add_child(vbox)

	var label := Label.new()
	label.text = "Pending Invites"
	label.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
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
	label.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	vbox.add_child(label)

	var leave_btn := Button.new()
	leave_btn.text = "Leave Guild"
	leave_btn.pressed.connect(_on_leave_guild)
	vbox.add_child(leave_btn)

func _refresh_all() -> void:
	_refresh_members()
	_refresh_invites()

func _refresh_members() -> void:
	if not _members_list:
		return
	_members_list.clear()
	if not GuildService:
		return

	var guild_data: Dictionary = GuildService.get_player_guild(_player_id)
	if guild_data.is_empty():
		_members_list.add_item("Not in a guild")
		return

	var guild_id: String = guild_data.get("id", "")
	if guild_id == "":
		_members_list.add_item("Not in a guild")
		return

	var members: Array = GuildService.get_guild_members(guild_id)
	for member in members:
		var member_data: Dictionary = member
		var member_name: String = member_data.get("name", "?")
		var rank: String = member_data.get("rank", "?")
		_members_list.add_item("%s [%s]" % [member_name, rank])

func _refresh_invites() -> void:
	if not _pending_list:
		return
	_pending_list.clear()
	if not GuildService:
		return

	var guild_data: Dictionary = GuildService.get_player_guild(_player_id)
	if guild_data.is_empty():
		return

	var guild_id: String = guild_data.get("id", "")
	if guild_id == "":
		return

	var invites: Array = GuildService.get_pending_invites(guild_id)
	for invite in invites:
		var invite_data: Dictionary = invite
		var player_name: String = invite_data.get("player_name", "?")
		_pending_list.add_item("Invite: %s" % player_name)

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
		var ok: bool = GuildService.invite_player(_player_id, target_name)
		show_notification("Invite sent." if ok else "Failed to send invite.")

func _on_leave_guild() -> void:
	var confirm := ConfirmationDialog.new()
	confirm.dialog_text = "Are you sure you want to leave the guild?"
	add_child(confirm)
	confirm.popup_centered()

	await confirm.confirmed
	confirm.queue_free()

	if GuildService:
		var ok: bool = GuildService.leave_guild(_player_id)
		if ok:
			show_notification("Left the guild.")
			close()
		else:
			show_notification("Failed to leave the guild.", false)

func show_notification(message: String, _success: bool = true) -> void:
	var notif := Label.new()
	notif.text = message
	notif.add_theme_color_override("font_color", UIStyles.COLORS.success)
	notif.z_index = 1000
	notif.global_position = Vector2(100, 100)
	get_tree().root.add_child(notif)
	await get_tree().create_timer(2.0).timeout
	notif.queue_free()
