## PartyUI - Party management panel
class_name PartyUI
extends Control

var _player_id: String = ""
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
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(350, 450)
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.98)
	style.border_color = Color(0.3, 0.3, 0.4)
	style.border_width_left = 2
	style.corner_radius_top_left = 12
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	
	var main := VBoxContainer.new()
	panel.add_child(main)
	
	# Header
	var header := HBoxContainer.new()
	main.add_child(header)
	
	var title := Label.new()
	title.text = "Party"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1, 1, 1))
	header.add_child(title)
	
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.pressed.connect(close)
	header.add_child(close_btn)
	
	# Members list
	var members_label := Label.new()
	members_label.text = "Members"
	members_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	main.add_child(members_label)
	
	_members_list = ItemList.new()
	_members_list.custom_minimum_size.y = 200
	main.add_child(_members_list)
	
	# Pending invites
	var pending_label := Label.new()
	pending_label.text = "Pending Invites"
	pending_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	main.add_child(pending_label)
	
	_pending_list = ItemList.new()
	_pending_list.custom_minimum_size.y = 100
	main.add_child(_pending_list)
	
	# Buttons
	var btn_row := HBoxContainer.new()
	main.add_child(btn_row)
	
	var invite_btn := Button.new()
	invite_btn.text = "Invite"
	invite_btn.pressed.connect(_on_invite)
	btn_row.add_child(invite_btn)
	
	var leave_btn := Button.new()
	leave_btn.text = "Leave"
	leave_btn.pressed.connect(_on_leave)
	btn_row.add_child(leave_btn)
	
	var disband_btn := Button.new()
	disband_btn.text = "Disband"
	disband_btn.pressed.connect(_on_disband)
	btn_row.add_child(disband_btn)

func open(player_id: String) -> void:
	_player_id = player_id
	_refresh_all()
	show()

func _refresh_all() -> void:
	_refresh_members()
	_refresh_pending()

func _refresh_members() -> void:
	_members_list.clear()
	if not PartyService:
		return
	
	var party_id := PartyService.get_player_party(_player_id)
	if party_id == "":
		_members_list.add_item("Not in a party")
		return
	
	var members := PartyService.get_party_members(party_id)
	for member in members:
		var name: String = member.get("name", "?")
		var role: String = member.get("role", "?")
		var leader_icon := "*" if member.get("is_leader", false) else ""
		_members_list.add_item("%s %s [%s]" % [leader_icon, name, role])

func _refresh_pending() -> void:
	_pending_list.clear()
	if not PartyService:
		return
	
	var party_id := PartyService.get_player_party(_player_id)
	if party_id == "":
		return
	
	var pending := PartyService.get_pending_invites(party_id)
	for p in pending:
		_pending_list.add_item("Invite: %s" % p.get("player_name", "?"))

func _on_invite() -> void:
	var dialog := AcceptDialog.new()
	dialog.dialog_text = "Enter player name:"
	dialog.title = "Invite to Party"
	add_child(dialog)
	dialog.popup_centered()
	
	await dialog.confirmed
	var target_name: String = dialog.dialog_text.strip_edges()
	dialog.queue_free()
	
	if target_name != "" and PartyService:
		var result := PartyService.invite_player(_player_id, target_name)
		show_notification(result.get("message", ""))

func _on_leave() -> void:
	if PartyService:
		var result := PartyService.leave_party(_player_id)
		show_notification(result.get("message", ""))
		_refresh_members()

func _on_disband() -> void:
	if PartyService:
		var party_id := PartyService.get_player_party(_player_id)
		if party_id != "":
			var result := PartyService.disband_party(_player_id, party_id)
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
