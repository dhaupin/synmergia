## ScreenshotService — Native Godot screenshot capture
## Captures the viewport as a PNG and saves it to disk.
## Used for dev automation (save_screenshot(FLAG_DEV)) and in-game player F8.

extends Node

const FLAG_DEV: int = 1 << 0

const KEY_F8: int = 4194332
const KEY_F8_ALT: int = 4194339  # xdotool/X11 encoding
const USB_F8: int = 119
const FLAG_FORCE: int = 1 << 1

enum Owner { DEV, PLAYER }

signal screenshot_saved(owner: Owner, path: String)
signal screenshot_failed(error: String)

var _session_index: int = 0

func save_screenshot(flags: int = 0) -> String:
	var owner: Owner = Owner.DEV if (flags & FLAG_DEV) else Owner.PLAYER
	var overwrite: bool = (flags & FLAG_FORCE) != 0

	if owner == Owner.PLAYER and not _screenshots_enabled():
		_emit_disabled()
		return ""

	var img: Image = _capture_viewport()
	if img == null:
		emit_signal("screenshot_failed", "viewport capture returned null")
		return ""

	var filename: String = _make_filename(owner)
	var rel_path: String = "captures/screenshots/" + filename
	var abs_path: String = ProjectSettings.globalize_path("res://" + rel_path)

	var mk_err: Error = DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	if mk_err != OK:
		emit_signal("screenshot_failed", "could not create captures/screenshots/")
		return ""

	if overwrite or not FileAccess.file_exists(abs_path):
		var err: Error = img.save_png(abs_path)
		if err != OK:
			emit_signal("screenshot_failed", "save_png failed (err=%d)" % err)
			return ""

	emit_signal("screenshot_saved", owner, abs_path)
	_notify_saved(abs_path, owner)
	return abs_path

func save_dev_screenshot() -> String:
	return save_screenshot(FLAG_DEV)

func _capture_viewport() -> Image:
	var vp: Viewport = get_viewport()
	if vp == null:
		return null
	var tex: ViewportTexture = vp.get_texture()
	if tex == null:
		return null
	return tex.get_image()

func _make_filename(owner: int) -> String:
	var ts: String = Time.get_datetime_string_from_system()
	ts = ts.replace("T", "_").replace(":", "").replace("-", "")
	if owner == Owner.DEV:
		_session_index += 1
		return "screenshot_%s_%03d.png" % [ts, _session_index]
	return "screenshot_%s.png" % ts

func _screenshots_enabled() -> bool:
	if PlayerConfig and PlayerConfig.has_method("get_global_setting"):
		return PlayerConfig.get_global_setting("screenshots_enabled", true)
	return true

func _notify_saved(abs_path: String, owner: int) -> void:
	var msg: String = "Screenshot saved: %s" % abs_path.get_file()
	if owner == Owner.DEV:
		GameLog.info(msg)
	else:
		if NotificationService:
			_emit_toast(msg)

func _emit_toast(msg: String) -> void:
	if not NotificationService or not ResourceLoader.exists("res://core/notifications/notification_kind.gd"):
		return
	var NotifKind = load("res://core/notifications/notification_kind.gd").NotifKind
	if not NotifKind.has("SYSTEM"):
		return
	NotificationService.notify(NotifKind.SYSTEM, msg, "ScreenshotService", "shot:%d" % msg.hash(), {}, "")

func _emit_disabled() -> void:
	emit_signal("screenshot_failed", "Screenshots are disabled in Settings")
	if NotificationService:
		_emit_toast("Screenshots are disabled in Settings")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		var kc: int = event.get_keycode()
		# Accept KEY_F8, KEY_F8_ALT (xdotool/X11), or USB HID code 119
		if kc == KEY_F8 or kc == KEY_F8_ALT or event.physical_keycode == USB_F8:
			save_screenshot()
