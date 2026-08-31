## MainMenu - Main menu controller with UIStyles integration
extends Control

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
	print("Play button pressed")
	if GameManager:
		GameManager.change_state(GameManager.GameState.CHARACTER_SELECT)

func _on_settings_pressed() -> void:
	print("Settings button pressed")
	UIStyles.show_notification("Settings coming soon", true, 2.0)

func _on_quit_pressed() -> void:
	print("Quit button pressed")
	get_tree().quit()
