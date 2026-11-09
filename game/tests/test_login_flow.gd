extends SceneTree

# Smoke test for the new login -> lobby -> char-select flow.
# Run: ./tools/godot --headless --path . --script res://tests/test_login_flow.gd

var _pass := 0
var _fail := 0

# Resolve autoloads via root (autoloads are children of /root)
var LoginService
var AccountService
var GameManager

func _initialize() -> void:
	LoginService = root.get_node_or_null("LoginService")
	AccountService = root.get_node_or_null("AccountService")
	GameManager = root.get_node_or_null("GameManager")

	print("--- LOGIN / LOBBY FLOW TEST ---")

	# 1. LoginService present and not logged in by default
	_assert("LoginService autoload present", LoginService != null)
	if LoginService:
		_assert("Not logged in initially", not LoginService.is_logged_in())

	# 2. Register a new account
	if LoginService:
		var test_user := "tester_%d" % Time.get_ticks_msec()
		var ok: bool = LoginService.register(test_user, "hunter2", "Test Hero", "hero@example.com")
		_assert("Register new account", ok)
		_assert("Logged in after register", LoginService.is_logged_in())
		_assert("Account id matches", LoginService.get_current_account_id() == test_user)
		_assert("Session token minted", LoginService.get_current_session_token().length() > 0)

		# 3. Logout
		LoginService.logout()
		_assert("Logged out", not LoginService.is_logged_in())

		# 4. Login with bad password fails
		_assert("Bad password rejected", not LoginService.login(test_user, "wrong"))

		# 5. Login with good password succeeds
		_assert("Good password accepted", LoginService.login(test_user, "hunter2"))
		_assert("Account is_guest=false", not LoginService.is_guest())

		# 6. Guest play is RETIRED: the door refuses, no session is minted
		LoginService.logout()
		_assert("Guest login refused", not LoginService.login_as_guest())
		_assert("Not logged in after refused guest", not LoginService.is_logged_in())
		_assert("Register without email refused", not LoginService.register("noemail_%d" % Time.get_ticks_msec(), "hunter2"))

	# 7. GameManager has LOGIN/LOBBY states
	if GameManager:
		_assert("GameManager has LOGIN state", "LOGIN" in GameManager.GameState.keys())
		_assert("GameManager has LOBBY state", "LOBBY" in GameManager.GameState.keys())

	# 8. CharacterData.to_dict round-trip
	var CharacterData = load("res://core/schemas/character_data.gd")
	if CharacterData:
		var cd = CharacterData.new("human", "warrior", "Aria")
		cd.level = 7
		var blob = cd.to_dict()
		_assert("to_dict returns species_id", blob.species_id == "human")
		_assert("to_dict returns level", int(blob.level) == 7)
		_assert("to_dict includes character_id key", blob.has("character_id"))

	# 9. AccountService can link a character
	if AccountService and LoginService:
		var test_user := "acctest_%d" % Time.get_ticks_msec()
		LoginService.register(test_user, "hunter2", "", "acct@example.com")
		LoginService.logout()
		AccountService.create_account(test_user, "")
		var linked: bool = AccountService.link_character("ch_aria", test_user, {"name": "Aria"})
		_assert("AccountService.link_character ok", linked)
		var chars: Array = AccountService.get_account_characters(test_user)
		_assert("Account has 1 character", chars.size() == 1)

	# 10. Login & lobby scenes load without parse errors
	var login_scene := load("res://ui/menus/login.tscn")
	_assert("login.tscn loads", login_scene != null)
	var lobby_scene := load("res://ui/menus/lobby.tscn")
	_assert("lobby.tscn loads", lobby_scene != null)

	# 11. THE LOGIN PANEL ITSELF: drive the real buttons through the
	# accessibility layer. The service-level legs above never touch the UI,
	# which is exactly how a REGISTER-mode button swap survived: the primary
	# button read "Create & Enter" but ran the login handler (a silent bounce
	# back to login mode) and the secondary read "Back to Login" but ran the
	# register handler. Both bugs live in the panel, not the service, so the
	# panel must be exercised.
	# The panel needs its _ready() to run (autoloads resolve, mode set),
	# so the panel leg is deferred one frame before it asserts + quits.
	_test_login_panel.call_deferred()


## Instantiate the real login panel and prove its two buttons do what their
## VISIBLE labels say in BOTH modes (the a11y `action` must match the verb).
func _test_login_panel() -> void:
	await process_frame
	await process_frame
	var panel_scene := load("res://ui/menus/login.tscn")
	if panel_scene == null:
		_assert("login panel instantiates", false)
		return
	var panel: Control = panel_scene.instantiate()
	root.add_child(panel)
	var primary: Button = panel.get_node_or_null("Center/Panel/Form/Buttons/LoginButton")
	var secondary: Button = panel.get_node_or_null("Center/Panel/Form/Buttons/RegisterButton")
	_assert("login panel has both buttons", primary != null and secondary != null)
	if primary == null or secondary == null:
		panel.queue_free()
		return

	# LOGIN mode: primary = sign in, secondary = flip to register.
	_assert("login mode: primary reads sign-in",
		String(primary.get("accessibility_name")).to_lower().contains("sign in"))
	_assert("login mode: secondary reads create-account",
		String(secondary.get("accessibility_name")).to_lower().contains("create"))
	secondary.pressed.emit()
	_assert("secondary flipped into register mode",
		String(primary.get("accessibility_name")).to_lower().contains("create"))
	_assert("register mode: primary label matches its action",
		String(primary.get("accessibility_name")).to_lower().contains("create"))
	_assert("register mode: secondary reads back-to-sign-in",
		String(secondary.get("accessibility_name")).to_lower().contains("back"))

	# THE REGRESSION: in register mode the PRIMARY button must submit the
	# register form. Prove it by registering a fresh account through the panel
	# and landing logged in.
	var u := "panel_%d" % Time.get_ticks_msec()
	var unode: LineEdit = panel.get_node_or_null("Center/Panel/Form/UsernameField")
	var pnode: LineEdit = panel.get_node_or_null("Center/Panel/Form/PasswordField")
	var enode: LineEdit = panel.get_node_or_null("Center/Panel/Form/EmailField")
	if unode and pnode and enode:
		unode.text = u
		pnode.text = "hunter2"
		enode.text = "panel_%d@example.com" % Time.get_ticks_msec()
		if LoginService:
			LoginService.logout()
		primary.pressed.emit()
		_assert("register-mode primary actually registers",
			LoginService and LoginService.is_logged_in()
			and LoginService.get_current_account_id() == u)
	else:
		_assert("login panel has register fields", false)

	# Back to Login must flip modes, never submit.
	secondary.pressed.emit()
	_assert("secondary flips back to login mode",
		String(primary.get("accessibility_name")).to_lower().contains("sign in"))

	if LoginService:
		LoginService.logout()
	panel.queue_free()

	print("")
	print("--- LOGIN TEST: %d passed, %d failed ---" % [_pass, _fail])
	quit(_fail)


func _assert(name: String, cond: bool) -> void:
	if cond:
		print("  [OK] %s" % name)
		_pass += 1
	else:
		print("  [FAIL] %s" % name)
		_fail += 1
