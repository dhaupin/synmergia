## PartyUI - Party management panel
## Migrated onto UIPanel base class.
extends UIPanel
class_name PartyUI

const UIStyles = preload("res://ui/components/ui_styles.gd")
const UIPanel = preload("res://ui/components/ui_panel.gd")

var _members_list: ItemList
var _pending_list: ItemList

signal closed()  # Alias of panel_closed for back-compat.

func _ready() -> void:
	super._ready()
	panel_closed.connect(func() -> void: closed.emit())
	_bind_service_signals()


func _bind_service_signals() -> void:
	if not PartyService:
		return
	var sigs := {
		"party_member_updated": _on_party_updated,
		"player_joined_party": _on_party_updated,
		"player_left_party": _on_party_updated,
		"party_disbanded": _on_party_disbanded,
		"party_invite_sent": _on_party_updated,
		"party_invite_accepted": _on_party_updated,
		"party_invite_declined": _on_party_updated,
		"party_invite_expired": _on_party_updated,
		"leader_changed": _on_party_updated,
		"loot_rule_changed": _on_party_updated,
	}
	for sig_name in sigs:
		if PartyService.has_signal(sig_name):
			var handler = sigs[sig_name]
			if not PartyService.get(sig_name).is_connected(handler):
				PartyService.get(sig_name).connect(handler)


func _on_party_updated(_party_id: String = "", _pid: String = "") -> void:
	if is_open():
		_refresh_all()


func _on_party_disbanded(_party_id: String) -> void:
	close()

func _setup_panel() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(350, 450)
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

	var members_label := Label.new()
	members_label.text = "Members"
	members_label.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	main.add_child(members_label)

	_members_list = ItemList.new()
	_members_list.custom_minimum_size.y = 200
	main.add_child(_members_list)

	var pending_label := Label.new()
	pending_label.text = "Pending Invites"
	pending_label.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	main.add_child(pending_label)

	_pending_list = ItemList.new()
	_pending_list.custom_minimum_size.y = 100
	main.add_child(_pending_list)

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
	title.text = "Party"
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

func refresh() -> void:
	_refresh_all()

func _refresh_all() -> void:
	_refresh_members()
	_refresh_pending()

func _refresh_members() -> void:
	if not _members_list:
		return
	_members_list.clear()
	if not PartyService:
		return

	var party_data: Dictionary = PartyService.get_player_party(_player_id)
	if party_data.is_empty():
		_members_list.add_item("Not in a party")
		return

	var party_id: String = party_data.get("id", "")
	if party_id == "":
		_members_list.add_item("Not in a party")
		return

	var members: Array = PartyService.get_party_member_details(party_id)
	for member in members:
		var member_data: Dictionary = member
		var member_name: String = member_data.get("name", "?")
		var member_class: String = member_data.get("class", "?")
		var is_gm: bool = member_data.get("is_gm", false)
		var is_leader: bool = member_data.get("is_leader", false)
		var leader_icon: String = "*" if is_leader else ""
		var gm_icon: String = "⭐" if is_gm else ""
		_members_list.add_item("%s %s%s [%s]" % [leader_icon, gm_icon, member_name, member_class])

func _refresh_pending() -> void:
	if not _pending_list:
		return
	_pending_list.clear()
	if not PartyService:
		return

	var party_data: Dictionary = PartyService.get_player_party(_player_id)
	if party_data.is_empty():
		return

	var party_id: String = party_data.get("id", "")
	if party_id == "":
		return

	var pending: Array = PartyService.get_pending_invites(party_id)
	for p in pending:
		var pending_data: Dictionary = p
		_pending_list.add_item("Invite: %s" % pending_data.get("player_name", "?"))

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
		var ok: bool = PartyService.invite_player(_player_id, target_name)
		show_notification("Invite sent." if ok else "Failed to send invite.")

func _on_leave() -> void:
	if PartyService:
		var ok: bool = PartyService.leave_party(_player_id)
		show_notification("Left the party." if ok else "Failed to leave the party.", ok)
		_refresh_members()

func _on_disband() -> void:
	if not PartyService:
		return
	var party_data: Dictionary = PartyService.get_player_party(_player_id)
	var party_id: String = party_data.get("id", "")
	if party_id != "":
		var ok: bool = PartyService.disband_party(party_id)
		if ok:
			close()

func show_notification(message: String, _success: bool = true) -> void:
	var notif := Label.new()
	notif.text = message
	notif.add_theme_color_override("font_color", UIStyles.COLORS.success)
	notif.z_index = 1000
	notif.global_position = Vector2(100, 100)
	get_tree().root.add_child(notif)
	await get_tree().create_timer(2.0).timeout
	notif.queue_free()