extends SceneTree

# Smoke test for AccountRollup service
# Run: godot --headless --path . --script res://tests/test_account_rollup.gd

var _pass := 0
var _fail := 0

# Resolve services via root (autoloads are children of /root)
var AccountRollup
var AccountService
var LoginService
var VaultService
var AchievementService

func _initialize() -> void:
	AccountRollup = root.get_node_or_null("AccountRollup")
	AccountService = root.get_node_or_null("AccountService")
	LoginService = root.get_node_or_null("LoginService")
	VaultService = root.get_node_or_null("VaultService")
	AchievementService = root.get_node_or_null("AchievementService")

	print("--- ACCOUNT ROLLUP TEST ---")

	# 1. AccountRollup autoload present
	_assert("AccountRollup service present", AccountRollup != null)

	if not AccountRollup:
		_finish()
		return

	# 2. Test empty rollup for new account
	var test_account := "rollup_test_%d" % Time.get_ticks_msec()
	var rollup := AccountRollup.get_rollup(test_account)
	_assert("Empty rollup has correct structure", rollup.has("account_id"))
	_assert("Empty rollup total_playtime is 0", rollup.total_playtime == 0)
	_assert("Empty rollup total_gold is 0", rollup.total_gold == 0)
	_assert("Empty rollup total_achievements is 0", rollup.total_achievements == 0)
	_assert("Empty rollup character_count is 0", rollup.character_count == 0)
	_assert("Empty rollup highest_level is 0", rollup.highest_level == 0)

	# 3. Create account and link characters via AccountService
	if AccountService:
		AccountService.create_account(test_account, "")
		var linked1 := AccountService.link_character("char_1", test_account, {"name": "Hero1", "class_id": "warrior", "species_id": "human", "level": 10, "gold": 5000, "playtime": 3600})
		_assert("Link character 1", linked1)
		var linked2 := AccountService.link_character("char_2", test_account, {"name": "Hero2", "class_id": "mage", "species_id": "akkan", "level": 5, "gold": 2000, "playtime": 1800})
		_assert("Link character 2", linked2)

	# 4. Rebuild rollup and verify aggregation
	var rebuilt := AccountRollup.rebuild_rollup(test_account)
	_assert("Rebuild returns rollup", not rebuilt.is_empty())
	_assert("Rollup character_count = 2", rebuilt.character_count == 2)
	_assert("Rollup total_gold = 7000 (5000+2000)", rebuilt.total_gold == 7000)
	_assert("Rollup total_playtime = 5400 (3600+1800)", rebuilt.total_playtime == 5400)
	_assert("Rollup highest_level = 10", rebuilt.highest_level == 10)
	_assert("Rollup total_levels = 15 (10+5)", rebuilt.total_levels == 15)

	# 5. Test get_rollup (cached)
	var cached := AccountRollup.get_rollup(test_account)
	_assert("Cached rollup matches rebuilt", cached.total_gold == rebuilt.total_gold)

	# 6. Test get_rollup_summary
	var summary := AccountRollup.get_rollup_summary(test_account)
	_assert("Summary has account_id", summary.has("account_id"))
	_assert("Summary total_playtime_hours = 1.5", abs(summary.total_playtime_hours - 1.5) < 0.01)
	_assert("Summary total_gold = 7000", summary.total_gold == 7000)
	_assert("Summary character_count = 2", summary.character_count == 2)
	_assert("Summary highest_level = 10", summary.highest_level == 10)
	_assert("Summary average_level = 7.5", abs(summary.average_level - 7.5) < 0.01)

	# 7. Test account vault integration
	if VaultService:
		VaultService.init_account_vault(test_account)
		# Deposit gold to account vault
		# Note: VaultService.open_vault requires player_id, but for account vault it gets account_id from player
		# We'll test the rollup's vault tracking directly
		var vault_data := VaultService.open_vault("", VaultService.VaultType.ACCOUNT)
		if not vault_data.is_empty():
			vault_data.gold = 10000
			# Manually trigger persist to update rollup
			VaultService._persist_account(test_account)
			var updated_rollup := AccountRollup.get_rollup(test_account)
			_assert("Account vault gold tracked", updated_rollup.account_vault_gold == 10000)
			_assert("Total gold includes vault", updated_rollup.total_gold == 17000)

	# 8. Test character unlink triggers rebuild
	if AccountService:
		AccountService.unlink_character("char_1")
		var after_unlink := AccountRollup.get_rollup(test_account)
		_assert("After unlink character_count = 1", after_unlink.character_count == 1)
		_assert("After unlink total_gold = 2000", after_unlink.total_gold == 2000)
		_assert("After unlink highest_level = 5", after_unlink.highest_level == 5)

	# 9. Test static singleton methods
	var static_rollup := AccountRollup.get_rollup_static(test_account)
	_assert("Static get_rollup works", static_rollup.total_gold == 2000)

	# 10. Test new account gets empty rollup
	var new_account := "new_rollup_%d" % Time.get_ticks_msec()
	var empty := AccountRollup.get_rollup_static(new_account)
	_assert("New account gets empty rollup", empty.character_count == 0 and empty.total_gold == 0)

	# 11. Test update_character_data incremental update
	if AccountService:
		AccountService.link_character("char_3", test_account, {"name": "Hero3", "class_id": "rogue", "species_id": "synthetic", "level": 8, "gold": 3000, "playtime": 2000})
		AccountRollup.update_character_data(test_account, "char_3", {"playtime": 2500, "gold": 3500, "level": 9})
		var updated := AccountRollup.get_rollup(test_account)
		_assert("Incremental update playtime", updated.characters["char_3"].playtime == 2500)
		_assert("Incremental update gold", updated.characters["char_3"].gold == 3500)
		_assert("Incremental update level", updated.characters["char_3"].level == 9)

	_finish()

func _finish() -> void:
	print("")
	print("--- ACCOUNT ROLLUP TEST: %d passed, %d failed ---" % [_pass, _fail])
	quit(_fail)

func _assert(name: String, cond: bool) -> void:
	if cond:
		print("  [OK] %s" % name)
		_pass += 1
	else:
		print("  [FAIL] %s" % name)
		_fail += 1