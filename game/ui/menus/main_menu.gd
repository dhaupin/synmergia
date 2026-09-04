## MainMenu - Main menu controller with UIStyles integration
extends Control
const UIStyles = preload("res://ui/components/ui_styles.gd")


@onready var play_button: Button = $MenuButtons/PlayButton
@onready var settings_button: Button = $MenuButtons/SettingsButton
@onready var quit_button: Button = $MenuButtons/QuitButton

func _ready() -> void:
	print("Main menu loaded")
	_apply_styles()

	# Hide quit button on mobile/web
	if DisplayServer.get_name() == "Android" or OS.has_feature("web"):
		quit_button.visible = false

func _apply_styles() -> void:
	var button_styles := UIStyles.create_button_style()
	UIStyles.apply_button_styles(play_button, button_styles)
	UIStyles.apply_button_styles(settings_button, button_styles)
	UIStyles.apply_button_styles(quit_button, button_styles)

	var title: Label = $Title
	if title:
		title.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)

	var subtitle: Label = $Subtitle
	if subtitle:
		subtitle.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)

func _on_play_pressed() -> void:
	print("[MENU] PlayButton pressed")
	if DebugOverlay:
		DebugOverlay.log_click("PlayButton", "goto_login", true)
	# Send the player to login first; on success they land in the
	# character lobby, which is the canonical entry point to the world.
	if GameManager:
		if LoginService and LoginService.is_logged_in():
			GameManager.change_state(GameManager.GameState.LOBBY)
		else:
			GameManager.change_state(GameManager.GameState.LOGIN)

func _on_settings_pressed() -> void:
	print("[MENU] SettingsButton pressed")
	if DebugOverlay:
		DebugOverlay.log_click("SettingsButton", "open_settings", true)
	_open_settings_panel()

func _open_settings_panel() -> void:
	var player_id: String = ""
	if LoginService and LoginService.is_logged_in():
		player_id = LoginService.get_current_account_id()
	# Look for an existing SettingsPanel on the HUD layer first.
	var hud: Node = get_tree().root.get_node_or_null("HudLayer")
	if hud and hud.has_node("SettingsPanel"):
		var panel: Node = hud.get_node("SettingsPanel")
		if panel and panel.has_method("open"):
			panel.open(player_id)
			return
	# Otherwise instantiate a fresh SettingsPanel overlay.
	var script: GDScript = load("res://ui/components/settings_panel.gd")
	if not script:
		UIStyles.show_notification("Settings unavailable", true, 2.0)
		return
	var panel2: Control = script.new()
	panel2.name = "SettingsPanelOverlay"
	get_tree().root.add_child.call_deferred(panel2)
	if panel2.has_method("open"):
		panel2.call_deferred("open", player_id)

func _on_quit_pressed() -> void:
	print("Quit button pressed")
	get_tree().quit()
