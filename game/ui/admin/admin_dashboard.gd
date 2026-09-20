## AdminDashboard - In-game admin UI panel
## Uses UIStyles for consistent theming
## Provides visual interface for admin commands and player management
extends "res://ui/components/ui_panel.gd"
class_name AdminDashboard
const AdminShell = preload("res://core/admin/admin_shell.gd")


## Main container
var _main_vbox: VBoxContainer
var _tab_container: TabContainer
var _terminal_output: RichTextLabel
var _command_input: LineEdit
var _history_index: int = -1

## Player list
var _player_list: ItemList
var _selected_player: String = ""

## Admin shell reference
var _shell: AdminShell
var _admin_id: String = ""


## Escape [ and ] for BBCode safety
static func _esc(text: String) -> String:
	return text.replace("[", "[lb]").replace("]", "[rb]")


func _ready() -> void:
	# Get or create admin shell
	_shell = AdminShell.new()
	add_child(_shell)
	_shell.command_executed.connect(_on_command_executed)

	# Build the panel UI first: _refresh_player_list clears _player_list,
	# which only exists after _setup_panel has run.
	_setup_panel()
	_refresh_player_list()
	_bind_admin_signals()

	# Auto-refresh player list
	var timer := Timer.new()
	timer.wait_time = 5.0
	timer.timeout.connect(_refresh_player_list)
	add_child(timer)
	timer.start()

func _setup_panel() -> void:

	# Create main container
	_main_vbox = VBoxContainer.new()
	_main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	_main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_main_vbox)

	# Title bar
	var title_bar := HBoxContainer.new()
	title_bar.custom_minimum_size.y = 40
	var title := Label.new()
	title.text = " Admin Dashboard"
	title.add_theme_color_override("font_color", UIStyles.COLORS.text_primary)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_bar.add_child(title)

	var close_btn := Button.new()
	close_btn.text = ""
	close_btn.pressed.connect(close)
	title_bar.add_child(close_btn)
	_main_vbox.add_child(title_bar)

	# Tab container
	_tab_container = TabContainer.new()
	_tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tab_container.tab_changed.connect(_on_tab_changed)
	_main_vbox.add_child(_tab_container)

	# Create tabs
	_create_shell_tab()
	_create_players_tab()
	_create_restrictions_tab()
	_create_stats_tab()
	_create_settings_tab()

	# Status bar
	var status_bar := HBoxContainer.new()
	status_bar.custom_minimum_size.y = 24
	var status := Label.new()
	status.text = " Admin Shell Ready"
	status.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	status_bar.add_child(status)
	_main_vbox.add_child(status_bar)

func _create_shell_tab() -> void:
	var tab := VBoxContainer.new()
	_tab_container.add_child(tab)
	_tab_container.set_tab_title(_tab_container.get_child_count() - 1, " Shell")

	# Terminal output
	_terminal_output = RichTextLabel.new()
	_terminal_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_terminal_output.bbcode_enabled = true
	_terminal_output.scroll_following = true
	_terminal_output.add_theme_color_override("default_color", Color(0.9, 0.9, 0.9))
	_terminal_output.add_theme_color_override("selection_color", Color(0.3, 0.5, 0.7))
	_terminal_output.add_theme_constant_override("line_separation", 2)
	tab.add_child(_terminal_output)

	# Initial message
	_terminal_output.append_text("[color=cyan]Welcome to Admin Shell[/color]\n")
	_terminal_output.append_text("[color=gray]Type 'help' for commands, 'toggles' for settings[/color]\n\n")

	# Command input
	var input_container := HBoxContainer.new()
	input_container.custom_minimum_size.y = 32

	var prompt := Label.new()
	prompt.text = "> "
	prompt.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))
	input_container.add_child(prompt)

	_command_input = LineEdit.new()
	_command_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_command_input.text_submitted.connect(_on_command_submitted)
	_command_input.gui_input.connect(_on_input_gui_input)
	input_container.add_child(_command_input)

	tab.add_child(input_container)

func _create_players_tab() -> void:
	var tab := VBoxContainer.new()
	_tab_container.add_child(tab)
	_tab_container.set_tab_title(_tab_container.get_child_count() - 1, " Players")

	# Toolbar
	var toolbar := HBoxContainer.new()
	toolbar.custom_minimum_size.y = 36

	var refresh_btn := Button.new()
	refresh_btn.text = "refresh Refresh"
	refresh_btn.pressed.connect(_refresh_player_list)
	toolbar.add_child(refresh_btn)

	var search_input := LineEdit.new()
	search_input.placeholder_text = "Search players..."
	search_input.text_changed.connect(_on_player_search)
	toolbar.add_child(search_input)
	search_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	tab.add_child(toolbar)

	# Player list
	_player_list = ItemList.new()
	_player_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_player_list.item_selected.connect(_on_player_selected)
	tab.add_child(_player_list)

	# Actions for selected player
	var actions := HBoxContainer.new()
	actions.custom_minimum_size.y = 40

	var lookup_btn := Button.new()
	lookup_btn.text = " Lookup"
	lookup_btn.pressed.connect(_lookup_selected_player)
	actions.add_child(lookup_btn)

	var mute_btn := Button.new()
	mute_btn.text = " Mute"
	mute_btn.pressed.connect(_mute_selected_player)
	actions.add_child(mute_btn)

	var kick_btn := Button.new()
	kick_btn.text = " Kick"
	kick_btn.pressed.connect(_kick_selected_player)
	actions.add_child(kick_btn)

	var restrict_btn := Button.new()
	restrict_btn.text = " Restrict"
	restrict_btn.pressed.connect(_restrict_selected_player)
	actions.add_child(restrict_btn)

	tab.add_child(actions)

func _create_restrictions_tab() -> void:
	var tab := VBoxContainer.new()
	_tab_container.add_child(tab)
	_tab_container.set_tab_title(_tab_container.get_child_count() - 1, " Restrictions")

	# Toolbar
	var toolbar := HBoxContainer.new()
	toolbar.custom_minimum_size.y = 36

	var view_all_btn := Button.new()
	view_all_btn.text = "View All Restrictions"
	view_all_btn.pressed.connect(func(): _shell.execute("restrictions", _admin_id))
	toolbar.add_child(view_all_btn)

	toolbar.add_child(Control.new())  # Spacer

	tab.add_child(toolbar)

	# Restrictions display (rich text)
	var restrictions_output := RichTextLabel.new()
	restrictions_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	restrictions_output.bbcode_enabled = true
	restrictions_output.add_theme_color_override("default_color", Color(0.9, 0.9, 0.9))
	restrictions_output.name = "RestrictionsOutput"
	tab.add_child(restrictions_output)

	# Quick actions
	var quick_actions := HBoxContainer.new()
	quick_actions.custom_minimum_size.y = 40

	var unmute_all_btn := Button.new()
	unmute_all_btn.text = " Unmute All"
	unmute_all_btn.pressed.connect(_unmute_all_players)
	quick_actions.add_child(unmute_all_btn)

	tab.add_child(quick_actions)

func _create_stats_tab() -> void:
	var tab := VBoxContainer.new()
	_tab_container.add_child(tab)
	_tab_container.set_tab_title(_tab_container.get_child_count() - 1, " Stats")

	# Stats output
	var stats_output := RichTextLabel.new()
	stats_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stats_output.bbcode_enabled = true
	stats_output.add_theme_color_override("default_color", Color(0.9, 0.9, 0.9))
	stats_output.name = "StatsOutput"
	tab.add_child(stats_output)

	# Refresh button
	var refresh_btn := Button.new()
	refresh_btn.text = "refresh Refresh Stats"
	refresh_btn.pressed.connect(func(): _shell.execute("stats", _admin_id))
	refresh_btn.custom_minimum_size.y = 32
	tab.add_child(refresh_btn)

func _create_settings_tab() -> void:
	var tab := ScrollContainer.new()
	_tab_container.add_child(tab)
	_tab_container.set_tab_title(_tab_container.get_child_count() - 1, " Settings")

	var content := VBoxContainer.new()
	content.custom_minimum_size.x = 400
	tab.add_child(content)

	# Section: Security Alerts
	var section1 := _create_settings_section("Security/QoS Alerts")
	content.add_child(section1)

	var alerts_on := CheckBox.new()
	alerts_on.button_pressed = GameConfig.Security.ENABLE_SECURITY_ALERTS
	alerts_on.text = "Enable Security Alerts to Players"
	section1.add_child(alerts_on)

	var rate_alerts := CheckBox.new()
	rate_alerts.button_pressed = GameConfig.Security.ALERT_ON_RATE_LIMIT
	rate_alerts.text = "Alert on Rate Limit"
	section1.add_child(rate_alerts)

	var restrict_alerts := CheckBox.new()
	restrict_alerts.button_pressed = GameConfig.Security.ALERT_ON_RESTRICTION
	restrict_alerts.text = "Alert on Restriction"
	section1.add_child(restrict_alerts)

	var exploit_alerts := CheckBox.new()
	exploit_alerts.button_pressed = GameConfig.Security.ALERT_ON_EXPLOIT_DETECTED
	exploit_alerts.text = "Alert on Exploit Detected (NOT RECOMMENDED)"
	section1.add_child(exploit_alerts)

	# Section: Debug
	var section2 := _create_settings_section("Debug")
	content.add_child(section2)

	var debug_logging := CheckBox.new()
	debug_logging.button_pressed = GameConfig.Debug.ENABLE_DEBUG_LOGGING
	debug_logging.text = "Enable Debug Logging"
	section2.add_child(debug_logging)

func _create_settings_section(title: String) -> VBoxContainer:
	var section := VBoxContainer.new()

	var label := Label.new()
	label.text = title
	label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3))
	section.add_child(label)

	var separator := HSeparator.new()
	section.add_child(separator)

	return section

## ============================================================================
## EVENT HANDLERS
## ============================================================================

func _on_command_submitted(text: String) -> void:
	if text.strip_edges() == "":
		return

	_terminal_output.append_text("[color=green]>[/color] %s\n" % _esc(text))
	_command_input.clear()

	var result := _shell.execute(text, _admin_id)

	if result.output != "":
		_terminal_output.append_text(_esc(result.output) + "\n")
	if result.error != "":
		_terminal_output.append_text("[color=red]Error:[/color] %s\n" % _esc(result.error))
	if result.success:
		_terminal_output.append_text("\n")

func _on_input_gui_input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.pressed:
			match event.keycode:
				KEY_UP:
					_navigate_history(-1)
				KEY_DOWN:
					_navigate_history(1)
				KEY_TAB:
					_autocomplete()

func _on_tab_changed(tab_index: int) -> void:
	var tab_name := _tab_container.get_child(tab_index).name

	match tab_name:
		"Restrictions":
			_shell.execute("restrictions", _admin_id)
		"Stats":
			_shell.execute("stats", _admin_id)

func _on_command_executed(cmd: String, result, executor_id: String) -> void:
	# Update relevant tabs based on command output
	var current_tab := _tab_container.get_child(_tab_container.current_tab)

	if current_tab.has_node("RestrictionsOutput"):
		var output: RichTextLabel = current_tab.get_node("RestrictionsOutput")
		if result.output != "":
			output.clear()
			output.append_text(result.output)

	if current_tab.has_node("StatsOutput"):
		var output: RichTextLabel = current_tab.get_node("StatsOutput")
		if result.output != "":
			output.clear()
			output.append_text(result.output)

func _on_player_selected(index: int) -> void:
	if index >= 0 and index < _player_list.get_item_count():
		_selected_player = _player_list.get_item_text(index)

func _on_player_search(text: String) -> void:
	_refresh_player_list(text)

## ============================================================================
## ACTIONS
## ============================================================================


func _bind_admin_signals() -> void:
	if AutoResponseService:
		if AutoResponseService.has_signal("action_taken") and not AutoResponseService.action_taken.is_connected(_on_auto_response_action):
			AutoResponseService.action_taken.connect(_on_auto_response_action)
		if AutoResponseService.has_signal("player_warned") and not AutoResponseService.player_warned.is_connected(_on_auto_response_warn):
			AutoResponseService.player_warned.connect(_on_auto_response_warn)


func _on_auto_response_action(player_id: String, action: int, exploit_type: String, reason: String) -> void:
	if not _terminal_output:
		return
	var action_names := ["WARN", "MUTE", "RESTRICT", "KICK", "BAN"]
	var action_name: String = action_names[action] if action < action_names.size() else "UNKNOWN"
	_terminal_output.append_text("[color=red]>[/color] Auto-action: %s %s (reason: %s)\n" % [action_name, _esc(player_id), _esc(exploit_type)])


func _on_auto_response_warn(player_id: String, exploit_type: String, message: String) -> void:
	if not _terminal_output:
		return
	_terminal_output.append_text("[color=yellow]>[/color] Auto-warn: %s -- %s\n" % [_esc(player_id), _esc(exploit_type)])


func _refresh_player_list(filter: String = "") -> void:
	_player_list.clear()

	var players := _shell.execute("players " + filter, _admin_id)
	var lines := players.output.split("\n")

	for line in lines:
		if line.begins_with("  ") and not line.contains("Total:"):
			# Extract player ID
			var clean := line.strip_edges()
			# Remove color codes and restrictions
			clean = clean.replace("[color=red](MUTED)[/color]", "").strip_edges()
			if clean != "":
				_player_list.add_item(clean)

func _lookup_selected_player() -> void:
	if _selected_player == "":
		return
	_tab_container.current_tab = 0  # Switch to shell tab
	_shell.execute("lookup " + _selected_player, _admin_id)
	_terminal_output.append_text(_shell.execute("lookup " + _selected_player, _admin_id).output + "\n")

func _mute_selected_player() -> void:
	if _selected_player == "":
		return
	_shell.execute("mute " + _selected_player + " 300", _admin_id)
	_refresh_player_list()

func _kick_selected_player() -> void:
	if _selected_player == "":
		return
	_shell.execute("kick " + _selected_player + " Kicked by admin", _admin_id)
	_refresh_player_list()

func _restrict_selected_player() -> void:
	if _selected_player == "":
		return
	_shell.execute("restrict " + _selected_player + " all 600", _admin_id)
	_refresh_player_list()

func _unmute_all_players() -> void:
	var result := _shell.execute("restrictions", _admin_id)
	# Parse and unmute all muted players
	var lines := result.output.split("\n")
	for line in lines:
		if "(MUTED)" in line:
			var player := line.strip_edges().replace("(MUTED)", "").strip_edges()
			_shell.execute("unmute " + player, _admin_id)
	_refresh_player_list()

## ============================================================================
## SHELL HELPERS
## ============================================================================

func _navigate_history(direction: int) -> void:
	if _shell.history.is_empty():
		return

	_history_index += direction
	_history_index = clampi(_history_index, -1, _shell.history.size() - 1)

	if _history_index == -1:
		_command_input.clear()
	else:
		_command_input.text = _shell.history[_history_index]
		_command_input.caret_position = _command_input.text.length()

func _autocomplete() -> void:
	var partial := _command_input.text
	var suggestions := _shell.get_suggestions(partial, _admin_id)

	if suggestions.size() == 1:
		_command_input.text = suggestions[0] + " "
		_command_input.caret_position = _command_input.text.length()
	elif suggestions.size() > 1:
		_terminal_output.append_text("[color=cyan]Completions:[/color] " + ", ".join(suggestions) + "\n")

## ============================================================================
## PUBLIC API
## ============================================================================

func set_admin_id(admin_id: String) -> void:
	# Validate admin has proper permissions
	if PermissionManager:
		if not PermissionManager.has_permission(admin_id, PermissionManager.Level.MOD):
			GameLog.warn("AdminDashboard: Access denied for %s - insufficient permissions" % admin_id)
			_admin_id = ""
			return
		if not PermissionManager.has_permission(admin_id, PermissionManager.Level.ADMIN):
			# Show MOD-level warning in UI
			_show_permission_warning()

	_admin_id = admin_id
	GameLog.info("AdminDashboard: Admin %s connected" % admin_id)

	# Connect to PermissionManager signals for real-time updates
	if PermissionManager:
		PermissionManager.admin_action.connect(_on_admin_action)

func execute_command(cmd: String) -> void:
	_on_command_submitted(cmd)

func _show_permission_warning() -> void:
	if _terminal_output:
		_terminal_output.append_text("\n[color=yellow] WARNING: MOD-LEVEL ACCESS[/color]\n")
		_terminal_output.append_text("Some features are restricted. ADMIN level required for:\n")
		_terminal_output.append_text("  - ban, restrict (non-chat), config changes\n")
		_terminal_output.append_text("  - View audit log\n\n")

func _on_admin_action(entry) -> void:
	# Log admin actions in real-time
	if _terminal_output and entry.admin_id == _admin_id:
		_terminal_output.append_text("[color=cyan]>[/color] Your action: %s\n" % entry.action)

## Check if user has permission level
func has_permission(required_level: int) -> bool:
	if _admin_id == "":
		return false
	if PermissionManager:
		return PermissionManager.has_permission(_admin_id, required_level)
	return false

## Check if user is admin level
func is_admin() -> bool:
	return has_permission(PermissionManager.Level.ADMIN if PermissionManager else 50)

## Check if user is moderator level
func is_moderator() -> bool:
	return has_permission(PermissionManager.Level.MOD if PermissionManager else 10)
