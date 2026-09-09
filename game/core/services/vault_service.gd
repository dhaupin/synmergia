## VaultService - Player and Guild vault management
## Handles secure item and gold storage
extends Node

## Singleton
static var instance: VaultService

const DictStore = preload("res://adapters/persistence/dict_store.gd")

const _kv_personal := "vault:personal:"
const _kv_guild := "vault:guild:"
const _kv_account := "vault:account:"

## Vault types
enum VaultType {
	PERSONAL,     # Individual player vault
	GUILD,        # Guild shared vault
	ACCOUNT       # Cross-character storage
}

## Vault permissions (for guild vaults)
enum Permission {
	VIEW = 1,
	DEPOSIT = 2,
	WITHDRAW = 4,
	MANAGE = 8  # Can modify permissions
}

## Player vaults: player_id -> vault_data
var _personal_vaults: Dictionary = {}

## Guild vaults: guild_id -> vault_data
var _guild_vaults: Dictionary = {}

## Account vaults: account_id -> vault_data
var _account_vaults: Dictionary = {}

## Vault limits
const PERSONAL_VAULT_SIZE: int = 100
const GUILD_VAULT_SIZE: int = 200
const ACCOUNT_VAULT_SIZE: int = 50
const PERSONAL_GOLD_LIMIT: int = 999999999
const GUILD_GOLD_LIMIT: int = 9999999999

## Signals
signal vault_opened(player_id: String, vault_type: VaultType)
signal item_deposited(player_id: String, vault_type: VaultType, item_id: String, quantity: int)
signal item_withdrawn(player_id: String, vault_type: VaultType, item_id: String, quantity: int)
signal gold_deposited(player_id: String, vault_type: VaultType, amount: int)
signal gold_withdrawn(player_id: String, vault_type: VaultType, amount: int)
signal permission_changed(guild_id: String, member_id: String, new_permissions: int)

func _ready() -> void:
	instance = self
	GameLog.info("VaultService: Ready")

	_load_vaults()

## ============================================================================
## VAULT INITIALIZATION
## ============================================================================

func init_personal_vault(player_id: String) -> void:
	if not _personal_vaults.has(player_id):
		_personal_vaults[player_id] = {
			"type": VaultType.PERSONAL,
			"slots": [],
			"gold": 0,
			"size": PERSONAL_VAULT_SIZE,
			"expanded": false
		}
		_persist_personal(player_id)
	GameLog.debug("VaultService: Initialized personal vault for %s" % player_id)

func init_guild_vault(guild_id: String, founder_id: String) -> void:
	if not _guild_vaults.has(guild_id):
		_guild_vaults[guild_id] = {
			"type": VaultType.GUILD,
			"slots": [],
			"gold": 0,
			"size": GUILD_VAULT_SIZE,
			"permissions": {},  # member_id -> permissions
			"rank_permissions": {}  # rank -> default permissions
		}
		# Founder gets all permissions
		_grant_guild_permissions(guild_id, founder_id, Permission.VIEW | Permission.DEPOSIT | Permission.WITHDRAW | Permission.MANAGE)
		_persist_guild(guild_id)
	GameLog.debug("VaultService: Initialized guild vault for %s" % guild_id)

func init_account_vault(account_id: String) -> void:
	if not _account_vaults.has(account_id):
		_account_vaults[account_id] = {
			"type": VaultType.ACCOUNT,
			"slots": [],
			"gold": 0,
			"size": ACCOUNT_VAULT_SIZE
		}
		_persist_account(account_id)
	GameLog.debug("VaultService: Initialized account vault for %s" % account_id)

## ============================================================================
## VAULT ACCESS
## ============================================================================

func open_vault(player_id: String, vault_type: VaultType) -> Dictionary:
	match vault_type:
		VaultType.PERSONAL:
			if not _personal_vaults.has(player_id):
				init_personal_vault(player_id)
			return _personal_vaults[player_id].duplicate(true)

		VaultType.GUILD:
			var guild_id := _get_player_guild_id(player_id)
			if guild_id.is_empty():
				return {}
			if not _guild_vaults.has(guild_id):
				return {}
			return _guild_vaults[guild_id].duplicate(true)

		VaultType.ACCOUNT:
			var account_id := _get_player_account_id(player_id)
			if account_id.is_empty():
				return {}
			if not _account_vaults.has(account_id):
				init_account_vault(account_id)
			return _account_vaults[account_id].duplicate(true)

	return {}

func close_vault(player_id: String, vault_type: VaultType) -> void:
	# TODO: Save vault state to database
	vault_opened.emit(player_id, vault_type)

## ============================================================================
## ITEM OPERATIONS
## ============================================================================

func deposit_item(player_id: String, vault_type: VaultType, item_data: Dictionary, quantity: int = 1) -> bool:
	if not _can_deposit(player_id, vault_type):
		GameLog.warn("VaultService: Player %s cannot deposit to vault type %d" % [player_id, vault_type])
		return false

	var vault: Dictionary = _get_vault(player_id, vault_type)
	if vault.is_empty():
		return false

	# Find existing stack or empty slot
	var item_id: String = item_data.get("id", "")
	var slot_index := _find_stackable_slot(vault, item_id, item_data.get("stack_size", 1))

	if slot_index >= 0:
		# Add to existing stack
		var slot: Dictionary = vault.slots[slot_index]
		slot.quantity = mini(slot.quantity + quantity, item_data.get("stack_size", 1))
	else:
		# Find empty slot
		slot_index = _find_empty_slot(vault)
		if slot_index < 0:
			GameLog.warn("VaultService: Vault is full")
			return false

		# Create new slot
		vault.slots[slot_index] = {
			"id": item_id,
			"quantity": quantity,
			"data": item_data
		}

	# Sync back to storage
	_persist_vault(player_id, vault_type)

	item_deposited.emit(player_id, vault_type, item_id, quantity)
	GameLog.debug("VaultService: %s deposited %d x %s" % [player_id, quantity, item_id])
	return true

func withdraw_item(player_id: String, vault_type: VaultType, slot_index: int, quantity: int = 1) -> Dictionary:
	if not _can_withdraw(player_id, vault_type):
		GameLog.warn("VaultService: Player %s cannot withdraw from vault type %d" % [player_id, vault_type])
		return {}

	var vault: Dictionary = _get_vault(player_id, vault_type)
	if vault.is_empty() or slot_index < 0 or slot_index >= vault.slots.size():
		return {}

	var slot: Dictionary = vault.slots[slot_index]
	if slot.is_empty():
		return {}

	var item_id: String = slot.get("id", "")
	var available: int = slot.get("quantity", 1)
	var to_withdraw := mini(quantity, available)

	if to_withdraw >= available:
		# Full stack
		vault.slots[slot_index] = {}
	else:
		# Partial
		slot.quantity -= to_withdraw

	# Sync back
	_persist_vault(player_id, vault_type)

	item_withdrawn.emit(player_id, vault_type, item_id, to_withdraw)
	GameLog.debug("VaultService: %s withdrew %d x %s" % [player_id, to_withdraw, item_id])

	return {
		"id": item_id,
		"quantity": to_withdraw,
		"data": slot.get("data", {})
	}

func move_item(from_vault: VaultType, to_vault: VaultType, player_id: String, from_slot: int, to_slot: int, quantity: int = 1) -> bool:
	# Withdraw from source
	var item := withdraw_item(player_id, from_vault, from_slot, quantity)
	if item.is_empty():
		return false

	# Deposit to destination
	if not deposit_item(player_id, to_vault, item, item.get("quantity", 1)):
		# Rollback - deposit back to source
		deposit_item(player_id, from_vault, item, item.get("quantity", 1))
		return false

	return true

## ============================================================================
## GOLD OPERATIONS
## ============================================================================

func deposit_gold(player_id: String, vault_type: VaultType, amount: int) -> bool:
	if not _can_deposit(player_id, vault_type):
		return false

	var limit := PERSONAL_GOLD_LIMIT if vault_type == VaultType.PERSONAL else GUILD_GOLD_LIMIT
	var vault: Dictionary = _get_vault(player_id, vault_type)
	if vault.is_empty():
		return false

	if vault.gold + amount > limit:
		amount = limit - vault.gold  # Cap at limit

	if amount <= 0:
		return false

	# Deduct from player
	if not _deduct_player_gold(player_id, amount):
		return false

	vault.gold += amount
	_persist_vault(player_id, vault_type)

	gold_deposited.emit(player_id, vault_type, amount)
	GameLog.debug("VaultService: %s deposited %d gold" % [player_id, amount])
	return true

func withdraw_gold(player_id: String, vault_type: VaultType, amount: int) -> bool:
	if not _can_withdraw(player_id, vault_type):
		return false

	var vault: Dictionary = _get_vault(player_id, vault_type)
	if vault.is_empty() or vault.gold < amount:
		return false

	# Add to player
	if not _add_player_gold(player_id, amount):
		return false

	vault.gold -= amount
	_persist_vault(player_id, vault_type)

	gold_withdrawn.emit(player_id, vault_type, amount)
	GameLog.debug("VaultService: %s withdrew %d gold" % [player_id, amount])
	return true

## ============================================================================
## GUILD VAULT PERMISSIONS
## ============================================================================

func _grant_guild_permissions(guild_id: String, member_id: String, permissions: int) -> void:
	if not _guild_vaults.has(guild_id):
		return
	_guild_vaults[guild_id].permissions[member_id] = permissions
	_persist_guild(guild_id)

func set_member_permission(guild_id: String, manager_id: String, member_id: String, permissions: int) -> bool:
	# Check if manager has MANAGE permission
	if not _has_guild_permission(guild_id, manager_id, Permission.MANAGE):
		return false

	_grant_guild_permissions(guild_id, member_id, permissions)
	permission_changed.emit(guild_id, member_id, permissions)
	return true

func _has_guild_permission(guild_id: String, member_id: String, permission: int) -> bool:
	if not _guild_vaults.has(guild_id):
		return false

	var perms: int = _guild_vaults[guild_id].permissions.get(member_id, 0)
	return (perms & permission) == permission

func _can_deposit(player_id: String, vault_type: VaultType) -> bool:
	match vault_type:
		VaultType.PERSONAL:
			return true
		VaultType.GUILD:
			return _has_guild_permission(_get_player_guild_id(player_id), player_id, Permission.DEPOSIT)
		VaultType.ACCOUNT:
			return true
	return false

func _can_withdraw(player_id: String, vault_type: VaultType) -> bool:
	match vault_type:
		VaultType.PERSONAL:
			return true
		VaultType.GUILD:
			return _has_guild_permission(_get_player_guild_id(player_id), player_id, Permission.WITHDRAW)
		VaultType.ACCOUNT:
			return true
	return false

## ============================================================================
## VAULT EXPANSION
## ============================================================================

const EXPANSION_SLOTS_PER_STEP: int = 10
const GOLD_COST_PER_SLOT: int = 1000  # 10 slots = 10,000 gold base

signal vault_expanded(player_id: String, vault_type: VaultType, new_size: int)

func expand_vault(player_id: String, vault_type: VaultType, slots: int) -> bool:
	var vault: Dictionary = _get_vault(player_id, vault_type)
	if vault.is_empty():
		return false

	# Calculate cost
	var cost: Dictionary = get_expansion_cost(vault_type, vault.get("size", 0))
	var gold_cost: int = cost.get("gold") if cost.has("gold") else 0

	# Check if player can afford it
	if gold_cost > 0:
		var player_gold: int = InventoryService.get_gold(player_id) if InventoryService else 0
		if player_gold < gold_cost:
			GameLog.warn("VaultService: Player %s cannot afford expansion (%d gold needed, %d owned)" % [player_id, gold_cost, player_gold])
			return false

		# Deduct gold
		if InventoryService and not InventoryService.modify_gold(player_id, -gold_cost):
			GameLog.warn("VaultService: Failed to deduct gold from player %s" % player_id)
			return false

	# Maximum expansion limits
	var base_size: int = GUILD_VAULT_SIZE if vault_type == VaultType.GUILD else PERSONAL_VAULT_SIZE
	var max_size: int = 500 if vault_type == VaultType.GUILD else 200
	var current_size: int = vault.get("size", base_size)

	if current_size + slots > max_size:
		# Refund if can't expand to requested amount
		if gold_cost > 0 and InventoryService:
			InventoryService.modify_gold(player_id, gold_cost)
		return false

	# Expand vault
	vault.size = current_size + slots
	vault.expanded = true
	_persist_vault(player_id, vault_type)

	vault_expanded.emit(player_id, vault_type, vault.size)
	GameLog.info("VaultService: Player %s expanded vault to %d slots for %d gold" % [player_id, vault.size, gold_cost])
	return true

func get_expansion_cost(vault_type: VaultType, current_size: int) -> Dictionary:
	var base_size: int = GUILD_VAULT_SIZE if vault_type == VaultType.GUILD else PERSONAL_VAULT_SIZE

	# Each expansion step adds EXPANSION_SLOTS_PER_STEP slots
	# Cost increases exponentially: base_cost * (1.5 ^ expansion_count)
	var expansion_count: int = maxi(0, (current_size - base_size) / EXPANSION_SLOTS_PER_STEP)
	var base_gold_cost: int = GOLD_COST_PER_SLOT * EXPANSION_SLOTS_PER_STEP

	# Exponential scaling: each expansion costs 50% more than the previous
	var gold_cost: float = base_gold_cost * pow(1.5, expansion_count)

	# Cap at a reasonable maximum (10 million gold)
	gold_cost = mini(gold_cost, 10000000)

	return {
		"gold": int(gold_cost),
		"premium": 0,
		"slots_offered": EXPANSION_SLOTS_PER_STEP,
		"next_size": mini(current_size + EXPANSION_SLOTS_PER_STEP, 500 if vault_type == VaultType.GUILD else 200)
	}

## ============================================================================
## HELPERS
## ============================================================================

func _get_vault(player_id: String, vault_type: VaultType) -> Dictionary:
	match vault_type:
		VaultType.PERSONAL:
			return _personal_vaults.get(player_id, {})
		VaultType.GUILD:
			var guild_id := _get_player_guild_id(player_id)
			return _guild_vaults.get(guild_id, {})
		VaultType.ACCOUNT:
			var account_id := _get_player_account_id(player_id)
			return _account_vaults.get(account_id, {})
	return {}

func _sync_vault(player_id: String, vault_type: VaultType, vault: Dictionary) -> void:
	_persist_vault(player_id, vault_type)

func _persist_vault(player_id: String, vault_type: VaultType) -> void:
	match vault_type:
		VaultType.PERSONAL:
			_persist_personal(player_id)
		VaultType.GUILD:
			var guild_id := _get_player_guild_id(player_id)
			if not guild_id.is_empty():
				_persist_guild(guild_id)
		VaultType.ACCOUNT:
			var account_id := _get_player_account_id(player_id)
			if not account_id.is_empty():
				_persist_account(account_id)

func _persist_personal(player_id: String) -> void:
	var store := DictStore.new()
	var key := _kv_personal + player_id
	if _personal_vaults.has(player_id) and not _personal_vaults[player_id].is_empty():
		store.set(key, _personal_vaults[player_id])
	else:
		store.erase(key)

func _persist_guild(guild_id: String) -> void:
	var store := DictStore.new()
	var key := _kv_guild + guild_id
	if _guild_vaults.has(guild_id) and not _guild_vaults[guild_id].is_empty():
		store.set(key, _guild_vaults[guild_id])
	else:
		store.erase(key)

func _persist_account(account_id: String) -> void:
	var store := DictStore.new()
	var key := _kv_account + account_id
	if _account_vaults.has(account_id) and not _account_vaults[account_id].is_empty():
		store.set(key, _account_vaults[account_id])
	else:
		store.erase(key)

func _load_vaults() -> void:
	var store := DictStore.new()
	var keys := store.all_keys()
	for key in keys:
		if key.begins_with(_kv_personal):
			var player_id := key.substr(_kv_personal.length())
			var data := store.get(key)
			if data:
				_personal_vaults[player_id] = data
		elif key.begins_with(_kv_guild):
			var guild_id := key.substr(_kv_guild.length())
			var data := store.get(key)
			if data:
				_guild_vaults[guild_id] = data
		elif key.begins_with(_kv_account):
			var account_id := key.substr(_kv_account.length())
			var data := store.get(key)
			if data:
				_account_vaults[account_id] = data

func _find_empty_slot(vault: Dictionary) -> int:
	var slots: Array = vault.get("slots", [])
	for i in range(slots.size()):
		if slots[i].is_empty():
			return i
	if slots.size() < vault.get("size", 100):
		vault.slots.append({})
		return slots.size() - 1
	return -1

func _find_stackable_slot(vault: Dictionary, item_id: String, max_stack: int) -> int:
	var slots: Array = vault.get("slots", [])
	for i in range(slots.size()):
		var slot: Dictionary = slots[i]
		if not slot.is_empty() and slot.get("id") == item_id:
			if slot.get("quantity", 1) < max_stack:
				return i
	return -1

func _get_player_guild_id(player_id: String) -> String:
	# TODO: Get from GuildService
	return ""

func _get_player_account_id(player_id: String) -> String:
	# TODO: Get from AccountService
	return ""

func _deduct_player_gold(player_id: String, amount: int) -> bool:
	if not InventoryService:
		GameLog.warn("VaultService: InventoryService not available for gold deduction")
		return false
	return InventoryService.modify_gold(player_id, -amount)

func _add_player_gold(player_id: String, amount: int) -> bool:
	if not InventoryService:
		GameLog.warn("VaultService: InventoryService not available for gold addition")
		return false
	return InventoryService.modify_gold(player_id, amount)

## ============================================================================
## PUBLIC API
## ============================================================================

static func singleton() -> VaultService:
	return instance

func get_vault_info(player_id: String, vault_type: VaultType) -> Dictionary:
	var vault := _get_vault(player_id, vault_type)
	if vault.is_empty():
		return {}
	return {
		"size": vault.get("size", 0),
		"used_slots": _count_used_slots(vault),
		"gold": vault.get("gold", 0)
	}

func _count_used_slots(vault: Dictionary) -> int:
	var count := 0
	for slot in vault.get("slots", []):
		if not slot.is_empty():
			count += 1
	return count
