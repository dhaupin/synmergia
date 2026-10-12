## LoginUI - Account login, register, and guest play
##
## First screen after the splash. Routes to Lobby on success. Three
## modes in one panel:
##  - Login: existing account
##  - Register: create new account (auto-logs-in)
##  - Guest: skip auth, get a transient account
##
## All three paths end at LOBBY. Lobby is the per-account char list.
extends Control
const UIStyles = preload("res://ui/components/ui_styles.gd")


@onready var _username: LineEdit = $Center/Panel/Form/UsernameField
@onready var _password: LineEdit = $Center/Panel/Form/PasswordField
@onready var _display_name: LineEdit = $Center/Panel/Form/DisplayNameField
@onready var _error_label: Label = $Center/Panel/Form/ErrorLabel
@onready var _login_btn: Button = $Center/Panel/Form/Buttons/LoginButton
@onready var _register_btn: Button = $Center/Panel/Form/Buttons/RegisterButton
@onready var _guest_btn: Button = $Center/Panel/Form/Buttons/GuestButton
@onready var _display_name_row: Control = $Center/Panel/Form/DisplayNameField

enum Mode { LOGIN, REGISTER }
var _mode: int = Mode.LOGIN

func _ready() -> void:
	_login_btn.pressed.connect(_on_login_pressed)
	_register_btn.pressed.connect(_on_register_pressed)
	_guest_btn.pressed.connect(_on_guest_pressed)
	_password.secret = true
	_set_mode(Mode.LOGIN)
	_apply_styles()
	_clear_error()

	# Enter key in text fields submits the form
	_username.text_submitted.connect(_on_username_submitted)
	_password.text_submitted.connect(_on_password_submitted)

	if LoginService:
		LoginService.login_failed.connect(_on_login_failed)
		LoginService.login_succeeded.connect(_on_login_succeeded)
	_resume_guest_door()

func _apply_styles() -> void:
	if not UIStyles:
		return
	var btn_styles := UIStyles.create_button_style()
	UIStyles.apply_button_styles(_login_btn, btn_styles)
	UIStyles.apply_button_styles(_register_btn, btn_styles)
	UIStyles.apply_button_styles(_guest_btn, btn_styles)

func _set_mode(mode: int) -> void:
	_mode = mode
	_display_name_row.visible = (mode == Mode.REGISTER)
	match mode:
		Mode.LOGIN:
			_login_btn.text = "Login"
			_register_btn.text = "Create Account"
		Mode.REGISTER:
			_login_btn.text = "Create & Enter"
			_register_btn.text = "Back to Login"
	_clear_error()

func _on_login_pressed() -> void:
	# print removed: print("[LOGIN] LoginButton pressed, mode=%d user='%s'" % [_mode, _username.text])
	if DebugOverlay:
		DebugOverlay.log_click("LoginButton", "login", false)
	if _mode == Mode.REGISTER:
		_set_mode(Mode.LOGIN)
		return
	var u := _username.text
	var p := _password.text
	if u.strip_edges() == "":
	# print removed: print("[LOGIN] LoginButton -> no username, error shown")
		_show_error("Enter a username")
		return
	if not LoginService:
		_show_error("LoginService unavailable")
		return
	# print removed: print("[LOGIN] LoginButton -> calling LoginService.login('%s', ***)" % u)
	LoginService.login(u, p)
	if DebugOverlay:
		DebugOverlay.log_click("LoginButton", "login", true)

func _on_register_pressed() -> void:
	# print removed: print("[LOGIN] RegisterButton pressed, mode=%d" % _mode)
	if DebugOverlay:
		DebugOverlay.log_click("RegisterButton", "toggle_mode", false)
	if _mode == Mode.LOGIN:
		_set_mode(Mode.REGISTER)
		return
	var u := _username.text
	var p := _password.text
	var dn := _display_name.text if _display_name else ""
	if u.strip_edges() == "":
		_show_error("Enter a username")
		return
	if p.length() < 6:
		_show_error("Password must be at least 6 characters")
		return
	if not LoginService:
		_show_error("LoginService unavailable")
		return
	LoginService.register(u, p, dn)
	if DebugOverlay:
		DebugOverlay.log_click("RegisterButton", "register", true)

func _on_guest_pressed() -> void:
	# print removed: print("[LOGIN] GuestButton pressed")
	if DebugOverlay:
		DebugOverlay.log_click("GuestButton", "guest_login", false)
	if not LoginService:
		_show_error("LoginService unavailable")
		return
	LoginService.login_as_guest()
	if DebugOverlay:
		DebugOverlay.log_click("GuestButton", "guest_login", true)

func _on_login_succeeded(_account_id: String, _is_guest: bool) -> void:
	if GameManager:
		GameManager.change_state(GameManager.GameState.LOBBY)

func _on_login_failed(reason: String) -> void:
	_show_error(reason)

func _show_error(msg: String) -> void:
	if _error_label:
		_error_label.text = msg
		_error_label.visible = true

func _clear_error() -> void:
	if _error_label:
		_error_label.text = ""
		_error_label.visible = false

func _on_username_submitted(_text: String) -> void:
	_password.grab_focus()

func _on_password_submitted(text: String) -> void:
	if text.strip_edges() == "":
		_show_error("Enter a password")
		return
	_on_login_pressed()

## The resume door (the web reload problem): when this browser
## remembers a guest id, the guest button RESUMES it instead of
## minting a new one -- relabeling the SAME button ("Continue as
## guest") rather than adding a second door, so the a11y contract
## stays one button and the probe's "Play without an account" press
## resumes automatically after a reload. Desktop/`--script` mode:
## the bridge is invisible and the label never changes.
func _resume_guest_door() -> void:
	if not WebIdBridge or not WebIdBridge.has_last_guest():
		return
	var id := WebIdBridge.get_last_guest_id()
	if AccountService and AccountService.get_account(id).is_empty():
		WebIdBridge.forget_guest()
		return
	_guest_btn.text = "Continue as guest"
	_guest_btn.accessibility_name = "Continue as guest"
	_guest_btn.accessibility_description = "Resumes the guest session this browser already played"

# TAB = focus navigation (accessibility). Former F5/F6 auto-login
# debug hotkeys removed: they fired real account actions from any
# scene and collided with the Settings keybind UI. Headless tests
# drive the buttons directly.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_TAB:
				# Focus cycling lives on A11yService (one implementation
				# for every menu; prd-accessibility.md sec 8 disposition).
				if event.shift:
					A11yService.focus_prev()
				else:
					A11yService.focus_next()
