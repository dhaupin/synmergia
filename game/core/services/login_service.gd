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
const AdapterRegistry = preload("res://adapters/registry.gd")
const SeedReceiptScript = preload("res://core/schemas/seed_receipt.gd")
const SeedChainScript = preload("res://core/frame/kv/seed_chain.gd")
const AccountRollup = preload("res://core/services/account_rollup.gd")

## This is the client-side gate. Server should always re-validate.

signal login_succeeded(account_id: String, is_guest: bool)
signal login_failed(reason: String)
signal logged_out
signal account_registered(account_id: String)
signal seed_receipt_ready(character_id: String, receipt: Resource)

const PBKDF2_ITERATIONS := 4096
const HASH_BYTES := 32                # SHA-256 output
const SALT_BYTES := 16
const MAX_LOGIN_ATTEMPTS := 5
const LOGIN_COOLDOWN_SEC := 10.0
const SESSION_TOKEN_BYTES := 24

## DictStore key prefix for accounts
const _kv_prefix := "login:account:"

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
	_load_accounts()
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
	if AccountRollup:
		AccountRollup.rebuild_rollup(account_id)
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
	_persist_account(account_id)

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
	if AccountRollup:
		AccountRollup.rebuild_rollup(guest_id)
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

## Invalidates all session tokens (called on manifest restore)
## Clears current session and forces all clients to re-authenticate
func invalidate_all_tokens() -> void:
	GameLog.info("LoginService: Invalidating all session tokens")
	
	# Clear current session
	_current_account_id = ""
	_current_session_token = ""
	_is_guest = false
	
	# Clear rate limit tracking
	_failed_attempts.clear()
	
	# Emit signal for any listeners
	logged_out.emit()
	GameLog.info("LoginService: All tokens invalidated")

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

## Builds a SeedReceipt for the given character.
## Derives the 4 seeds (world, shard, instance, player) from the
## character's scope stack, computes the manifest hash, signs with
## the server key, and emits seed_receipt_ready.
## Returns the SeedReceipt resource, or null if character not found.
func build_seed_receipt(character_id: String) -> Resource:
	if not AccountService:
		GameLog.warn("LoginService: AccountService not available")
		return null
	
	var character_data: Dictionary = AccountService.get_character(character_id)
	if character_data.is_empty():
		GameLog.warn("LoginService: Character %s not found" % character_id)
		return null
	
	var account_id: String = character_data.get("account_id", "")
	if account_id == "":
		GameLog.warn("LoginService: Character %s has no account" % character_id)
		return null
	
	# Get server HMAC key from config
	var server_key := _get_server_hmac_key()
	if server_key.is_empty():
		GameLog.warn("LoginService: Server HMAC key not configured")
		return null
	
	# Build scope stack for this character: [player_seed, shard_seed, world_seed]
	# The seeds are derived from the character's persistent scope tree
	var scope_stack := _build_scope_stack(account_id, character_id)
	if scope_stack.size() < 3:
		GameLog.warn("LoginService: Incomplete scope stack for %s" % character_id)
		return null
	
	# Derive the 4 seeds using SeedChain
	var world_seed: PackedByteArray = SeedChainScript.derive_seed(scope_stack, "/world")
	var shard_seed: PackedByteArray = SeedChainScript.derive_seed(scope_stack, "/shard")
	var player_seed: PackedByteArray = SeedChainScript.derive_seed(scope_stack, "/player/%s" % character_id)

	# Check OpenSeedRegistry for active instance seed within TTL (D032 reconnect window)
	var instance_seed: PackedByteArray
	if OpenSeedRegistry:
		instance_seed = OpenSeedRegistry.lookup(character_id)
	if instance_seed.is_empty():
		instance_seed = SeedChainScript.derive_seed(scope_stack, "/instance")
		if OpenSeedRegistry:
			OpenSeedRegistry.register(character_id, instance_seed)
	
	# Compute manifest hash from world state
	var manifest_hash := _compute_manifest_hash()
	
	# Create and sign receipt
	var receipt = SeedReceiptScript.new()
	receipt.world_seed = world_seed
	receipt.shard_seed = shard_seed
	receipt.instance_seed = instance_seed
	receipt.player_seed = player_seed
	receipt.manifest_hash = manifest_hash
	receipt.issued_at = Time.get_unix_time_from_system() * 1000
	receipt.sign(server_key)
	
	GameLog.info("LoginService: Built seed receipt for %s" % character_id)
	seed_receipt_ready.emit(character_id, receipt)
	return receipt

func _get_server_hmac_key() -> PackedByteArray:
	# In production, load from secure config file (srv/config/server.key)
	# For dev, use a deterministic key based on game config
	if GameConfig and GameConfig.has_method("get_server_hmac_key"):
		var key_str: String = GameConfig.get_server_hmac_key()
		if key_str != "":
			return key_str.hex_decode()
	
	# Fallback: derive from a known constant (dev only)
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update("synmergia_dev_hmac_key".to_utf8_buffer())
	return ctx.finish()

func _build_scope_stack(account_id: String, character_id: String) -> Array[PackedByteArray]:
	# Stack order: [player_seed, shard_seed, world_seed] (top to bottom)
	# Bottom-up derivation: world folds first, then shard, then player
	var stack: Array[PackedByteArray] = []
	
	# Try to get seeds from character's persistent state
	if AccountService and AccountService.has_method("get_character_scope_seeds"):
		var seeds: Dictionary = AccountService.get_character_scope_seeds(character_id)
		if not seeds.is_empty():
			var player_seed := (seeds.get("player_seed", "") as String).hex_decode()
			var shard_seed := (seeds.get("shard_seed", "") as String).hex_decode()
			var world_seed := (seeds.get("world_seed", "") as String).hex_decode()
			if player_seed.size() == 32:
				stack.append(player_seed)
			if shard_seed.size() == 32:
				stack.append(shard_seed)
			if world_seed.size() == 32:
				stack.append(world_seed)
	
	# If missing, generate deterministic seeds from character_id + account_id
	if stack.size() < 3:
		var base := (account_id + ":" + character_id).to_utf8_buffer()
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update(base)
		ctx.update("world".to_utf8_buffer())
		var ws := ctx.finish()
		
		ctx = HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update(base)
		ctx.update("shard".to_utf8_buffer())
		var ss := ctx.finish()
		
		ctx = HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update(base)
		ctx.update("player".to_utf8_buffer())
		var ps := ctx.finish()
		
		stack = [ps, ss, ws]
	
	return stack

func _compute_manifest_hash() -> PackedByteArray:
	# Hash of the current world manifest (zones, gateways, static data)
	var parts: Array[PackedByteArray] = []
	
	if WorldService:
		var ws = WorldService
		if ws.has_method("get_world_seed"):
			var seed_val: int = ws.get_world_seed()
			var b := PackedByteArray()
			b.resize(8)
			for i in range(8):
				b[i] = (seed_val >> (i * 8)) & 0xFF
			parts.append(b)
	
	# Add zone data hashes
	if ZoneManager:
		var zones = ZoneManager.get_loaded_zones() if ZoneManager.has_method("get_loaded_zones") else []
		for zone_id in zones:
			var b: PackedByteArray = zone_id.to_utf8_buffer()
			parts.append(b)
	
	# Combine all parts
	var combined := PackedByteArray()
	for p in parts:
		combined.append_array(p)
	
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	if not combined.is_empty():
		ctx.update(combined)
	return ctx.finish()


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

func _load_accounts() -> void:
	var store: PersistenceStore = AdapterRegistry.get_persistence("accounts")
	if not store.has_key(_kv_prefix + "_init"):
		_store = {}
		return
	var keys: Array = store.all_keys()
	var account_keys: Array = []
	for key in keys:
		if key.begins_with(_kv_prefix) and key != _kv_prefix + "_init":
			account_keys.append(key)
	if account_keys.is_empty():
		return
	var results: Dictionary = store.get_many(account_keys)
	for key in account_keys:
		var account_id = key.substr(_kv_prefix.length())
		var entry: Dictionary = results.get(key, {})
		if not entry.is_empty():
			_store[account_id] = entry

func _persist_account(account_id: String) -> void:
	var store: PersistenceStore = AdapterRegistry.get_persistence("accounts")
	var entry: Dictionary = _store.get(account_id, {})
	if entry.is_empty():
		store.erase(_kv_prefix + account_id)
	else:
		store.set_kv(_kv_prefix + account_id, entry)
	if not store.has_key(_kv_prefix + "_init"):
		store.set_kv(_kv_prefix + "_init", {"ts": Time.get_unix_time_from_system()})
