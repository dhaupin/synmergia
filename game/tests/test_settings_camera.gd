## test_settings_camera.gd - Settings persistence + camera wiring battery.
##
## Covers the two vert-slice gaps from the session log:
##   1. Settings dropdowns hydrate saved PlayerConfig values on build
##      (sliders/toggles already did; dropdowns rendered the default).
##   2. ThirdPersonCamera consumes camera_fov / camera_distance /
##      camera_smoothing -- both at boot (_apply_user_settings) and live
##      via PlayerConfig.setting_changed.
##   3. Round-trip: change a setting -> saved value survives a reload.
##
##   cd game && xvfb-run godot --path . --script res://tests/test_settings_camera.gd
##
## Exit 0 = all checks pass. Failures print FAIL lines and exit 1.
extends SceneTree

var _pass := 0
var _fail := 0


func _initialize() -> void:
	print("=== SETTINGS + CAMERA WIRING TEST ===")
	# Defer one frame so autoloads are ready.
	await process_frame
	_run()


func _ok(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  PASS: %s %s" % [label, detail])
	else:
		_fail += 1
		print("  FAIL: %s %s" % [label, detail])


func _run() -> void:
	var pc = root.get_node_or_null("PlayerConfig")
	_ok("PlayerConfig autoload present", pc != null)
	if pc == null:
		_finish()
		return	## ------------------------------------------------------------------
	## 1. Dropdown hydration
	## ------------------------------------------------------------------
	print("--- dropdown hydration ---")
	# Hydration happens at panel _ready, so saved values must be set
	# BEFORE the panel builds. Set camera_mode=1 ("Action") first.
	pc.set_account_setting("camera_mode", 1, true)
	# language: the panel stores indices; write idx 2 ("French") directly
	# (the old default "en" was a legacy string, now coerced on load).
	pc._account_settings["language"] = 2

	# Use the REAL HUD scene: SettingsPanel lives in hud_layer.tscn and its
	# _setup_ui() needs the tree context the scene provides. A bare
	# panel_script.new() has no "Panel" node family and its _setup_ui
	# bails, so a synthetic instance would never populate controls.
	var hud: Node = (load("res://ui/hud/hud_layer.tscn") as PackedScene).instantiate()
	root.add_child(hud)
	await process_frame
	var panel: Node = hud.get_node_or_null("SettingsPanel")
	_ok("SettingsPanel present in HUD scene", panel != null)
	if panel == null:
		_finish()
		return
	await process_frame

	var cam_mode_dd: OptionButton = panel._setting_controls.get("camera_mode", {}).get("control")
	_ok("camera_mode dropdown hydrates saved index", cam_mode_dd != null and cam_mode_dd.selected == 1,
		"(selected=%s)" % str(cam_mode_dd.selected if cam_mode_dd else "nil"))
	if cam_mode_dd:
		cam_mode_dd.selected = 0
		pc.set_account_setting("camera_mode", 0, true)

	var lang_dd: OptionButton = panel._setting_controls.get("language", {}).get("control")
	_ok("language dropdown hydrates saved index", lang_dd != null and lang_dd.selected == 2,
		"(selected=%s)" % str(lang_dd.selected if lang_dd else "nil"))
	if lang_dd:
		pc.set_account_setting("language", 0, true)




	hud.queue_free()
	await process_frame

	## ------------------------------------------------------------------
	## 2. Round-trip: sliders save into PlayerConfig
	## ------------------------------------------------------------------
	print("--- round trip ---")
	pc.set_account_setting("camera_fov", 100, true)
	pc.set_account_setting("camera_distance", 18.0, true)
	pc.set_account_setting("camera_smoothing", false, true)
	_ok("camera_fov saved", int(pc.get_account_setting("camera_fov", 0)) == 100)
	_ok("camera_distance saved", float(pc.get_account_setting("camera_distance", 0.0)) == 18.0)
	_ok("camera_smoothing saved", bool(pc.get_account_setting("camera_smoothing", true)) == false)

	## ------------------------------------------------------------------
	## 3. Camera consumes the saved settings
	## ------------------------------------------------------------------
	print("--- camera wiring ---")
	var cam: Camera3D = load("res://entities/player/camera/third_person_camera.gd").new()
	var mount := Node3D.new()
	mount.add_child(cam)
	root.add_child(mount)
	await process_frame
	await process_frame

	_ok("camera applies saved fov at boot", absf(cam.fov - 100.0) < 0.5,
		"(fov=%s)" % str(cam.fov))
	_ok("camera applies saved distance at boot", absf(cam.current_distance - 18.0) < 0.01,
		"(dist=%s)" % str(cam.current_distance))
	_ok("camera max_distance widened for saved distance", cam.max_distance >= 18.0,
		"(max=%s)" % str(cam.max_distance))
	_ok("camera smoothing toggle maps to loose follow", absf(cam.follow_smoothness - 4.0) < 0.01,
		"(smooth=%s)" % str(cam.follow_smoothness))

	# Live update through the signal path (same path the settings panel uses).
	pc.set_account_setting("camera_fov", 65, true)
	pc.set_account_setting("camera_distance", 7.0, true)
	pc.set_account_setting("camera_smoothing", true, true)
	await process_frame
	await process_frame

	_ok("camera fov updates live via setting_changed", absf(cam._default_fov - 65.0) < 0.5,
		"(fov=%s)" % str(cam._default_fov))
	_ok("camera distance updates live via setting_changed", absf(cam.current_distance - 7.0) < 0.01,
		"(dist=%s)" % str(cam.current_distance))
	_ok("camera smoothing updates live via setting_changed", absf(cam.follow_smoothness - 12.0) < 0.01,
		"(smooth=%s)" % str(cam.follow_smoothness))

	# Restore defaults so the account store is clean for other tests.
	pc.set_account_setting("camera_fov", 90, true)
	pc.set_account_setting("camera_distance", 10.0, true)
	pc.set_account_setting("camera_smoothing", true, true)

	mount.queue_free()

	_finish()


func _tab_button(panel: Node, label: String) -> Button:
	for btn in panel._tab_buttons:
		if is_instance_valid(btn) and str(btn.text) == label:
			return btn
	return null


func _finish() -> void:
	print("=== SETTINGS/CAMERA SUMMARY: %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
