## AccountService - Account-level operations
## Manages accounts, character linking, and account-wide features
class_name AccountService
extends Node

# Singleton instance
static var instance: AccountService

# Accounts (account_id -> account_data)
var _accounts: Dictionary = {}

# Characters (character_id -> character_data)
var _characters: Dictionary = {}

# Character to account mapping (character_id -> account_id)
var _character_to_account: Dictionary = {}

# Account to characters mapping (account_id -> [character_ids])
var _account_characters: Dictionary = {}

# Settings
var _allow_same_account_trade: bool = false	 # Can trade between own characters
var _max_characters_per_account: int = 5

signal account_created(account_id: String)
signal character_linked(character_id: String, account_id: String)
signal character_unlinked(character_id: String)
signal same_account_trade_attempted(character1: String, character2: String, allowed: bool)

func _ready() -> void:
				instance = self
				Logger.info("AccountService: Ready")

## Create a new account
func create_account(account_id: String, email: String = "") -> Dictionary:
				# QoS: Rate limit account creation
				if not QoSService.rate_limit(account_id, "account_create"):
								Logger.debug("AccountService: Rate limited account creation for %s" % account_id)
								return {}
				
				if _accounts.has(account_id):
								Logger.warn("AccountService: Account %s already exists" % account_id)
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
				
				account_created.emit(account_id)
				Logger.info("AccountService: Created account %s" % account_id)
				
				return account

## Get account by ID
func get_account(account_id: String) -> Dictionary:
				return _accounts.get(account_id, {})

## Get account by character ID
func get_account_by_character(character_id: String) -> Dictionary:
				var account_id := _character_to_account.get(character_id, "")
				if account_id == "":
								return {}
				return get_account(account_id)

## Link a character to an account
func link_character(character_id: String, account_id: String, character_data: Dictionary = {}) -> bool:
				if not _accounts.has(account_id):
								Logger.warn("AccountService: Account %s does not exist" % account_id)
								return false

				# Security: Validate character name if provided
				if character_data.has("name"):
								var name_validation := SecurityService.validate_player_name(character_data["name"])
								if not name_validation.valid:
												Logger.warn("AccountService: Invalid character name '%s': %s" % [character_data["name"], name_validation.reason])
												return false

				if _character_to_account.has(character_id):
								Logger.warn("AccountService: Character %s already linked" % character_id)
								return false
				
				var chars: Array = _account_characters[account_id]
				if chars.size() >= _max_characters_per_account:
								Logger.warn("AccountService: Max characters reached for account %s" % account_id)
								return false
				
				# Store character data
				character_data["id"] = character_id
				character_data["account_id"] = account_id
				character_data["linked_at"] = Time.get_unix_time_from_system()
				_characters[character_id] = character_data
				
				# Create mappings
				_character_to_account[character_id] = account_id
				_account_characters[account_id].append(character_id)
				_accounts[account_id]["characters"] = _account_characters[account_id]
				
				character_linked.emit(character_id, account_id)
				Logger.info("AccountService: Linked character %s to account %s" % [character_id, account_id])
				
				return true

## Unlink a character from account
func unlink_character(character_id: String) -> bool:
				if not _character_to_account.has(character_id):
								return false
				
				var account_id := _character_to_account[character_id]
				_character_to_account.erase(character_id)
				
				if _account_characters.has(account_id):
								var chars: Array = _account_characters[account_id]
								chars.erase(character_id)
				
				_characters.erase(character_id)
				
				character_unlinked.emit(character_id)
				Logger.info("AccountService: Unlinked character %s from account %s" % [character_id, account_id])
				
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
				var account1 := _character_to_account.get(character1_id, "")
				var account2 := _character_to_account.get(character2_id, "")
				
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
				var account_id := _character_to_account.get(character1_id, "")
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
				Logger.info("AccountService: Same-account trade %s for %s" % ("enabled" if enabled else "disabled", account_id))
				return true

## Update last login
func update_last_login(account_id: String) -> void:
				if _accounts.has(account_id):
								_accounts[account_id]["last_login"] = Time.get_unix_time_from_system()

## Get online characters on account
func get_online_account_characters(account_id: String) -> Array:
				var char_ids: Array = _account_characters.get(account_id, [])
				var online: Array = []
				
				for char_id in char_ids:
								if PlayerService.instance and PlayerService.instance.is_online(char_id):
												online.append(char_id)
				
				return online

## Set account premium status
func set_premium(account_id: String, premium: bool) -> bool:
				if not _accounts.has(account_id):
								return false
				
				_accounts[account_id]["premium"] = premium
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
				
				Logger.info("AccountService: Deleted account %s" % account_id)
				return true
