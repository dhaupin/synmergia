## AccountService - Account-level operations
## Manages accounts, character linking, and account-wide features
extends Node
# QoSService uses static shim methods (AGENTS.md allowlist); the const is required.
const QoSService = preload("res://core/autoload/qos_service.gd")
# NOTE: AdapterRegistry is an autoload; reference it directly.
const PersistenceStore = preload("res://adapters/persistence/persistence_store.gd")

# Singleton instance
static var instance: Node

# Accounts (account_id -> account_data)
var _accounts: Dictionary = {}

# Characters (character_id -> character_data)
var _characters: Dictionary = {}

# Character to account mapping (character_id -> account_id)
var _character_to_account: Dictionary = {}

# Account to characters mapping (account_id -> [character_ids])
var _account_characters: Dictionary = {}

## DictStore key prefix
const _kv_prefix := "account_service:"

# Settings
var _allow_same_account_trade: bool = false	 # Can trade between own characters
var _max_characters_per_account: int = 5

## Resolve AdapterRegistry autoload safely. Typed as Node because the
# AdapterRegistry script has no class_name (autoload shadow rule).
func _adapter_registry() -> Node:
	var root = get_tree().root if has_node("/root") else null
	if root:
		return root.get_node_or_null("AdapterRegistry")
	return null

signal account_created(account_id: String)
signal character_linked(character_id: String, account_id: String)
signal character_unlinked(character_id: String)
signal same_account_trade_attempted(character1: String, character2: String, allowed: bool)

func _ready() -> void:
	instance = self
	_load_state()
	GameLog.info("AccountService: Ready")

## Create a new account
func create_account(account_id: String, email: String = "") -> Dictionary:
	# QoS: Rate limit account creation
	if not QoSService.rate_limit(account_id, "account_create"):
		GameLog.debug("AccountService: Rate limited account creation for %s" % account_id)
		return {}

	if _accounts.has(account_id):
		GameLog.warn("AccountService: Account %s already exists" % account_id)
		return {}

	var account := {
		"id": account_id,
		"email": email,
		"created_at": Time.get_unix_time_from_system(),
		"last_login": Time.get_unix_time_from_system(),
		"characters": [],
		"settings": {
			"allow_same_account_trade": false,
			"two_factor_enabled": false
			},
			"premium": false
	}

	_accounts[account_id] = account
	_account_characters[account_id] = []
	_persist_account(account_id)

	account_created.emit(account_id)
	GameLog.info("AccountService: Created account %s" % account_id)

	return account

## Get account by ID
func get_account(account_id: String) -> Dictionary:
	return _accounts.get(account_id, {})

## Get account by character ID
func get_account_by_character(character_id: String) -> Dictionary:
	var account_id: String = _character_to_account.get(character_id, "")
	if account_id == "":
		return {}
	return get_account(account_id)

## Check if an account has admin privileges
func is_admin(account_id: String) -> bool:
	var account: Dictionary = get_account(account_id)
	var level: int = account.get("account_level", 0)
	return level >= GameConfig.Security.ADMIN_LEVEL

## Link a character to an account
func link_character(character_id: String, account_id: String, character_data: Dictionary = {}) -> bool:
	if not _accounts.has(account_id):
		GameLog.warn("AccountService: Account %s does not exist" % account_id)
		return false

	# Security: Validate character name if provided
	if character_data.has("name"):
		var name_validation := SecurityService.validate_player_name(character_data["name"])
		if not name_validation.valid:
			GameLog.warn("AccountService: Invalid character name '%s': %s" % [character_data["name"], name_validation.reason])
			return false

	if _character_to_account.has(character_id):
		GameLog.warn("AccountService: Character %s already linked" % character_id)
		return false

	var chars: Array = _account_characters[account_id]
	if chars.size() >= _max_characters_per_account:
		GameLog.warn("AccountService: Max characters reached for account %s" % account_id)
		return false

	# Store character data
	character_data["id"] = character_id
	character_data["account_id"] = account_id
	character_data["linked_at"] = Time.get_unix_time_from_system()
	_characters[character_id] = character_data
	_persist_character(character_id)

# Create mappings
	_character_to_account[character_id] = account_id
	_account_characters[account_id].append(character_id)
	_accounts[account_id]["characters"] = _account_characters[account_id]
	_persist_account(account_id)

	character_linked.emit(character_id, account_id)
	if AccountRollup:
		AccountRollup.on_character_linked(character_id, account_id)
	GameLog.info("AccountService: Linked character %s to account %s" % [character_id, account_id])

	return true

## Unlink a character from account
func unlink_character(character_id: String) -> bool:
	if not _character_to_account.has(character_id):
		return false

	var account_id: String = _character_to_account[character_id]
	_character_to_account.erase(character_id)

	if _account_characters.has(account_id):
		var chars: Array = _account_characters[account_id]
		chars.erase(character_id)

	_characters.erase(character_id)

	character_unlinked.emit(character_id)
	if AccountRollup:
		AccountRollup.on_character_unlinked(character_id, account_id)
	GameLog.info("AccountService: Unlinked character %s from account %s" % [character_id, account_id])

	return true

## Get characters for account
func get_account_characters(account_id: String) -> Array:
	var char_ids: Array = _account_characters.get(account_id, [])
	var chars: Array = []
	for char_id in char_ids:
		chars.append(_characters.get(char_id, {}))
	return chars

## Get character by ID
func get_character(character_id: String) -> Dictionary:
	return _characters.get(character_id, {})

## Check if two characters are on the same account
func is_same_account(character1_id: String, character2_id: String) -> bool:
	var account1: String = _character_to_account.get(character1_id, "")
	var account2: String = _character_to_account.get(character2_id, "")

	if account1 == "" or account2 == "":
		return false

	return account1 == account2

## Check if same-account trade is allowed
func can_same_account_trade(character1_id: String, character2_id: String) -> Dictionary:
	var result := {"allowed": false, "reason": ""}

	# Check if same account
	if not is_same_account(character1_id, character2_id):
		result["allowed"] = true
		return result

	# Same account - check settings
	var account_id: String = _character_to_account.get(character1_id, "")
	var account: Dictionary = _accounts.get(account_id, {})

	if account.is_empty():
		result["reason"] = "Account not found"
		return result

	if not account.get("settings", {}).get("allow_same_account_trade", false):
		result["reason"] = "Same-account trade disabled"
		same_account_trade_attempted.emit(character1_id, character2_id, false)
		return result

	result["allowed"] = true
	same_account_trade_attempted.emit(character1_id, character2_id, true)
	return result

## Enable/disable same-account trade for account
func set_same_account_trade(account_id: String, enabled: bool) -> bool:
	if not _accounts.has(account_id):
		return false

	_accounts[account_id]["settings"]["allow_same_account_trade"] = enabled
	_persist_account(account_id)
	GameLog.info("AccountService: Same-account trade %s for %s" % ["enabled" if enabled else "disabled", account_id])
	return true

## Update last login
func update_last_login(account_id: String) -> void:
	if _accounts.has(account_id):
		_accounts[account_id]["last_login"] = Time.get_unix_time_from_system()
	_persist_account(account_id)

## Get online characters on account
func get_online_account_characters(account_id: String) -> Array:
	var char_ids: Array = _account_characters.get(account_id, [])
	var online: Array = []

	for char_id in char_ids:
		# PlayerService may not be registered; guard the lookup
		if Engine.has_singleton("PlayerService"):
			var player_svc: Object = Engine.get_singleton("PlayerService")
			if player_svc and player_svc.has_method("is_online") and player_svc.call("is_online", char_id):
				online.append(char_id)

	return online

## Set account premium status
func set_premium(account_id: String, premium: bool) -> bool:
	if not _accounts.has(account_id):
		return false

	_accounts[account_id]["premium"] = premium
	_persist_account(account_id)
	return true

## Is account premium?
func is_premium(account_id: String) -> bool:
	var account: Dictionary = _accounts.get(account_id, {})
	return account.get("premium", false)

## Set account setting
func set_account_setting(account_id: String, key: String, value: Variant) -> bool:
	if not _accounts.has(account_id):
		return false

	_accounts[account_id]["settings"][key] = value
	_persist_account(account_id)
	return true

## Get account setting
func get_account_setting(account_id: String, key: String, default: Variant = null) -> Variant:
	var account: Dictionary = _accounts.get(account_id, {})
	return account.get("settings", {}).get(key, default)

## Delete account and all linked characters
func delete_account(account_id: String) -> bool:
	if not _accounts.has(account_id):
		return false

	# Unlink all characters
	var char_ids: Array = _account_characters.get(account_id, []).duplicate()
	for char_id in char_ids:
		unlink_character(char_id)

	_accounts.erase(account_id)
	_account_characters.erase(account_id)

	GameLog.info("AccountService: Deleted account %s" % account_id)
	return true

## == Persistence ============================================================

func _load_state() -> void:
	var registry = _adapter_registry()
	if not registry:
		return
	var store: PersistenceStore = registry.get_persistence("accounts")
	_accounts = {}
	_characters = {}
	_character_to_account = {}
	_account_characters = {}
	var keys: Array = store.all_keys()
	var account_keys: Array = []
	var char_keys: Array = []
	for key in keys:
		if key.begins_with(_kv_prefix + "account:"):
			account_keys.append(key)
		elif key.begins_with(_kv_prefix + "char:"):
			char_keys.append(key)
	
	if not account_keys.is_empty():
		var account_results: Dictionary = store.get_many(account_keys)
		for key in account_keys:
			var account_id = key.substr(_kv_prefix.length() + 8)
			_accounts[account_id] = account_results.get(key, {})
	
	if not char_keys.is_empty():
		var char_results: Dictionary = store.get_many(char_keys)
		for key in char_keys:
			var char_id = key.substr(_kv_prefix.length() + 5)
			_characters[char_id] = char_results.get(key, {})
	
	# Rebuild mappings from loaded data
	for char_id in _characters:
		var char_data = _characters[char_id]
		var account_id = char_data.get("account_id", "")
		if account_id != "":
			_character_to_account[char_id] = account_id
			if not _account_characters.has(account_id):
				_account_characters[account_id] = []
			_account_characters[account_id].append(char_id)
			if _accounts.has(account_id):
				_accounts[account_id]["characters"] = _account_characters[account_id]

func _persist_account(account_id: String) -> void:
	var registry = _adapter_registry()
	if not registry:
		return
	var store: PersistenceStore = registry.get_persistence("accounts")
	if _accounts.has(account_id):
		store.set_kv(_kv_prefix + "account:" + account_id, _accounts[account_id])
	else:
		store.erase(_kv_prefix + "account:" + account_id)

func _persist_character(character_id: String) -> void:
	var registry = _adapter_registry()
	if not registry:
		return
	var store: PersistenceStore = registry.get_persistence("accounts")
	if _characters.has(character_id):
		store.set_kv(_kv_prefix + "char:" + character_id, _characters[character_id])
	else:
		store.erase(_kv_prefix + "char:" + character_id)


func persist_all() -> void:
	var registry = _adapter_registry()
	if not registry:
		return
	var store: PersistenceStore = registry.get_persistence("accounts")
	var entries: Dictionary = {}
	for account_id in _accounts.keys():
		entries[_kv_prefix + "account:" + account_id] = _accounts[account_id]
	for char_id in _characters.keys():
		entries[_kv_prefix + "char:" + char_id] = _characters[char_id]
	if not entries.is_empty():
		store.set_batch(entries)
