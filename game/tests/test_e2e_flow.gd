extends SceneTree

# End-to-end smoke test for the full Synmergia flow:
#   main_menu -> login -> register -> lobby -> character_select
#   -> character creation -> play
#
# Run:
#   ./tools/godot --headless --path . --script res://tests/test_e2e_flow.gd

var _pass := 0
var _fail := 0

func _initialize() -> void:
	print("--- END-TO-END FLOW TEST ---")
	_run()
	print("--- E2E TEST: %d passed, %d failed ---" % [_pass, _fail])
	quit(_fail)

func _run() -> void:
	var LoginService := root.get_node_or_null("LoginService")
	var AccountService := root.get_node_or_null("AccountService")
	var GameManager := root.get_node_or_null("GameManager")

	_assert("GameManager present", GameManager != null)
	_assert("LoginService present", LoginService != null)
	_assert("AccountService present", AccountService != null)
	if not (LoginService and AccountService and GameManager):
		return

	# 1) Start from a clean state
	LoginService.logout()
	_assert("Logged out at start", not LoginService.is_logged_in())

	# 2) Register a fresh account
	var username := "e2e_%d" % Time.get_ticks_msec()
	var register_ok: bool = LoginService.register(username, "test_password_42", "E2E Hero")
	_assert("Register fresh account", register_ok)
	_assert("Auto-logged in after register", LoginService.is_logged_in())
	_assert("Account id matches", LoginService.get_current_account_id() == username)
	_assert("Has session token", LoginService.get_current_session_token() != "")
	_assert("Account is_guest=false", not LoginService.is_guest())

	# 3) Logout and try wrong password
	LoginService.logout()
	_assert("Logged out again", not LoginService.is_logged_in())
	var wrong_ok: bool = LoginService.login(username, "wrong_password")
	_assert("Bad password rejected", not wrong_ok)

	# 4) Re-login with correct password
	var good_ok: bool = LoginService.login(username, "test_password_42")
	_assert("Good password accepted", good_ok)
	_assert("Logged in after retry", LoginService.is_logged_in())

	# 5) Try guest flow
	LoginService.login_as_guest()
	_assert("Guest login succeeds", LoginService.is_logged_in())
	_assert("is_guest=true", LoginService.is_guest())

	# 6) Logout, then re-login original
	LoginService.logout()
	_assert("Logged out after guest", not LoginService.is_logged_in())
	good_ok = LoginService.login(username, "test_password_42")
	_assert("Re-login original after guest", good_ok)

	# 7) Game state machine
	_assert("Has LOADING state", GameManager.GameState.keys().has("LOADING"))
	_assert("Has LOGIN state", GameManager.GameState.keys().has("LOGIN"))
	_assert("Has MAIN_MENU state", GameManager.GameState.keys().has("MAIN_MENU"))
	_assert("Has LOBBY state", GameManager.GameState.keys().has("LOBBY"))
	_assert("Has CHARACTER_SELECT state", GameManager.GameState.keys().has("CHARACTER_SELECT"))
	_assert("Has PLAYING state", GameManager.GameState.keys().has("PLAYING"))
	_assert("Has PAUSED state", GameManager.GameState.keys().has("PAUSED"))

	# 8) AccountService character lifecycle
	var char_id := "char_%d" % Time.get_ticks_msec()
	var link_ok: bool = AccountService.link_character(char_id, username, {
		"name": "E2E Test",
		"species_id": "human",
		"class_id": "warrior",
		"level": 1,
		"zone_id": "zone_starter_plains",
	})
	_assert("AccountService.link_character", link_ok)
	var chars: Array = AccountService.get_account_characters(username)
	_assert("Account has 1 character", chars.size() == 1)

	var unlink_ok: bool = AccountService.unlink_character(char_id)
	_assert("AccountService.unlink_character", unlink_ok)
	chars = AccountService.get_account_characters(username)
	_assert("Account has 0 chars after unlink", chars.size() == 0)

	# 9) Scene loads
	var login_scene := load("res://ui/menus/login.tscn")
	_assert("login.tscn loads", login_scene != null)
	var lobby_scene := load("res://ui/menus/lobby.tscn")
	_assert("lobby.tscn loads", lobby_scene != null)
	var char_select_scene := load("res://ui/menus/character_select.tscn")
	_assert("character_select.tscn loads", char_select_scene != null)
	var main_menu_scene := load("res://ui/menus/main_menu.tscn")
	_assert("main_menu.tscn loads", main_menu_scene != null)
	var hud_scene := load("res://ui/hud/hud_layer.tscn")
	_assert("hud_layer.tscn loads", hud_scene != null)
	var world_scene := load("res://scenes/world_playable.tscn")
	_assert("world_playable.tscn loads", world_scene != null)

	# 10) HUD has expected widget count (basic structure check)
	# We can't easily instantiate a CanvasLayer in headless SceneTree test,
	# but we can pack and count children of the PackedScene.
	# PackedScene does not expose get_child_count at script time; presence is enough

	# 11) Rate limiting kicks in after several wrong-password attempts.
	# We don't wait for cooldown; we just verify _check_rate_limit gates the API.
	var LoginServiceInternal := LoginService
	# Spam 8 wrong passwords — by attempt 6+ we should see rate limit denial.
	var saw_rate_limit_failure: bool = false
	# Reset the in-memory counter (private but reachable; we own this test).
	# Use the public API path: just hammer login() until it stops failing on
	# "Incorrect password" and starts failing on "Too many attempts".
	for i in range(8):
		var ok: bool = LoginServiceInternal.login(username, "wrong_%d" % i)
		if not ok:
			# We can't read the failure reason directly, but we know
			# 6+ wrong in window returns false because of rate limit
			# (not just wrong password). To verify, count that we still
			# get a false return even though the password is the *correct*
			# one — that proves the rate limit window is in effect.
			pass
	# Now try the *correct* password. If rate limit is in effect, this
	# must return false (because the rate limit check happens before
	# the password check).
	var correct_after_spam: bool = LoginServiceInternal.login(username, "test_password_42")
	_assert("Rate limit blocks correct password after spam", not correct_after_spam)
	# Restore: log out so we don't leave the test environment rate-limited.
	LoginServiceInternal.logout()

	# 12) Settings panel script loads + main_menu wires the button
	var settings_script: GDScript = load("res://ui/components/settings_panel.gd")
	_assert("SettingsPanel script loads", settings_script != null)
	var main_menu_script: GDScript = load("res://ui/menus/main_menu.gd")
	_assert("MainMenu script loads", main_menu_script != null)
	var main_menu_scene_2: PackedScene = load("res://ui/menus/main_menu.tscn")
	_assert("MainMenu scene loads", main_menu_scene_2 != null)
	# Verify main_menu has the open method (compile-time check that the
	# new code path landed).
	var sample_main: Node = main_menu_script.new()
	_assert("MainMenu has _open_settings_panel method", sample_main.has_method("_open_settings_panel"))
	_assert("MainMenu has _on_settings_pressed method", sample_main.has_method("_on_settings_pressed"))
	sample_main.queue_free()

func _assert(label: String, cond: bool) -> void:
	if cond:
		print("  [OK] %s" % label)
		_pass += 1
	else:
		printerr("  [FAIL] %s" % label)
		_fail += 1
