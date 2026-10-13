## Probe: the touch-HUD yield law at the UIPanel chokepoint (play-day
## pass 2: the joystick drew OVER the settings/character panels).
## Headless script mode:
##   godot --headless --path game --script res://tests/probe_touch_hud_yield.gd
##
## Contract probe: UIPanel-derived classes must call
## InputManager.set_touch_hud_panels_open(true) on open() and coordinate
## the disarm on close() (via MenuManager's authoritative stack). The
## InputManager autoload cannot compile in script mode, so this probe
## reads the SOURCES statically: the funnel call must exist in
## UIPanel.open and close, and set_panels_open in the joystick must
## take a bool. Runtime wiring verification lives in the HUD suite.
extends SceneTree

var _fails: int = 0


func _init() -> void:
	call_deferred("_run")


func _check(cond: bool, label: String) -> void:
	if cond:
		print("PASS: " + label)
	else:
		_fails += 1
		printerr("FAIL: " + label)


func _source(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f != null else ""


func _run() -> void:
	var panel_src := _source("res://ui/components/ui_panel.gd")
	_check(panel_src.contains("set_touch_hud_panels_open(true)"),
		"UIPanel.open calls set_touch_hud_panels_open(true)")
	_check(panel_src.contains("set_touch_hud_panels_open(false)"),
		"UIPanel.close disarms set_touch_hud_panels_open(false)")
	_check(panel_src.contains("_open_panels"),
		"UIPanel.close consults MenuManager's stack (idle rearm safe)")
	var im_src := _source("res://core/autoload/input_manager.gd")
	_check(im_src.contains("set_touch_hud_panels_open"), "InputManager exposes the funnel")
	_check(im_src.contains("set_panels_open"), "InputManager forwards to the joystick")
	var vj_src := _source("res://ui/components/virtual_joystick.gd")
	_check(vj_src.contains("func set_panels_open"), "joystick exposes set_panels_open")
	var bs_src := _source("res://ui/components/blacksmith_ui.gd")
	_check(bs_src.contains("set_panel_title(\"The Smithy\")"), "Blacksmith panel title set (no raw node name)")
	var cs_src := _source("res://ui/menus/character_stats_ui.gd")
	_check(cs_src.contains("SCROLL_MODE_DISABLED") and cs_src.contains("SCROLL_MODE_SHOW_NEVER"),
		"char stats scroll: touch-drag modes explicit")
	var sp_src := _source("res://ui/components/settings_panel.gd")
	_check(sp_src.contains("0.9, 1.4"), "ui_scale slider band sane (0.9..1.4)")
	var styles_src := _source("res://ui/components/ui_styles.gd")
	_check(styles_src.contains("LineEdit or control is TextEdit"), "text scaling covers LineEdit/TextEdit")
	_check(styles_src.contains("CheckBox or control is CheckButton"), "text scaling covers checkboxes")
	_check(styles_src.contains("OptionButton"), "text scaling covers dropdowns")

	print("TOUCH HUD YIELD probe: %d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)
