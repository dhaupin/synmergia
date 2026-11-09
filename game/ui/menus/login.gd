## LoginUI - Account login and register (guest play is RETIRED).
##
## First screen after the splash. Routes to Lobby on success. Two
## modes in one panel:
##  - Login: existing account
##  - Register: create new account (email required, auto-logs-in)
##
## Every account is email-bound; there is no guest door. Both paths
## end at LOBBY. Lobby is the per-account char list.
extends Control
const UIStyles = preload("res://ui/components/ui_styles.gd")


@onready var _username: LineEdit = $Center/Panel/Form/UsernameField
@onready var _password: LineEdit = $Center/Panel/Form/PasswordField
@onready var _display_name: LineEdit = $Center/Panel/Form/DisplayNameField
@onready var _email: LineEdit = $Center/Panel/Form/EmailField
@onready var _error_label: Label = $Center/Panel/Form/ErrorLabel
@onready var _login_btn: Button = $Center/Panel/Form/Buttons/LoginButton
@onready var _register_btn: Button = $Center/Panel/Form/Buttons/RegisterButton
@onready var _display_name_row: Control = $Center/Panel/Form/DisplayNameField
@onready var _email_row: Control = $Center/Panel/Form/EmailField

enum Mode { LOGIN, REGISTER }
var _mode: int = Mode.LOGIN

func _ready() -> void:
	_login_btn.pressed.connect(_on_login_pressed)
	_register_btn.pressed.connect(_on_register_pressed)
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

func _apply_styles() -> void:
	if not UIStyles:
		return
	var btn_styles := UIStyles.create_button_style()
	UIStyles.apply_button_styles(_login_btn, btn_styles)
	UIStyles.apply_button_styles(_register_btn, btn_styles)

func _set_mode(mode: int) -> void:
	_mode = mode
	_display_name_row.visible = (mode == Mode.REGISTER)
	_email_row.visible = (mode == Mode.REGISTER)
	match mode:
		Mode.LOGIN:
			_login_btn.text = "Login"
			_register_btn.text = "Create Account"
			UIStyles.apply_accessibility(_login_btn, "Sign in to your account")
			UIStyles.apply_accessibility(_register_btn, "Create a new account")
		Mode.REGISTER:
			_login_btn.text = "Create & Enter"
			_register_btn.text = "Back to Login"
			# The visible text flips with the mode, so the accessible action
			# must too: otherwise an AT/agent reads "sign in" for a button
			# that actually creates the account (and vice versa).
			UIStyles.apply_accessibility(_login_btn, "Create account and enter")
			UIStyles.apply_accessibility(_register_btn, "Back to sign in")
	_clear_error()

func _on_login_pressed() -> void:
	# This is the PRIMARY button: "Login" in login mode, "Create & Enter"
	# in register mode. It must do whatever its current label says.
	if _mode == Mode.REGISTER:
		_do_register()
		return
	_do_login()

func _on_register_pressed() -> void:
	# This is the SECONDARY button: "Create Account" flips INTO register
	# mode; "Back to Login" flips back. It never submits a form.
	if _mode == Mode.REGISTER:
		_set_mode(Mode.LOGIN)
		return
	_set_mode(Mode.REGISTER)

func _do_login() -> void:
	var u := _username.text
	var p := _password.text
	if u.strip_edges() == "":
		# print removed: print("[LOGIN] LoginButton -> no username, error shown")
		if DebugOverlay:
			DebugOverlay.log_click("LoginButton", "login", false)
		_show_error("Enter a username")
		return
	if not LoginService:
		if DebugOverlay:
			DebugOverlay.log_click("LoginButton", "login", false)
		_show_error("LoginService unavailable")
		return
	# print removed: print("[LOGIN] LoginButton -> calling LoginService.login('%s', ***)" % u)
	LoginService.login(u, p)
	if DebugOverlay:
		DebugOverlay.log_click("LoginButton", "login", true)

func _do_register() -> void:
	var u := _username.text
	var p := _password.text
	var dn := _display_name.text if _display_name else ""
	var em := _email.text if _email else ""
	if u.strip_edges() == "":
		if DebugOverlay:
			DebugOverlay.log_click("RegisterButton", "register", false)
		_show_error("Enter a username")
		return
	if p.length() < 6:
		if DebugOverlay:
			DebugOverlay.log_click("RegisterButton", "register", false)
		_show_error("Password must be at least 6 characters")
		return
	if em.strip_edges() == "":
		if DebugOverlay:
			DebugOverlay.log_click("RegisterButton", "register", false)
		_show_error("Enter an email (required to create an account)")
		return
	if not LoginService:
		if DebugOverlay:
			DebugOverlay.log_click("RegisterButton", "register", false)
		_show_error("LoginService unavailable")
		return
	LoginService.register(u, p, dn, em)
	if DebugOverlay:
		DebugOverlay.log_click("RegisterButton", "register", true)

func _on_login_succeeded(_account_id: String) -> void:
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
