## ChatUI - In-game chat panel with channels
## Uses UIStyles for consistent theming
extends Control
class_name ChatUI
const UIStyles = preload("res://ui/components/ui_styles.gd")


## Escape BBCode brackets in user-supplied content.
static func _esc(text: String) -> String:
	return text.replace('[', '［').replace(']', '］')

## Chat history display
var _chat_history: RichTextLabel
var _chat_input: LineEdit
var _channel_selector: OptionButton

## State
var _current_channel: int = ChatService.Channel.SAY
var _is_visible: bool = true
var _max_messages: int = 100
var _message_count: int = 0

## Channel tabs
var _tabs: HBoxContainer
var _tab_buttons: Dictionary = {}

## Constants
const CHAT_WIDTH: int = 400
const CHAT_HEIGHT: int = 250
const INPUT_HEIGHT: int = 30

## Local player info
var _player_info_label: Label

func _ready() -> void:
	_setup_ui()
	_setup_accessibility()
	_connect_signals()

func _setup_accessibility() -> void:
	accessible_name = "Chat"
	accessible_description = "In-game chat panel. Press Enter to open chat input. Use channel tabs or dropdown to switch channels."

func update_accessibility_settings() -> void:
	# Update channel tabs
	if _tabs:
		for child in _tabs.get_children():
			if child is Button:
				child.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
				var scale = UIStyles.get_text_scale()
				var current_size := child.get_theme_font_size("font_size")
				if current_size > 0:
					child.add_theme_font_size_override("font_size", int(current_size * scale))
	
	# Update chat history
	if _chat_history:
		_chat_history.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
		var scale = UIStyles.get_text_scale()
		var current_size := _chat_history.get_theme_font_size("default_font_size")
		if current_size > 0:
			_chat_history.add_theme_font_size_override("default_font_size", int(current_size * scale))
	
	# Update chat input
	if _chat_input:
		_chat_input.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
		var scale = UIStyles.get_text_scale()
		var current_size := _chat_input.get_theme_font_size("font_size")
		if current_size > 0:
			_chat_input.add_theme_font_size_override("font_size", int(current_size * scale))

func _setup_ui() -> void:
	# Main container
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	vbox.offset_right = CHAT_WIDTH
	vbox.offset_bottom = CHAT_HEIGHT + INPUT_HEIGHT + 40
	add_child(vbox)

	# Channel tabs
	_tabs = HBoxContainer.new()
	_tabs.custom_minimum_size.y = 28
	_tabs.focus_mode = Control.FOCUS_ALL
	_tabs.accessible_name = "Chat Channel Tabs"
	_tabs.accessible_description = "Click to switch between chat channels: Say, Zone, Party, Guild, Whisper."
	_tabs.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
	vbox.add_child(_tabs)
	_create_channel_tabs()

	# Chat history (RichTextLabel for colorized messages)
	_chat_history = RichTextLabel.new()
	_chat_history.custom_minimum_size.y = CHAT_HEIGHT
	_chat_history.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_history.bbcode_enabled = true
	_chat_history.scroll_following = true
	_chat_history.modulate = Color(1, 1, 1, 0.9)
	_chat_history.add_theme_color_override("default_color", UIStyles.COLORS.text_primary)
	_chat_history.meta_underlined = false
	_chat_history.focus_mode = Control.FOCUS_ALL
	_chat_history.accessible_name = "Chat History"
	_chat_history.accessible_description = "Displays chat messages. Use arrow keys to scroll through history."
	_chat_history.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
	vbox.add_child(_chat_history)

	# Input container
	var input_container := HBoxContainer.new()
	input_container.custom_minimum_size.y = INPUT_HEIGHT
	vbox.add_child(input_container)

	# Channel selector dropdown
	_channel_selector = OptionButton.new()
	_channel_selector.custom_minimum_size.x = 70
	_channel_selector.focus_mode = Control.FOCUS_ALL
	_channel_selector.accessible_name = "Channel Selector"
	_channel_selector.accessible_description = "Select the chat channel to send messages to."
	_channel_selector.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
	_populate_channel_dropdown()
	_channel_selector.item_selected.connect(_on_channel_selected)
	input_container.add_child(_channel_selector)

	# Chat input
	_chat_input = LineEdit.new()
	_chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_input.placeholder_text = "Press Enter to chat..."
	_chat_input.max_length = ChatService.MAX_MESSAGE_LENGTH
	_chat_input.focus_mode = Control.FOCUS_ALL
	_chat_input.accessible_name = "Chat Input"
	_chat_input.accessible_description = "Type your message and press Enter to send. Press Escape to cancel."
	_chat_input.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
	_chat_input.text_submitted.connect(_on_message_submitted)
	input_container.add_child(_chat_input)

	# Set initial channel
	_set_active_channel(ChatService.Channel.SAY)

func _create_channel_tabs() -> void:
	# Create tabs for common channels
	var channels := [
		{"id": ChatService.Channel.SAY, "name": "Say", "color": UIStyles.COLORS.text_primary},
		{"id": ChatService.Channel.ZONE, "name": "Zone", "color": Color(0.0, 1.0, 0.0)},
		{"id": ChatService.Channel.PARTY, "name": "Party", "color": Color(0.0, 1.0, 0.53)},
		{"id": ChatService.Channel.GUILD, "name": "Guild", "color": Color(1.0, 0.67, 0.0)},
		{"id": ChatService.Channel.WHISPER, "name": "Whisper", "color": Color(1.0, 0.6, 1.0)},
	]

	for ch in channels:
		var btn := Button.new()
		btn.text = ch.name
		btn.add_theme_color_override("font_color", ch.color)
		btn.add_theme_color_override("font_hover_color", Color(1, 1, 1))
		btn.custom_minimum_size.x = 60
		btn.toggle_mode = true
		btn.button_pressed = false
		btn.focus_mode = Control.FOCUS_ALL
		btn.accessible_name = "Chat Channel: %s" % ch.name
		btn.accessible_description = "Switch to %s channel." % ch.name
		btn.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
		btn.pressed.connect(_on_tab_clicked.bind(ch.id))
		_tabs.add_child(btn)
		_tab_buttons[ch.id] = btn

func _populate_channel_dropdown() -> void:
	_channel_selector.clear()
	_channel_selector.add_item("Say", ChatService.Channel.SAY)
	_channel_selector.add_item("Zone", ChatService.Channel.ZONE)
	_channel_selector.add_item("Party", ChatService.Channel.PARTY)
	_channel_selector.add_item("Guild", ChatService.Channel.GUILD)
	_channel_selector.add_item("Whisper", ChatService.Channel.WHISPER)
	_channel_selector.add_item("Trade", ChatService.Channel.TRADE)
	_channel_selector.add_item("Yell", ChatService.Channel.YELL)

func _connect_signals() -> void:
	if ChatService:
		ChatService.message_received.connect(_on_chat_message)

	# System messages on startup
	add_system_message("Chat loaded. Press Enter to chat, click tabs to switch channels.")

func _on_tab_clicked(channel: int) -> void:
	_set_active_channel(channel)

func _on_channel_selected(index: int) -> void:
	var channel: int = _channel_selector.get_item_id(index)
	_set_active_channel(channel)

func _set_active_channel(channel: int) -> void:
	_current_channel = channel

	# Update tab buttons
	for ch_id in _tab_buttons:
		var btn: Button = _tab_buttons[ch_id]
		btn.button_pressed = (ch_id == channel)

	# Update dropdown
	for i in range(_channel_selector.item_count):
		if _channel_selector.get_item_id(i) == channel:
			_channel_selector.selected = i
			break

	# Update player info channel label
	if _player_info_label:
		_player_info_label.text = ChatService.get_channel_name(channel)

	# Update input placeholder
	var channel_name := ChatService.get_channel_name(channel)
	_chat_input.placeholder_text = "Chat in %s..." % channel_name

func _on_message_submitted(text: String) -> void:
	if text.is_empty():
		return

	# Handle commands
	if text.begins_with("/"):
		_handle_command(text)
		return

	# Send via ChatService
	var local_player_id := ""
	if PlayerManager and PlayerManager.local_player:
		local_player_id = str(PlayerManager.local_player.entity_id)

	var success := ChatService.send_message(
		local_player_id,
		_current_channel,
		text
	)

	if not success:
		# Rate limited or blocked
		_chat_input.clear()

func _handle_command(text: String) -> void:
	var parts := text.substr(1).split(" ")
	var cmd: String = parts[0].to_lower()
	var args: String = " ".join(parts.slice(1)) if parts.size() > 1 else ""

	match cmd:
		"w", "whisper":
			var target_and_msg := args.split(" ", true, 1)
			if target_and_msg.size() >= 2:
				# /w PlayerName message
				var target_name: String = target_and_msg[0]
				var msg: String = target_and_msg[1]
				ChatService.send_whisper("", target_name, msg)
			else:
				add_system_message("Usage: /w PlayerName message")
		"r", "reply":
			# Reply to last whisper
			ChatService.send_whisper_to_last("", args)
		"party":
			add_system_message("Party commands: /invite, /leave, /kick")
		"guild":
			add_system_message("Guild commands: /g message")
		"me":
			# Emote
			if not args.is_empty():
				var local_id := str(PlayerManager.get_local_player_id()) if PlayerManager else ""
				ChatService.send_emote(local_id, args)
		_:
			add_system_message("Unknown command: %s" % cmd)

func _on_chat_message(sender_id: String, channel: int, message: String, targets: Array) -> void:
	add_message(sender_id, channel, message)

func add_message(sender_id: String, channel: int, message: String) -> void:
	var sender_name := _get_sender_name(sender_id)
	var formatted := ChatService.format_message(sender_id, channel, message, sender_name)
	_chat_history.append_text(formatted + "\n")
	_message_count += 1

	# Trim old messages
	if _message_count > _max_messages:
		_trim_history()

func add_system_message(message: String) -> void:
	var formatted := "[color=%s][System]:[/color] %s" % [UIStyles.COLORS.warning.to_html(), message]
	_chat_history.append_text(formatted + "\n")
	_message_count += 1

func _get_sender_name(sender_id: String) -> String:
	var name: String = sender_id
	if EntityService:
		var entity = EntityService.get_entity(sender_id)
		if entity and entity.has("character_data"):
			var char_data = entity.character_data
			if char_data.has("player_name"):
				name = char_data.player_name
	return name

func _trim_history() -> void:
	# Remove first quarter of messages
	var text: String = _chat_history.text
	var lines := text.split("\n")
	if lines.size() > _max_messages / 2:
		var new_lines := lines.slice(lines.size() - _max_messages / 2)
		_chat_history.clear()
		_chat_history.append_text("\n".join(new_lines))
		_message_count = new_lines.size()

func _add_player_info_row(vbox: VBoxContainer) -> void:
	# Player info header
	var player_header := HBoxContainer.new()
	player_header.custom_minimum_size.y = 24
	_add_player_info_header(player_header)
	vbox.add_child(player_header)

func _add_player_info_header(header: HBoxContainer) -> void:
	# Player name
	var name_label := Label.new()
	name_label.text = "[Player]"
	name_label.add_theme_color_override("font_color", UIStyles.COLORS.text_primary)
	name_label.add_theme_font_size_override("font_size", 11)
	header.add_child(name_label)

	# Separator
	var sep := Label.new()
	sep.text = " | "
	sep.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	header.add_child(sep)

	# Channel indicator
	var channel_label := Label.new()
	channel_label.text = "Say"
	channel_label.name = "ChannelLabel"
	channel_label.add_theme_color_override("font_color", UIStyles.COLORS.info)
	channel_label.add_theme_font_size_override("font_size", 11)
	header.add_child(channel_label)

	_player_info_label = channel_label

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	# Admin button (if GM/admin)
	if _is_admin():
		var admin_btn := Button.new()
		admin_btn.text = "[Admin]"
		admin_btn.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
		admin_btn.add_theme_font_size_override("font_size", 10)
		admin_btn.focus_mode = Control.FOCUS_ALL
		admin_btn.accessible_name = "Admin Shell"
		admin_btn.accessible_description = "Open the admin command shell."
		admin_btn.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
		admin_btn.pressed.connect(_toggle_admin_shell)
		header.add_child(admin_btn)

func _is_admin() -> bool:
	var local_id := str(PlayerManager.get_local_player_id()) if PlayerManager else ""
	if local_id.is_empty():
		return false
	if PermissionManager:
		return PermissionManager.is_admin(local_id) or PermissionManager.is_gm(local_id)
	return false

func _toggle_admin_shell() -> void:
	if has_node("AdminPanel"):
		var panel: Control = get_node("AdminPanel")
		panel.visible = not panel.visible
	else:
		_create_admin_shell()

func _create_admin_shell() -> void:
	var panel := PanelContainer.new()
	panel.name = "AdminPanel"
	panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.offset_left = -320
	panel.offset_top = 0
	panel.offset_right = -10
	panel.offset_bottom = 200
	panel.focus_mode = Control.FOCUS_ALL
	panel.accessible_name = "Admin Shell"
	panel.accessible_description = "Administrative command shell. Type 'help' for available commands."

	var style := UIStyles.create_panel_style(
		UIStyles.COLORS.background_dark,
		UIStyles.COLORS.accent_gold,
		2,
		4
	)
	panel.add_theme_stylebox_override("panel", style)
	panel.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
	add_child(panel)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "ADMIN SHELL"
	title.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	title.add_theme_font_size_override("font_size", 12)
	vbox.add_child(title)

	# Admin input
	var admin_input := LineEdit.new()
	admin_input.name = "AdminInput"
	admin_input.placeholder_text = "> admin command..."
	admin_input.focus_mode = Control.FOCUS_ALL
	admin_input.accessible_name = "Admin Command Input"
	admin_input.accessible_description = "Type admin commands here. Press Enter to execute."
	admin_input.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
	admin_input.text_submitted.connect(_on_admin_command)
	vbox.add_child(admin_input)

	# Admin output
	var admin_output := RichTextLabel.new()
	admin_output.name = "AdminOutput"
	admin_output.custom_minimum_size.y = 120
	admin_output.bbcode_enabled = true
	admin_output.add_theme_color_override("default_color", UIStyles.COLORS.text_primary)
	admin_output.focus_mode = Control.FOCUS_ALL
	admin_output.accessible_name = "Admin Command Output"
	admin_output.accessible_description = "Displays the results of admin commands."
	admin_output.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
	vbox.add_child(admin_output)

	# Welcome message
	var welcome := "[color=%s]Admin shell loaded. Type 'help' for commands.[/color]" % UIStyles.COLORS.warning.to_html()
	admin_output.append_text(welcome)

func _on_admin_command(text: String) -> void:
	var admin_input: LineEdit = get_node_or_null("AdminPanel/AdminInput")
	var admin_output: RichTextLabel = get_node_or_null("AdminPanel/AdminOutput")
	if not admin_input or not admin_output:
		return

	admin_input.clear()

	# Parse command
	var parts := text.split(" ")
	var cmd: String = parts[0].to_lower()
	var args := " ".join(parts.slice(1)) if parts.size() > 1 else ""

	var result := ""
	match cmd:
		"help":
			result = "[color=%s]Commands:[/color]\n" % UIStyles.COLORS.info.to_html()
			result += "  /announce <msg> - Server announcement\n"
			result += "  /kick <player> [reason] - Kick player\n"
			result += "  /ban <player> [reason] - Ban player\n"
			result += "  /mute <player> [duration] - Mute player\n"
			result += "  /teleport <x> <y> <z> - Teleport\n"
			result += "  /spawn <entity> [count] - Spawn entity\n"
			result += "  /heal <player> - Heal player\n"
			result += "  /stats <player> - View player stats\n"
			result += "  /online - List online players\n"
			result += "  /clear - Clear this output"
		"announce":
			if args.is_empty():
				result = "[color=%s]Usage: /announce <message>[/color]" % UIStyles.COLORS.error.to_html()
			else:
				NotificationService.broadcast_alert(args, [NotificationService.AlertScope.server_wide()], NotificationService.NotificationType.ALERT)
				result = "[color=%s]Announcement sent:[/color] %s" % [UIStyles.COLORS.success.to_html(), _esc(args)]
		"kick":
			if args.is_empty():
				result = "[color=%s]Usage: /kick <player> [reason][/color]" % UIStyles.COLORS.error.to_html()
			else:
				var target: String = args.split(" ")[0]
				var reason: String = " ".join(args.split(" ").slice(1)) if args.split(" ").size() > 1 else "No reason"
				AdminCommands.kick_player(target, reason)
				result = "[color=%s]Kicked:[/color] %s (reason: %s)" % [UIStyles.COLORS.warning.to_html(), _esc(target), _esc(reason)]
		"ban":
			if args.is_empty():
				result = "[color=%s]Usage: /ban <player> [reason][/color]" % UIStyles.COLORS.error.to_html()
			else:
				var target: String = args.split(" ")[0]
				var reason: String = " ".join(args.split(" ").slice(1)) if args.split(" ").size() > 1 else "Banned by admin"
				AdminCommands.ban_player(target, reason)
				result = "[color=%s]Banned:[/color] %s" % [UIStyles.COLORS.error.to_html(), _esc(target)]
		"mute":
			if args.is_empty():
				result = "[color=%s]Usage: /mute <player> [duration][/color]" % UIStyles.COLORS.error.to_html()
			else:
				var target: String = args.split(" ")[0]
				var duration: String = args.split(" ")[1] if args.split(" ").size() > 1 else "60"
				SecurityService.restrict_player(target, "chat", int(duration))
				result = "[color=%s]Muted:[/color] %s for %s seconds" % [UIStyles.COLORS.warning.to_html(), _esc(target), _esc(duration)]
		"teleport", "tp":
			var coords: PackedStringArray = args.split(" ")
			if coords.size() >= 3:
				var pos := Vector3(float(coords[0]), float(coords[1]), float(coords[2]))
				if PlayerManager:
					var local_player = PlayerManager.local_player
					if local_player:
						local_player.global_position = pos
					result = "[color=%s]Teleported:[/color] to %s" % [UIStyles.COLORS.success.to_html(), _esc(str(pos))]
				else:
					result = "[color=%s]Usage: /tp <x> <y> <z>[/color]" % UIStyles.COLORS.error.to_html()
		"spawn":
			if args.is_empty():
				result = "[color=%s]Usage: /spawn <entity_type> [count][/color]" % UIStyles.COLORS.error.to_html()
			else:
				result = "[color=%s]Spawn:[/color] %s (use admin console for full spawn)" % [UIStyles.COLORS.info.to_html(), _esc(args)]
		"heal":
			if PlayerManager:
				var local_player = PlayerManager.local_player
				if local_player and local_player.has("health_component"):
					local_player.health_component.current_health = local_player.health_component.max_health
					result = "[color=%s]Healed:[/color] You are now at full health" % UIStyles.COLORS.success.to_html()
		"stats":
			if args.is_empty():
				result = "[color=%s]Usage: /stats <player_name>[/color]" % UIStyles.COLORS.error.to_html()
			else:
				result = "[color=%s]Stats:[/color] Use character panel for detailed stats" % UIStyles.COLORS.info.to_html()
		"online":
			result = "[color=%s]Online:[/color] %d players" % [UIStyles.COLORS.info.to_html(), EntityService.get_player_count() if EntityService else 0]
		"clear":
			admin_output.clear()
			return
		_:
			result = "[color=%s]Unknown command:[/color] %s (type 'help')" % [UIStyles.COLORS.error.to_html(), _esc(cmd)]

	admin_output.append_text("\n> " + _esc(text))
	admin_output.append_text("\n" + result)

func focus_input() -> void:
	_chat_input.grab_focus()

func clear_chat() -> void:
	_chat_history.clear()
	_message_count = 0
