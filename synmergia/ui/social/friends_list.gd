## FriendsListUI - In-game friends management panel
## Migrated onto UIPanel base class.
class_name FriendsListUI
extends UIPanel

const CharacterData := preload("res://core/schemas/character_data.gd")

var _tab_container: TabContainer
var _friends_list: ItemList
var _requests_list: ItemList
var _blocked_list: ItemList

signal closed()  # Alias of panel_closed for back-compat.

func _ready() -> void:
	super._ready()
	panel_closed.connect(func() -> void: closed.emit())
	_bind_service_signals()


func _bind_service_signals() -> void:
	if not FriendsService:
		return
	var sigs := {
		"friend_added": _on_friends_changed,
		"friend_removed": _on_friends_changed,
		"friend_request_received": _on_friends_changed,
		"friend_request_sent": _on_friends_changed,
		"friend_request_accepted": _on_friends_changed,
		"friend_request_declined": _on_friends_changed,
		"friend_request_expired": _on_friends_changed,
		"player_status_changed": _on_status_changed,
		"player_blocked": _on_friends_changed,
		"player_unblocked": _on_friends_changed,
		"player_ignored": _on_friends_changed,
		"player_unignored": _on_friends_changed,
	}
	for sig_name in sigs:
		if FriendsService.has_signal(sig_name):
			var handler = sigs[sig_name]
			if not FriendsService.get(sig_name).is_connected(handler):
				FriendsService.get(sig_name).connect(handler)


func _on_friends_changed(_a = null, _b = null) -> void:
	if is_open():
		_refresh_all()


func _on_status_changed(_player_id: String, _online: bool) -> void:
	if is_open():
		_refresh_all()

func _setup_panel() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	panel.offset_right = -50
	panel.custom_minimum_size = Vector2(320, 500)
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

	var friends_tab := Control.new()
	friends_tab.name = "Friends"
	_tab_container.add_child(friends_tab)
	_setup_friends_tab(friends_tab)

	var requests_tab := Control.new()
	requests_tab.name = "Requests"
	_tab_container.add_child(requests_tab)
	_setup_requests_tab(requests_tab)

	var blocked_tab := Control.new()
	blocked_tab.name = "Blocked"
	_tab_container.add_child(blocked_tab)
	_setup_blocked_tab(blocked_tab)

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
	title.text = "Friends"
	title.add_theme_font_size_override("font_size", 18)
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

func _setup_friends_tab(tab: Control) -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	tab.add_child(vbox)

	_friends_list = ItemList.new()
	_friends_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_friends_list.item_selected.connect(_on_friend_selected)
	vbox.add_child(_friends_list)

	var btn_row := HBoxContainer.new()
	vbox.add_child(btn_row)

	var add_btn := Button.new()
	add_btn.text = "+ Add Friend"
	add_btn.pressed.connect(_on_add_friend)
	btn_row.add_child(add_btn)

func _setup_requests_tab(tab: Control) -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	tab.add_child(vbox)

	var received_label := Label.new()
	received_label.text = "Received:"
	received_label.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	vbox.add_child(received_label)

	_requests_list = ItemList.new()
	_requests_list.custom_minimum_size.y = 150
	vbox.add_child(_requests_list)

	var btn_row := HBoxContainer.new()
	vbox.add_child(btn_row)

	var accept_btn := Button.new()
	accept_btn.text = "Accept"
	accept_btn.pressed.connect(_on_accept_request)
	btn_row.add_child(accept_btn)

	var decline_btn := Button.new()
	decline_btn.text = "Decline"
	decline_btn.pressed.connect(_on_decline_request)
	btn_row.add_child(decline_btn)

func _setup_blocked_tab(tab: Control) -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	tab.add_child(vbox)

	_blocked_list = ItemList.new()
	_blocked_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_blocked_list)

	var btn_row := HBoxContainer.new()
	vbox.add_child(btn_row)

	var unblock_btn := Button.new()
	unblock_btn.text = "Unblock"
	unblock_btn.pressed.connect(_on_unblock)
	btn_row.add_child(unblock_btn)

func _refresh_all() -> void:
	_refresh_friends()
	_refresh_requests()
	_refresh_blocked()

func _refresh_friends() -> void:
	if not _friends_list:
		return
	_friends_list.clear()
	if not FriendsService:
		return

	var friends: Array = FriendsService.get_friends(_player_id)
	for friend in friends:
		var friend_data: Dictionary = friend
		var friend_name: String = friend_data.get("player_name", "Unknown")
		var online: bool = friend_data.get("online", false)
		var zone: String = friend_data.get("zone", "")
		var class_id: String = friend_data.get("class_id", "")
		var is_gm: bool = CharacterData.is_gm_class(class_id) if class_id else false

		var display: String = friend_name
		if is_gm:
			display = "[GM] " + display
		if online and zone != "":
			display += " (%s)" % zone

		_friends_list.add_item(display)

		if not online:
			_friends_list.set_item_custom_fg_color(
				_friends_list.item_count - 1, UIStyles.COLORS.text_disabled
			)

func _refresh_requests() -> void:
	if not _requests_list:
		return
	_requests_list.clear()
	if not FriendsService:
		return

	var requests: Array = FriendsService.get_pending_requests_received(_player_id)
	for req in requests:
		var req_data: Dictionary = req
		var from_name: String = req_data.get("from_player_name", "Unknown")
		_requests_list.add_item("From: %s" % from_name)

func _refresh_blocked() -> void:
	if not _blocked_list:
		return
	_blocked_list.clear()
	if not FriendsService:
		return

	var blocked: Array = FriendsService.get_blocked_players(_player_id)
	for player_id in blocked:
		_blocked_list.add_item(str(player_id))

func _on_friend_selected(index: int) -> void:
	if not FriendsService:
		return
	var friends: Array = FriendsService.get_friends(_player_id)
	if index < friends.size():
		var friend: Dictionary = friends[index]
		var friend_id: String = friend.get("player_id", "")
		_show_friend_options(friend_id, friend.get("player_name", ""))

func _show_friend_options(friend_id: String, friend_name: String) -> void:
	var confirm := ConfirmationDialog.new()
	confirm.dialog_text = "Remove %s from friends?" % friend_name
	confirm.confirmed.connect(func() -> void: _remove_friend(friend_id))
	confirm.canceled.connect(confirm.queue_free)
	add_child(confirm)
	confirm.popup_centered()

func _remove_friend(friend_id: String) -> void:
	if FriendsService:
		FriendsService.remove_friend(_player_id, friend_id)
		_refresh_friends()

func _on_add_friend() -> void:
	var dialog := AcceptDialog.new()
	dialog.dialog_text = "Enter player name to add:"
	dialog.title = "Add Friend"
	add_child(dialog)
	dialog.popup_centered()

	await dialog.confirmed
	var player_name: String = dialog.dialog_text.strip_edges()
	dialog.queue_free()

	if player_name != "" and FriendsService:
		# NOTE: signature is send_friend_request(from_id, from_name, to_id).
		# Pre-existing call passes _player_id twice; preserved here until Phase C
		# passes the real from_name via the player's CharacterData.
		var result: Dictionary = FriendsService.send_friend_request(_player_id, _player_id, player_name)
		_show_notification(result.get("message", "Request sent"))

func _on_accept_request() -> void:
	if not _requests_list or not FriendsService:
		return
	var selected: PackedInt32Array = _requests_list.get_selected_items()
	if selected.is_empty():
		return

	var requests: Array = FriendsService.get_pending_requests_received(_player_id)
	if selected[0] < requests.size():
		var request: Dictionary = requests[selected[0]]
		FriendsService.accept_friend_request(_player_id, request.get("id", ""))
		_refresh_all()

func _on_decline_request() -> void:
	if not _requests_list or not FriendsService:
		return
	var selected: PackedInt32Array = _requests_list.get_selected_items()
	if selected.is_empty():
		return

	var requests: Array = FriendsService.get_pending_requests_received(_player_id)
	if selected[0] < requests.size():
		var request: Dictionary = requests[selected[0]]
		FriendsService.decline_friend_request(_player_id, request.get("id", ""))
		_refresh_all()

func _on_unblock() -> void:
	if not _blocked_list or not FriendsService:
		return
	var selected: PackedInt32Array = _blocked_list.get_selected_items()
	if selected.is_empty():
		return

	var blocked: Array = FriendsService.get_blocked_players(_player_id)
	if selected[0] < blocked.size():
		FriendsService.unblock_player(_player_id, str(blocked[selected[0]]))
		_refresh_blocked()

func _show_notification(message: String) -> void:
	var notif := Label.new()
	notif.text = message
	notif.add_theme_color_override("font_color", UIStyles.COLORS.success)
	notif.z_index = 1000
	notif.global_position = Vector2(100, 100)
	get_tree().root.add_child(notif)
	await get_tree().create_timer(2.0).timeout
	notif.queue_free()