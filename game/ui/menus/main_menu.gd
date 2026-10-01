## MainMenu - Main menu controller with UIStyles integration
## Round-6 simplification: ONE button, "Start" (the old Account flow:
## login / register / guest -> lobby -> play). The separate "Play"
## button and its direct-to-character-select flow are gone -- one
## button, one flow, no dead paths (play-test round 6, item 6).
extends Control
const UIStyles = preload("res://ui/components/ui_styles.gd")
const Brand = preload("res://core/utils/branding.gd")


@onready var start_button: Button = $MenuButtons/StartButton
@onready var quit_button: Button = $MenuButtons/QuitButton

func _ready() -> void:
	_apply_styles()
	_apply_branding()

	# Hide quit button on mobile/web
	if DisplayServer.get_name() == "Android" or OS.has_feature("web"):
		quit_button.visible = false

func _apply_branding() -> void:
	# The horizontal lockup (emblem + SYNMERGIA banner) replaces the
	# text title when the logo pack is present; text stays as fallback.
	var logo: Texture2D = Brand.lockup() if Brand else null
	if logo == null:
		return
	var title: Label = $Title
	var subtitle: Label = $Subtitle
	if title:
		title.visible = false
	if subtitle:
		subtitle.visible = false
	var banner := TextureRect.new()
	banner.name = "LogoBanner"
	banner.texture = logo
	banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	banner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	banner.anchors_preset = Control.PRESET_TOP_WIDE
	banner.anchor_right = 1.0
	banner.offset_top = 90.0
	banner.offset_bottom = 330.0
	add_child(banner)
	move_child(banner, 1)  # just above Background

func _apply_styles() -> void:
	# Start is THE primary action (play-test round 8, item 2): it used
	# to render as a ~200x30 default-theme button under a huge logo --
	# invisible CTA. Big green fill, generous font, dark text.
	start_button.custom_minimum_size = Vector2(380, 76)
	UIStyles.apply_cta_button(start_button, 30)
	var button_styles := UIStyles.create_button_style()
	UIStyles.apply_button_styles(quit_button, button_styles)

	var title: Label = $Title
	if title:
		title.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)

	var subtitle: Label = $Subtitle
	if subtitle:
		subtitle.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)

func _on_start_pressed() -> void:
	if DebugOverlay:
		DebugOverlay.log_click("StartButton", "goto_login", true)
	# One flow: login / register / guest -> lobby (per-account character
	# list) -> play. The old Account path -- the only wired flow since
	# round 3, so nothing is lost by dropping Play.
	if GameManager:
		GameManager.change_state(GameManager.GameState.LOGIN)

func _on_quit_pressed() -> void:
	get_tree().quit()

func _open_settings_panel() -> void:
	# Lazily instantiate the shared settings panel over the menu.
	if _settings_panel != null and is_instance_valid(_settings_panel):
		_settings_panel.open()
		return
	var SettingsPanelScript = load("res://ui/components/settings_panel.gd")
	if SettingsPanelScript == null:
		return
	_settings_panel = SettingsPanelScript.new()
	add_child(_settings_panel)
	if _settings_panel.has_method("open"):
		_settings_panel.open()

func _on_settings_pressed() -> void:
	_open_settings_panel()

var _settings_panel: Control = null

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_TAB:
			var buttons := [start_button, quit_button]
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
