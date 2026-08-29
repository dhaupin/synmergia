## MainMenu - Main menu controller
extends Control

@onready var play_button: Button = $MenuButtons/PlayButton
@onready var settings_button: Button = $MenuButtons/SettingsButton
@onready var quit_button: Button = $MenuButtons/QuitButton

func _ready() -> void:
	GameLogger.info("Main menu loaded")
	
	# Hide quit button on mobile/web
	if DisplayServer.get_name() == "Android" or OS.has_feature("web"):
		quit_button.visible = false

func _on_play_pressed() -> void:
	GameLogger.info("Play button pressed")
	GameManager.change_state(GameManager.GameState.CHARACTER_SELECT)

func _on_settings_pressed() -> void:
	GameLogger.info("Settings button pressed")
	# Open settings menu
	pass

func _on_quit_pressed() -> void:
	GameLogger.info("Quit button pressed")
	get_tree().quit()
