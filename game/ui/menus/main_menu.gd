## MainMenu - Main menu controller with UIStyles integration
extends Control
const UIStyles = preload("res://ui/components/ui_styles.gd")


@onready var play_button: Button = $MenuButtons/PlayButton
@onready var quit_button: Button = $MenuButtons/QuitButton

func _ready() -> void:
	# print removed: print("Main menu loaded")
	_apply_styles()

	# Hide quit button on mobile/web
	if DisplayServer.get_name() == "Android" or OS.has_feature("web"):
		quit_button.visible = false

func _apply_styles() -> void:
	var button_styles := UIStyles.create_button_style()
	UIStyles.apply_button_styles(play_button, button_styles)
	UIStyles.apply_button_styles(quit_button, button_styles)

	var title: Label = $Title
	if title:
		title.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)

	var subtitle: Label = $Subtitle
	if subtitle:
		subtitle.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)

func _on_play_pressed() -> void:
	# print removed: print("[MENU] PlayButton pressed")
	if DebugOverlay:
		DebugOverlay.log_click("PlayButton", "goto_login", true)
	# Send the player to login first; on success they land in the
	# character lobby, which is the canonical entry point to the world.
	if GameManager:
		if LoginService and LoginService.is_logged_in():
			GameManager.change_state(GameManager.GameState.LOBBY)
		else:
			GameManager.change_state(GameManager.GameState.LOGIN)

func _on_quit_pressed() -> void:
	# print removed: print("Quit button pressed")
	get_tree().quit()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_TAB:
			var buttons := [play_button, quit_button]
			var current := get_viewport().gui_get_focus_owner()
			var idx := -1
			for i in range(buttons.size()):
				if buttons[i] == current:
					idx = i
					break
			if event.shift:
				idx = (idx - 1 + buttons.size()) % buttons.size()
			else:
				idx = (idx + 1) % buttons.size()
			buttons[idx].grab_focus()
