extends SceneTree

func _init() -> void:
	var ok := true
	if not _test_ttl_expiration():
		push_error("FAIL: dict_store_ttl")
		ok = false
	if not _test_sweep_expired():
		push_error("FAIL: dict_store_sweep")
		ok = false
	quit(0 if ok else 1)

func _test_ttl_expiration() -> bool:
	var store := DictStore.new()
	store.set("ttl:test", {"val": 42}, 2)
	if not store.has_key("ttl:test"):
		push_error("DictStore key missing immediately after set")
		return false
	var data = store.get("ttl:test")
	if data.get("val") != 42:
		push_error("DictStore TTL get returned wrong data")
		return false
	# Wait for expiry
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	if store.has_key("ttl:test"):
		push_error("DictStore key still present after TTL expiry")
		return false
	return true

func _test_sweep_expired() -> bool:
	var store := DictStore.new()
	store.set("sweep:a", {"v": 1}, 1)
	store.set("sweep:b", {"v": 2}, 1)
	store.set("sweep:c", {"v": 3}, 0)  # no expiry
	var removed = store.sweep_expired()
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
