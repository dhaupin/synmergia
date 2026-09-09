extends SceneTree

func _init() -> void:
	var ok := true
	if not _test_full_persistence_cycle():
		push_error("FAIL: full_persistence_cycle")
		ok = false
	if not _test_batch_operations():
		push_error("FAIL: batch_operations")
		ok = false
	quit(0 if ok else 1)

func _test_full_persistence_cycle() -> bool:
	# Simulate multiple services sharing the same adapter layer
	var store := DictStore.new()

	# Service A: PlayerConfig saves settings
	var player_settings := {
		"graphics_quality": 2,
		"vsync_enabled": true,
		"music_volume": 0.8
	}
	store.set("player:global", player_settings)

	# Service B: LoginService saves account
	var account := {
		"username": "testuser",
		"display_name": "Test User",
		"created_at": Time.get_unix_time_from_system()
	}
	store.set("login:account:testuser", account)

	# Service C: GuildService saves guild
	var guild := {
		"name": "Test Guild",
		"tag": "TEST",
		"leader_id": "player_1",
		"members": [{"id": "player_1", "rank": 0}]
	}
	store.set("guild:guild_1", guild)

	# Verify all data is readable
	var loaded_settings = store.get("player:global")
	if loaded_settings.get("graphics_quality") != 2:
		push_error("E2E: settings not persisted")
		return false

	var loaded_account = store.get("login:account:testuser")
	if loaded_account.get("username") != "testuser":
		push_error("E2E: account not persisted")
		return false

	var loaded_guild = store.get("guild:guild_1")
	if loaded_guild.get("name") != "Test Guild":
		push_error("E2E: guild not persisted")
		return false

	# Verify batch read
	var batch := store.get_many(["player:global", "login:account:testuser", "guild:guild_1"])
	if batch.size() != 3:
		push_error("E2E: batch read size mismatch")
		return false

	# Verify key enumeration
	var keys := store.all_keys()
	if keys.size() < 3:
		push_error("E2E: key enumeration missing keys")
		return false

	return true

func _test_batch_operations() -> bool:
	var store := DictStore.new()

	# Batch write
	var batch_data := {
		"batch:1": {"val": 1},
		"batch:2": {"val": 2},
		"batch:3": {"val": 3},
		"batch:empty": {}
	}
	store.set_batch(batch_data)

	# Verify non-empty persisted
	if store.get("batch:1").get("val") != 1:
		push_error("E2E: batch set failed")
		return false

	# Verify empty was erased
	if store.has("batch:empty"):
		push_error("E2E: batch set did not erase empty")
		return false

	# Batch delete
	store.erase_batch(["batch:1", "batch:2"])
	if store.has("batch:1") or store.has("batch:2"):
		push_error("E2E: batch erase failed")
		return false

	return true
