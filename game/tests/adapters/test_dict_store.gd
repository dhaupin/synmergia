extends SceneTree

func _init() -> void:
	var ok := true
	if not _test_dict_store_crud():
		push_error("FAIL: dict_store_crud")
		ok = false
	if not _test_dict_store_batch():
		push_error("FAIL: dict_store_batch")
		ok = false
	quit(0 if ok else 1)

func _test_dict_store_crud() -> bool:
	var store := DictStore.new()
	store.set_kv("test:key", {"foo": "bar", "num": 42})
	var data = store.get_kv("test:key")
	if data.is_empty():
		push_error("DictStore.get returned empty")
		return false
	if data.get("foo") != "bar" or data.get("num") != 42:
		push_error("DictStore.get returned wrong data: %s" % data)
		return false
	if not store.has_key("test:key"):
		push_error("DictStore.has returned false for existing key")
		return false
	store.erase("test:key")
	if store.has_key("test:key"):
		push_error("DictStore.has returned true after erase")
		return false
	return true

func _test_dict_store_batch() -> bool:
	var store := DictStore.new()
	var batch: Dictionary = {
		"batch:a": {"val": 1},
		"batch:b": {"val": 2},
		"batch:c": {"val": 3}
	}
	store.set_batch(batch)
	var a = store.get_kv("batch:a")
	var b = store.get_kv("batch:b")
	var c = store.get_kv("batch:c")
	if a.get("val") != 1 or b.get("val") != 2 or c.get("val") != 3:
		push_error("DictStore.set_batch failed: %s, %s, %s" % [a, b, c])
		return false
	var many = store.get_many(["batch:a", "batch:b"])
	if many.size() != 2:
		push_error("DictStore.get_many returned wrong size: %d" % many.size())
		return false
	store.erase_batch(["batch:a", "batch:b"])
	if store.has_key("batch:a") or store.has_key("batch:b"):
		push_error("DictStore.erase_batch failed")
		return false
	return true
