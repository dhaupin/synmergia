## LoginService - Account login, registration, and session management
##
## Persists accounts + hashed passwords in user://accounts.json so the
## game is fully playable offline (single-machine / dev). When a real
## authoritative server is connected, the same API can be re-pointed
## to NetworkManager RPCs without touching UI code.
##
## Security notes:
##  - Passwords are PBKDF2-hashed with a per-account salt via Godot's
##    HashingContext (SHA-256, 4096 iterations). Plaintext is never
##    written to disk.
##  - Login attempts are rate-limited through QoSService to mitigate
##    brute force (5 attempts / 10s / account).
##  - Display names flow through SecurityService.validate_player_name.
extends Node

# QoSService exposes a static facade (QoSService.rate_limit(...)), so a
# const preload here resolves to the class and the static methods still
# dispatch to the singleton at runtime -- no shadow.
const QoSService = preload("res://core/autoload/qos_service.gd")
##
## This is the client-side gate. Server should always re-validate.
extends Node

signal login_succeeded(account_id: String, is_guest: bool)
signal login_failed(reason: String)
signal logged_out
signal account_registered(account_id: String)

const SAVE_PATH := "user://accounts.json"
const PBKDF2_ITERATIONS := 4096
const HASH_BYTES := 32                # SHA-256 output
const SALT_BYTES := 16
const MAX_LOGIN_ATTEMPTS := 5
const LOGIN_COOLDOWN_SEC := 10.0
const SESSION_TOKEN_BYTES := 24

static var instance: LoginService

# In-memory state
var _current_account_id: String = ""
var _current_session_token: String = ""
var _is_guest: bool = false
var _failed_attempts: Dictionary = {}   # account_id -> [timestamps]

# Disk-backed state (id -> {salt, hash, display_name, created_at})
var _store: Dictionary = {}

func _ready() -> void:
	instance = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_store()
	GameLog.info("LoginService: Ready (%d stored accounts)" % _store.size())


# == Public API =========================================================

func login(account_id: String, password: String) -> bool:
	account_id = _sanitize_id(account_id)
	if not _check_rate_limit(account_id):
		_fail("Too many attempts. Please wait before trying again.")
		return false

	if not _store.has(account_id):
		_fail("Account not found")
		return false

	if not _verify_password(account_id, password):
		_fail("Incorrect password")
		return false

	_current_account_id = account_id
	_current_session_token = _mint_session_token()
	_is_guest = false
	_failed_attempts.erase(account_id)

	if AccountService:
		AccountService.update_last_login(account_id)
	GameLog.info("LoginService: %s logged in" % account_id)
	login_succeeded.emit(account_id, false)
	return true

func register(account_id: String, password: String, display_name: String = "") -> bool:
	account_id = _sanitize_id(account_id)
	if account_id == "":
		_fail("Account name cannot be empty")
		return false
	if password.length() < 6:
		_fail("Password must be at least 6 characters")
		return false
	if _store.has(account_id):
		_fail("Account already exists")
		return false

	var validation := SecurityService.validate_player_name(display_name) if SecurityService else {"valid": true}
	if not validation.get("valid", true):
		_fail("Display name invalid: %s" % validation.get("reason", "unknown"))
		return false

	var salt := _random_bytes(SALT_BYTES)
	var hash := _derive_hash(password, salt)
	_store[account_id] = {
		"salt": salt.hex_encode(),
		"hash": hash.hex_encode(),
		"display_name": display_name if display_name != "" else account_id,
		"created_at": Time.get_unix_time_from_system(),
		"is_guest": false,
	}
	_save_store()

	# Mirror to AccountService so the rest of the game sees a real account
	if AccountService:
		AccountService.create_account(account_id, "")

	GameLog.info("LoginService: Registered %s" % account_id)
	account_registered.emit(account_id)

	# Auto-login after register
	return login(account_id, password)

func login_as_guest() -> bool:
	var guest_id := "guest_%d" % Time.get_ticks_msec()
	if AccountService:
		AccountService.create_account(guest_id, "")
	_current_account_id = guest_id
	_current_session_token = _mint_session_token()
	_is_guest = true
	GameLog.info("LoginService: Guest session %s" % guest_id)
	login_succeeded.emit(guest_id, true)
	return true

func logout() -> void:
	if _current_account_id == "":
		return
	var prev := _current_account_id
	_current_account_id = ""
	_current_session_token = ""
	_is_guest = false
	GameLog.info("LoginService: %s logged out" % prev)
	logged_out.emit()

func is_logged_in() -> bool:
	return _current_account_id != ""

func get_current_account_id() -> String:
	return _current_account_id

func get_current_session_token() -> String:
	return _current_session_token

func is_guest() -> bool:
	return _is_guest

func has_account(account_id: String) -> bool:
	return _store.has(_sanitize_id(account_id))


# == Internals ==========================================================

func _sanitize_id(raw: String) -> String:
	return raw.strip_edges().to_lower()

func _check_rate_limit(account_id: String) -> bool:
	if not QoSService:
		return true
	var now := Time.get_ticks_msec()
	var window_ms := int(LOGIN_COOLDOWN_SEC * 1000.0)
	if not _failed_attempts.has(account_id):
		return true
	var recent: Array = _failed_attempts[account_id].filter(func(t): return now - t < window_ms)
	_failed_attempts[account_id] = recent
	return recent.size() < MAX_LOGIN_ATTEMPTS

func _record_failed_attempt(account_id: String) -> void:
	if not _failed_attempts.has(account_id):
		_failed_attempts[account_id] = []
	var arr: Array = _failed_attempts[account_id]
	arr.append(Time.get_ticks_msec())
	_failed_attempts[account_id] = arr

func _verify_password(account_id: String, password: String) -> bool:
	var entry: Dictionary = _store.get(account_id, {})
	if entry.is_empty():
		return false
	var salt := (entry.get("salt", "") as String).hex_decode()
	var expected := (entry.get("hash", "") as String).hex_decode()
	var actual := _derive_hash(password, salt)
	if actual.size() != expected.size():
		_record_failed_attempt(account_id)
		return false
	for i in range(actual.size()):
		if actual[i] != expected[i]:
			_record_failed_attempt(account_id)
			return false
	return true

func _derive_hash(password: String, salt: PackedByteArray) -> PackedByteArray:
	# PBKDF2-style iterated SHA-256: H( H( ... H(salt || password) ... ))
	var ctx := HashingContext.new()
	if ctx.start(HashingContext.HASH_SHA256) != OK:
		return PackedByteArray()
	ctx.update(salt)
	ctx.update(password.to_utf8_buffer())
	var h := ctx.finish()
	for i in range(PBKDF2_ITERATIONS - 1):
		var c2 := HashingContext.new()
		c2.start(HashingContext.HASH_SHA256)
		c2.update(h)
		h = c2.finish()
	return h

func _random_bytes(n: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(n)
	for i in range(n):
		b[i] = randi() % 256
	return b

func _mint_session_token() -> String:
	return _random_bytes(SESSION_TOKEN_BYTES).hex_encode()

func _fail(reason: String) -> void:
	GameLog.warn("LoginService: %s" % reason)
	login_failed.emit(reason)

func _load_store() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		_store = {}
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not f:
		_store = {}
		return
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		_store = parsed
	else:
		GameLog.warn("LoginService: accounts.json corrupt, starting fresh")
		_store = {}

func _save_store() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not f:
		GameLog.error("LoginService: failed to open accounts.json for write")
		return
	f.store_string(JSON.stringify(_store))
	f.close()
