## AccountRollup - Account-level state aggregation across characters
## Aggregates playtime, gold, achievements, vault, and progression per account
extends Node

const DictStore = preload("res://adapters/persistence/dict_store.gd")

const _kv_prefix := "account_rollup:"

static var instance: Node

## Account rollup data: account_id -> rollup_data
var _rollups: Dictionary = {}

signal rollup_updated(account_id: String)
signal character_data_changed(account_id: String, character_id: String)

## Rollup data structure:
## {
##   "total_playtime": int,        # seconds across all characters
##   "total_gold": int,            # gold across all characters + account vault
##   "total_achievements": int,    # unique achievements unlocked across account
##   "account_vault_gold": int,    # gold in account vault
##   "account_vault_items": int,   # item count in account vault
##   "character_count": int,       # number of characters on account
##   "highest_level": int,         # highest character level
##   "total_levels": int,          # sum of all character levels
##   "last_updated": int,          # unix timestamp
##   "characters": {               # per-character breakdown
##     "character_id": {
##       "playtime": int,
##       "gold": int,
##       "achievements": int,
##       "level": int,
##       "class": String,
##       "species": String
##     }
##   }
## }

func _ready() -> void:
	instance = self
	_load_rollups()
	GameLog.info("AccountRollup: Ready (%d accounts loaded)" % _rollups.size())

## Build or rebuild rollup for an account from all its characters
func rebuild_rollup(account_id: String) -> Dictionary:
	if not AccountService:
		GameLog.warn("AccountRollup: AccountService not available")
		return {}

	var characters: Array = AccountService.get_account_characters(account_id)
	if characters.is_empty():
		var empty_rollup := _empty_rollup(account_id)
		_rollups[account_id] = empty_rollup
		_persist_rollup(account_id)
		return empty_rollup

	var rollup := _empty_rollup(account_id)
	var total_achievements: Dictionary = {}  # achievement_id -> true (for uniqueness)

	for char_data in characters:
		var char_id: String = char_data.get("id", "")
		if char_id == "":
			continue

		# Per-character rollup entry must exist before field writes; the
		# characters dict starts empty in _empty_rollup.
		if not rollup.characters.has(char_id):
			rollup.characters[char_id] = {
				"playtime": 0,
				"gold": 0,
				"level": 1,
				"class": "",
				"species": "",
				"achievements": 0
			}

		# Character playtime
		var playtime: int = char_data.get("playtime", 0)
		rollup.total_playtime += playtime
		rollup.characters[char_id].playtime = playtime

		# Character gold
		var gold: int = char_data.get("gold", 0)
		rollup.total_gold += gold
		rollup.characters[char_id].gold = gold

		# Character level
		var level: int = char_data.get("level", 1)
		rollup.total_levels += level
		if level > rollup.highest_level:
			rollup.highest_level = level
		rollup.characters[char_id].level = level

		# Character class/species
		rollup.characters[char_id].class = char_data.get("class_id", "")
		rollup.characters[char_id].species = char_data.get("species_id", "")

		# Character achievements
		if AchievementService:
			var unlocked: Array = AchievementService.get_unlocked_achievements(char_id)
			rollup.characters[char_id].achievements = unlocked.size()
			for ach_id in unlocked:
				if not total_achievements.has(ach_id):
					total_achievements[ach_id] = true

	rollup.total_achievements = total_achievements.size()
	rollup.character_count = characters.size()

	# Account vault gold
	if VaultService:
		var vault_data: Dictionary = VaultService.open_vault("", VaultService.VaultType.ACCOUNT)
		if not vault_data.is_empty():
			rollup.account_vault_gold = vault_data.get("gold", 0)
			rollup.account_vault_items = _count_vault_items(vault_data)

	rollup.total_gold += rollup.account_vault_gold
	rollup.last_updated = Time.get_unix_time_from_system()

	_rollups[account_id] = rollup
	_persist_rollup(account_id)

	rollup_updated.emit(account_id)
	GameLog.debug("AccountRollup: Rebuilt rollup for %s (chars=%d, gold=%d, playtime=%ds, achieves=%d)" % [
		account_id, rollup.character_count, rollup.total_gold, rollup.total_playtime, rollup.total_achievements])

	return rollup

## Get cached rollup for account (rebuilds if not cached)
func get_rollup(account_id: String) -> Dictionary:
	if not _rollups.has(account_id):
		return rebuild_rollup(account_id)
	return _rollups[account_id].duplicate(true)

## Get specific rollup field
func get_rollup_field(account_id: String, field: String) -> Variant:
	var rollup := get_rollup(account_id)
	return rollup.get(field, null)

## Get total playtime across account (seconds)
func get_total_playtime(account_id: String) -> int:
	return get_rollup(account_id).get("total_playtime", 0)

## Get total gold across account (characters + account vault)
func get_total_gold(account_id: String) -> int:
	return get_rollup(account_id).get("total_gold", 0)

## Get total unique achievements across account
func get_total_achievements(account_id: String) -> int:
	return get_rollup(account_id).get("total_achievements", 0)

## Get account vault gold
func get_account_vault_gold(account_id: String) -> int:
	return get_rollup(account_id).get("account_vault_gold", 0)

## Get highest character level on account
func get_highest_level(account_id: String) -> int:
	return get_rollup(account_id).get("highest_level", 0)

## Get character breakdown for account
func get_character_breakdown(account_id: String) -> Dictionary:
	return get_rollup(account_id).get("characters", {})

## Update a single character's data in the rollup (incremental update)
func update_character_data(account_id: String, character_id: String, char_data: Dictionary) -> void:
	if not _rollups.has(account_id):
		rebuild_rollup(account_id)
		return

	var rollup: Dictionary = _rollups[account_id]
	var old_char: Dictionary = rollup.characters.get(character_id, {})

	# Update playtime
	var old_playtime: int = old_char.get("playtime", 0)
	var new_playtime: int = char_data.get("playtime", 0)
	rollup.total_playtime += (new_playtime - old_playtime)
	rollup.characters[character_id].playtime = new_playtime

	# Update gold
	var old_gold: int = old_char.get("gold", 0)
	var new_gold: int = char_data.get("gold", 0)
	rollup.total_gold += (new_gold - old_gold)
	rollup.characters[character_id].gold = new_gold

	# Update level
	var old_level: int = old_char.get("level", 1)
	var new_level: int = char_data.get("level", 1)
	rollup.total_levels += (new_level - old_level)
	if new_level > rollup.highest_level:
		rollup.highest_level = new_level
	rollup.characters[character_id].level = new_level

	# Update class/species
	rollup.characters[character_id].class = char_data.get("class_id", "")
	rollup.characters[character_id].species = char_data.get("species_id", "")

	# Update achievements (recalculate for this character)
	if AchievementService:
		var unlocked: Array = AchievementService.get_unlocked_achievements(character_id)
		rollup.characters[character_id].achievements = unlocked.size()
		# Recalculate total unique achievements
		var total_achievements: Dictionary = {}
		for cid in rollup.characters:
			if AchievementService:
				var c_unlocked: Array = AchievementService.get_unlocked_achievements(cid)
				for ach_id in c_unlocked:
					total_achievements[ach_id] = true
		rollup.total_achievements = total_achievements.size()

	# Update account vault
	if VaultService:
		var vault_data: Dictionary = VaultService.open_vault("", VaultService.VaultType.ACCOUNT)
		if not vault_data.is_empty():
			rollup.account_vault_gold = vault_data.get("gold", 0)
			rollup.account_vault_items = _count_vault_items(vault_data)
		rollup.total_gold = 0
		for cid in rollup.characters:
			rollup.total_gold += rollup.characters[cid].get("gold", 0)
		rollup.total_gold += rollup.account_vault_gold

	rollup.last_updated = Time.get_unix_time_from_system()
	_persist_rollup(account_id)

	character_data_changed.emit(account_id, character_id)
	rollup_updated.emit(account_id)

## Called when a character is linked to an account
func on_character_linked(character_id: String, account_id: String) -> void:
	rebuild_rollup(account_id)

## Called when a character is unlinked from an account
func on_character_unlinked(character_id: String, account_id: String) -> void:
	rebuild_rollup(account_id)

## Called when account vault changes
func on_account_vault_changed(account_id: String) -> void:
	if not _rollups.has(account_id):
		return
	var rollup: Dictionary = _rollups[account_id]
	if VaultService:
		var vault_data: Dictionary = VaultService.open_vault("", VaultService.VaultType.ACCOUNT)
		if not vault_data.is_empty():
			rollup.account_vault_gold = vault_data.get("gold", 0)
			rollup.account_vault_items = _count_vault_items(vault_data)
		# Recalculate total gold
		rollup.total_gold = 0
		for cid in rollup.characters:
			rollup.total_gold += rollup.characters[cid].get("gold", 0)
		rollup.total_gold += rollup.account_vault_gold
		rollup.last_updated = Time.get_unix_time_from_system()
		_persist_rollup(account_id)
		rollup_updated.emit(account_id)

## Get rollup summary for display (UI-friendly)
func get_rollup_summary(account_id: String) -> Dictionary:
	var rollup := get_rollup(account_id)
	return {
		"account_id": account_id,
		"total_playtime_hours": rollup.total_playtime / 3600.0,
		"total_gold": rollup.total_gold,
		"total_achievements": rollup.total_achievements,
		"character_count": rollup.character_count,
		"highest_level": rollup.highest_level,
		"average_level": rollup.total_levels / float(rollup.character_count) if rollup.character_count > 0 else 0.0,
		"account_vault_gold": rollup.account_vault_gold,
		"account_vault_items": rollup.account_vault_items,
		"last_updated": rollup.last_updated
	}

## Static convenience method
static func get_rollup_static(account_id: String) -> Dictionary:
	var inst := singleton()
	if inst == null:
		return {}
	return inst.get_rollup(account_id)

static func rebuild_rollup_static(account_id: String) -> Dictionary:
	var inst := singleton()
	if inst == null:
		return {}
	return inst.rebuild_rollup(account_id)

static func singleton() -> AccountRollup:
	var ml: MainLoop = Engine.get_main_loop()
	if ml == null or not ml is SceneTree:
		return null
	var root: Window = (ml as SceneTree).root
	if root == null:
		return null
	return root.get_node_or_null("AccountRollup")

func _empty_rollup(account_id: String) -> Dictionary:
	return {
		"account_id": account_id,
		"total_playtime": 0,
		"total_gold": 0,
		"total_achievements": 0,
		"account_vault_gold": 0,
		"account_vault_items": 0,
		"character_count": 0,
		"highest_level": 0,
		"total_levels": 0,
		"last_updated": Time.get_unix_time_from_system(),
		"characters": {}
	}

func _count_vault_items(vault_data: Dictionary) -> int:
	var count := 0
	for slot in vault_data.get("slots", []):
		if not slot.is_empty():
			count += 1
	return count

func _load_rollups() -> void:
	var store := DictStore.new()
	_rollups = {}
	for key in store.all_keys():
		if key.begins_with(_kv_prefix):
			var account_id: String = key.substr(_kv_prefix.length())
			var data: Dictionary = store.get_kv(key)
			if not data.is_empty():
				_rollups[account_id] = data

func _persist_rollup(account_id: String) -> void:
	var store := DictStore.new()
	var key := _kv_prefix + account_id
	if _rollups.has(account_id):
		store.set_kv(key, _rollups[account_id])
	else:
		store.erase(key)