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
