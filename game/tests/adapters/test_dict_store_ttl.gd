extends SceneTree

const DictStore = preload("res://adapters/persistence/dict_store.gd")

func _init() -> void:
	var ok := true
	if not _test_set_get():
		push_error("FAIL: dict_store_set_get")
		ok = false
	if not _test_sweep():
		push_error("FAIL: dict_store_sweep")
		ok = false
	quit(0 if ok else 1)

func _test_set_get() -> bool:
	var store := DictStore.new()
	store.set_kv("test:1", {"val": 42})
	if not store.has_key("test:1"):
		push_error("DictStore key missing after set")
		return false
	var data: Variant = store.get_kv("test:1")
	if data.get("val") != 42:
		push_error("DictStore get returned wrong data: %s" % data)
		return false
	if store.has_key("nonexistent"):
		push_error("DictStore has_key returned true for missing key")
		return false
	return true

func _test_sweep() -> bool:
	var store := DictStore.new()
	store.set_kv("sweep:a", {"v": 1}, 1)
	store.set_kv("sweep:b", {"v": 2}, 1)
	store.set_kv("sweep:c", {"v": 3}, 0)
	# Manually expire keys (TTL in the past)
	var now: float = Time.get_unix_time_from_system()
	store._expires["sweep:a"] = now - 10.0
	store._expires["sweep:b"] = now - 10.0
	var removed: int = store.sweep_expired()
	if removed < 2:
		push_error("DictStore sweep_expired removed %d, expected >= 2" % removed)
		return false
	if store.has_key("sweep:a") or store.has_key("sweep:b"):
		push_error("DictStore sweep did not remove expired keys")
		return false
	if not store.has_key("sweep:c"):
		push_error("DictStore sweep removed non-expired key")
		return false
	return true
