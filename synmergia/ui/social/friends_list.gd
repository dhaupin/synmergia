## FriendsListUI - In-game friends management panel
class_name FriendsListUI
extends Control

## Current player
var _player_id: String = ""

## UI Elements
var _panel: PanelContainer
var _tab_container: TabContainer
var _friends_list: ItemList
var _blocked_list: ItemList
var _ignored_list: ItemList
var _requests_list: ItemList

## Signals
signal closed()

func _ready() -> void:
	_setup_ui()
	hide()

func _setup_ui() -> void:
	# Semi-transparent overlay
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.gui_input.connect(func(e): 
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			hide()
	)
	add_child(overlay)
	
	# Main panel
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_panel.offset_right = -50
	_panel.custom_minimum_size = Vector2(320, 500)
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.98)
	style.border_color = Color(0.3, 0.3, 0.4)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	_panel.add_theme_stylebox_override("panel", style)
	
	add_child(_panel)
	
	var main := VBoxContainer.new()
	_panel.add_child(main)
	
	# Header
	var header := HBoxContainer.new()
	main.add_child(header)
	
	var title := Label.new()
	title.text = "Friends"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1, 1, 1))
	header.add_child(title)
	
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.pressed.connect(hide)
	header.add_child(close_btn)
	
	# Tabs
	_tab_container = TabContainer.new()
	_tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(_tab_container)
	
	# Friends tab
	var friends_tab := Control.new()
	friends_tab.name = "Friends"
	_tab_container.add_child(friends_tab)
	_setup_friends_tab(friends_tab)
	
	# Requests tab
	var requests_tab := Control.new()
	requests_tab.name = "Requests"
	_tab_container.add_child(requests_tab)
	_setup_requests_tab(requests_tab)
	
	# Blocked tab
	var blocked_tab := Control.new()
	blocked_tab.name = "Blocked"
	_tab_container.add_child(blocked_tab)
	_setup_blocked_tab(blocked_tab)

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
	received_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
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

func open(player_id: String) -> void:
	_player_id = player_id
	_refresh_all()
	show()

func _refresh_all() -> void:
	_refresh_friends()
	_refresh_requests()
	_refresh_blocked()

func _refresh_friends() -> void:
	_friends_list.clear()
	if not FriendsService:
		return
	
	var friends: Array = FriendsService.get_friends(_player_id)
	for friend in friends:
		var name: String = friend.get("player_name", "Unknown")
		var online: bool = friend.get("online", false)
		var zone: String = friend.get("zone", "")
		
		var status_icon := "[green]" if online else "[gray]"
		var display := "%s*%s[/color] %s" % [status_icon, name, "[/color]" if online else "[/color]"]
		if online and zone != "":
			display += " (%s)" % zone
		
		_friends_list.add_item(display)
		
		# Color online green, offline gray
		if not online:
			_friends_list.set_item_custom_fg_color(_friends_list.item_count - 1, Color(0.5, 0.5, 0.5))

func _refresh_requests() -> void:
	_requests_list.clear()
	if not FriendsService:
		return
	
	var requests: Array = FriendsService.get_pending_requests_received(_player_id)
	for req in requests:
		var from_name: String = req.get("from_player_name", "Unknown")
		_requests_list.add_item("From: %s" % from_name)

func _refresh_blocked() -> void:
	_blocked_list.clear()
	if not FriendsService:
		return
	
	var blocked: Array = FriendsService.get_blocked_players(_player_id)
	for player_id in blocked:
		_blocked_list.add_item(player_id)

func _on_friend_selected(index: int) -> void:
	var friends: Array = FriendsService.get_friends(_player_id)
	if index < friends.size():
		var friend: Dictionary = friends[index]
		var friend_id: String = friend.get("player_id", "")
		_show_friend_options(friend_id, friend.get("player_name", ""))

func _show_friend_options(friend_id: String, friend_name: String) -> void:
	# Simple confirm dialog for removing friend
	var confirm := ConfirmationDialog.new()
	confirm.dialog_text = "Remove %s from friends?" % friend_name
	confirm.confirmed.connect(func(): _remove_friend(friend_id))
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
		var result := FriendsService.send_friend_request(_player_id, _player_id, player_name)
		_show_notification(result.get("message", "Request sent"))

func _on_accept_request() -> void:
	var idx := _requests_list.get_selected_items()
	if idx.is_empty():
		return
	
	var requests: Array = FriendsService.get_pending_requests_received(_player_id)
	if idx[0] < requests.size():
		var request: Dictionary = requests[idx[0]]
		FriendsService.accept_friend_request(_player_id, request.get("id", ""))
		_refresh_all()

func _on_decline_request() -> void:
	var idx := _requests_list.get_selected_items()
	if idx.is_empty():
		return
	
	var requests: Array = FriendsService.get_pending_requests_received(_player_id)
	if idx[0] < requests.size():
		var request: Dictionary = requests[idx[0]]
		FriendsService.decline_friend_request(_player_id, request.get("id", ""))
		_refresh_all()

func _on_unblock() -> void:
	var idx := _blocked_list.get_selected_items()
	if idx.is_empty():
		return
	
	var blocked: Array = FriendsService.get_blocked_players(_player_id)
	if idx[0] < blocked.size():
		FriendsService.unblock_player(_player_id, blocked[idx[0]])
		_refresh_blocked()

func _show_notification(message: String) -> void:
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
