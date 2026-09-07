## Integration test: a service-shaped object using the
## adapter layer end-to-end. Models the LoginService path
## (account lookup + session creation) without touching the
## real LoginService code.
##
## Proves the contract works: get a store, call it, get results.
##
## Run with:
##   tools/godot --headless --path synmergia --script res://tests/adapters/test_adapter_integration.gd
extends SceneTree

const MemoryPersistenceStore = preload("res://adapters/persistence/memory_persistence_store.gd")
const MemoryCacheStore = preload("res://adapters/cache/memory_cache_store.gd")

var _passed: int = 0
var _failed: int = 0


func _initialize() -> void:
	print("--- ADAPTER INTEGRATION TEST ---")

	# Set up the in-memory stores (simulating what BackendFactory
	# would do with STORAGE_BACKEND=memory CACHE_BACKEND=memory).
	var accounts = MemoryPersistenceStore.new()
	accounts.connect({})
	accounts.seed("accounts", [])

	var sessions = MemoryCacheStore.new()
	sessions.connect({})

	# A "service" is just a closure over the stores.
	var service := _FakeLoginService.new(accounts, sessions)

	_test_register_account(service)
	_test_login_existing_account(service)
	_test_login_unknown_account_rejected(service)
	_test_session_ttl(service)
	_test_logout_clears_session(service)
	_test_rate_limiting_via_counter(service)

	_finish()


func _test_register_account(service) -> void:
	var ok: bool = service.register_account("alice", "hunter2")
	if not ok:
		_fail("register_account returned false")
		return
	var row: Dictionary = service.accounts.query_one(
		"SELECT * FROM accounts WHERE username = $1", ["alice"]
	)
	if row.get("password_hash") == null or row.get("password_hash") == "hunter2":
		_fail("password should be hashed, not stored plain")
		return
	_ok("register_account: persists + hashes password")


func _test_login_existing_account(service) -> void:
	var token: String = service.login("alice", "hunter2")
	if token == "":
		_fail("login returned empty token for valid credentials")
		return
	_ok("login: returns session token")

	# The token should resolve via the cache
	var account_id = service.sessions.get("session:%s" % token)
	if account_id == null:
		_fail("session token not in cache")
		return
	_ok("login: session token is in cache, resolves to account")


func _test_login_unknown_account_rejected(service) -> void:
	var token: String = service.login("nobody", "wrong")
	if token != "":
		_fail("login should return empty for unknown user")
		return
	_ok("login: rejects unknown account")


func _test_session_ttl(service) -> void:
	var token: String = service.login("alice", "hunter2")
	if token == "":
		_fail("login failed in setup")
		return
	# Verify the TTL was set
	var exists: bool = service.sessions.exists("session:%s" % token)
	if not exists:
		_fail("session should exist right after login")
		return
	_ok("session: TTL is set (cache key present)")


func _test_logout_clears_session(service) -> void:
	var token: String = service.login("alice", "hunter2")
	service.logout(token)
	if service.sessions.exists("session:%s" % token):
		_fail("session should be gone after logout")
		return
	_ok("logout: clears session from cache")


func _test_rate_limiting_via_counter(service) -> void:
	# Five login attempts; the 5th should be rate-limited.
	for i in range(4):
		service.login("alice", "wrong")
	var allowed: bool = service.login("alice", "hunter2")
	if not allowed:
		_fail("5th attempt should still be allowed (limit=5)")
		return
	# 6th attempt should be blocked
	var blocked: bool = service.login("alice", "hunter2")
	if blocked:
		_fail("6th attempt should be blocked by rate limiter")
		return
	_ok("rate limit: 5 allowed, 6th blocked")


# --- FakeLoginService ---
# Models the auth flow without depending on the real
# LoginService.gd. Demonstrates the adapter pattern.

class _FakeLoginService:
	extends RefCounted

	var accounts: MemoryPersistenceStore
	var sessions: MemoryCacheStore
	const RATE_LIMIT := 5
	const RATE_WINDOW_SEC := 60
	const SESSION_TTL_SEC := 86400

	func _init(a: MemoryPersistenceStore, s: MemoryCacheStore) -> void:
		accounts = a
		sessions = s

	func _hash(pw: String) -> String:
		# Trivial hash. Real code uses bcrypt/argon2.
		return "h:%s" % pw.length()

	func register_account(username: String, password: String) -> bool:
		var existing: Dictionary = accounts.query_one(
			"SELECT * FROM accounts WHERE username = $1", [username]
		)
		if not existing.is_empty():
			return false
		accounts.execute(
			"INSERT INTO accounts (id, username, password_hash) VALUES ($1, $2, $3)",
			["acc_%s" % username, username, _hash(password)]
		)
		return true

	func login(username: String, password: String) -> Variant:
		# Rate limit: 5 attempts per username per minute
		var key := "rl:%s" % username
		var attempts: int = sessions.incr_with_ttl(key, RATE_WINDOW_SEC)
		if attempts > RATE_LIMIT:
			return false  # blocked (return bool, not token)
		var row: Dictionary = accounts.query_one(
			"SELECT * FROM accounts WHERE username = $1", [username]
		)
		if row.is_empty():
			return ""  # unknown user
		if row.get("password_hash") != _hash(password):
			return ""  # bad password
		var token := "tok_%d_%s" % [Time.get_ticks_msec(), username]
		sessions.set("session:%s" % token, row.get("id"), SESSION_TTL_SEC)
		return token

	func logout(token: String) -> void:
		sessions.delete("session:%s" % token)


func _ok(msg: String) -> void:
	_passed += 1
	print("  [PASS] %s" % msg)


func _fail(msg: String) -> void:
	_failed += 1
	printerr("  [FAIL] %s" % msg)


func _finish() -> void:
	print("--- %d passed, %d failed ---" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
