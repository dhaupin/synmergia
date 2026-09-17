extends SceneTree

const DictStore = preload("res://adapters/persistence/dict_store.gd")

func _init() -> void:
	var ok := true
	if not _test_service_persistence_flow():
		push_error("FAIL: service_persistence_flow")
		ok = false
	quit(0 if ok else 1)

func _test_service_persistence_flow() -> bool:
	# Simulate a service that uses DictStore for persistence
	var store := DictStore.new()
	var prefix := "test_service:"

	# 1. Service starts and loads state
	var player_id := "player_123"
	var initial_data: Dictionary = {
		"gold": 1000,
		"level": 5,
		"inventory": ["sword", "shield"],
		"settings": {"music_volume": 0.8}
	}
	store.set_kv(prefix + player_id, initial_data)

	# 2. Service reads back the data
	var loaded = store.get_kv(prefix + player_id)
	if loaded.get("gold") != 1000:
		push_error("Service integration: gold mismatch")
		return false
	if loaded.get("level") != 5:
		push_error("Service integration: level mismatch")
		return false
	if loaded.get("inventory") != ["sword", "shield"]:
		push_error("Service integration: inventory mismatch")
		return false

	# 3. Service updates data and persists
	loaded["gold"] = 1500
	loaded["level"] = 6
	loaded["inventory"].append("potion")
	store.set_kv(prefix + player_id, loaded)

	# 4. Service reads updated data
	var updated = store.get_kv(prefix + player_id)
	if updated.get("gold") != 1500:
		push_error("Service integration: updated gold mismatch")
		return false
	if updated.get("level") != 6:
		push_error("Service integration: updated level mismatch")
		return false
	if updated.get("inventory").size() != 3:
		push_error("Service integration: updated inventory size mismatch")
		return false

	# 5. Service deletes player data
	store.erase(prefix + player_id)
	if store.has_key(prefix + player_id):
		push_error("Service integration: erase failed")
		return false

	return true
