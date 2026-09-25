## TestSeedReceipt
##
## Tests for SeedReceipt Resource (labs/prd-login-seed-chain.md)
## Covers US-001 through US-004 + edge cases
## issued_at is in Unix milliseconds; replay window is 60,000 ms.

extends SceneTree

const SeedReceiptScript = preload("res://core/schemas/seed_receipt.gd")

var ok: bool = true

func _init() -> void:
	_run_tests()
	quit(0 if ok else 1)

func _assert(cond: bool, msg: String) -> void:
	if not cond:
		push_error("FAIL: %s" % msg)
		ok = false
	else:
		print("PASS: %s" % msg)

func _run_tests() -> void:
	_test_instantiation()
	_test_defaults()
	_test_roundtrip_200_bytes()
	_test_verify_correct_key()
	_test_verify_wrong_key()
	_test_corrupted()
	_test_issued_at()
	_test_four_seeds_32_bytes()
	_test_sign_verify()
	_test_replay_window()

func _test_instantiation() -> void:
	var receipt = SeedReceiptScript.new()
	_assert(receipt != null, "SeedReceipt instantiates")
	_assert(receipt is Resource, "SeedReceipt extends Resource")

func _test_defaults() -> void:
	var receipt = SeedReceiptScript.new()
	_assert(receipt.world_seed.size() == 0, "world_seed empty default")
	_assert(receipt.shard_seed.size() == 0, "shard_seed empty default")
	_assert(receipt.instance_seed.size() == 0, "instance_seed empty default")
	_assert(receipt.player_seed.size() == 0, "player_seed empty default")
	_assert(receipt.manifest_hash.size() == 0, "manifest_hash empty default")
	_assert(receipt.signature.size() == 0, "signature empty default")
	_assert(receipt.issued_at == 0, "issued_at zero default")

func _test_roundtrip_200_bytes() -> void:
	var receipt = SeedReceiptScript.new()
	receipt.world_seed = _rand32()
	receipt.shard_seed = _rand32()
	receipt.instance_seed = _rand32()
	receipt.player_seed = _rand32()
	receipt.manifest_hash = _rand32()
	receipt.signature = _rand32()
	receipt.issued_at = 1700000000000
	var bytes = receipt.to_bytes()
	_assert(bytes.size() == 200, "to_bytes returns 200 bytes: %d" % bytes.size())
	var receipt2 = SeedReceiptScript.from_bytes(bytes)
	_assert(receipt2.world_seed == receipt.world_seed, "world_seed roundtrip")
	_assert(receipt2.shard_seed == receipt.shard_seed, "shard_seed roundtrip")
	_assert(receipt2.instance_seed == receipt.instance_seed, "instance_seed roundtrip")
	_assert(receipt2.player_seed == receipt.player_seed, "player_seed roundtrip")
	_assert(receipt2.manifest_hash == receipt.manifest_hash, "manifest_hash roundtrip")
	_assert(receipt2.signature == receipt.signature, "signature roundtrip")
	_assert(receipt2.issued_at == receipt.issued_at, "issued_at roundtrip")

func _test_verify_correct_key() -> void:
	var receipt = SeedReceiptScript.new()
	receipt.world_seed = _rand32()
	receipt.shard_seed = _rand32()
	receipt.instance_seed = _rand32()
	receipt.player_seed = _rand32()
	receipt.manifest_hash = _rand32()
	receipt.issued_at = Time.get_unix_time_from_system() * 1000
	var key = _rand32()
	receipt.sign(key)
	_assert(receipt.verify(key), "verify with correct key succeeds")

func _test_verify_wrong_key() -> void:
	var receipt = SeedReceiptScript.new()
	receipt.world_seed = _rand32()
	receipt.shard_seed = _rand32()
	receipt.instance_seed = _rand32()
	receipt.player_seed = _rand32()
	receipt.manifest_hash = _rand32()
	receipt.issued_at = Time.get_unix_time_from_system() * 1000
	var key1 = _rand32()
	var key2 = _rand32()
	receipt.sign(key1)
	_assert(not receipt.verify(key2), "verify with wrong key fails")

func _test_corrupted() -> void:
	var receipt = SeedReceiptScript.new()
	receipt.world_seed = _rand32()
	receipt.shard_seed = _rand32()
	receipt.instance_seed = _rand32()
	receipt.player_seed = _rand32()
	receipt.manifest_hash = _rand32()
	receipt.issued_at = Time.get_unix_time_from_system() * 1000
	var key = _rand32()
	receipt.sign(key)
	var bytes = receipt.to_bytes()
	bytes[0] = bytes[0] ^ 0xFF
	var receipt2 = SeedReceiptScript.from_bytes(bytes)
	_assert(not receipt2.verify(key), "corrupted receipt fails verification")

func _test_issued_at() -> void:
	var receipt = SeedReceiptScript.new()
	var now = Time.get_unix_time_from_system() * 1000
	receipt.issued_at = now
	var bytes = receipt.to_bytes()
	var receipt2 = SeedReceiptScript.from_bytes(bytes)
	_assert(receipt2.issued_at == now, "issued_at preserved")

func _test_four_seeds_32_bytes() -> void:
	var receipt = SeedReceiptScript.new()
	receipt.world_seed = _rand32()
	receipt.shard_seed = _rand32()
	receipt.instance_seed = _rand32()
	receipt.player_seed = _rand32()
	_assert(receipt.world_seed.size() == 32, "world_seed 32 bytes")
	_assert(receipt.shard_seed.size() == 32, "shard_seed 32 bytes")
	_assert(receipt.instance_seed.size() == 32, "instance_seed 32 bytes")
	_assert(receipt.player_seed.size() == 32, "player_seed 32 bytes")

func _test_sign_verify() -> void:
	var receipt = SeedReceiptScript.new()
	receipt.world_seed = _rand32()
	receipt.shard_seed = _rand32()
	receipt.instance_seed = _rand32()
	receipt.player_seed = _rand32()
	receipt.manifest_hash = _rand32()
	receipt.issued_at = Time.get_unix_time_from_system() * 1000
	var key = _rand32()
	receipt.sign(key)
	_assert(receipt.signature.size() == 32, "signature 32 bytes")
	_assert(receipt.verify(key), "sign then verify succeeds")

func _test_replay_window() -> void:
	var receipt = SeedReceiptScript.new()
	receipt.world_seed = _rand32()
	receipt.shard_seed = _rand32()
	receipt.instance_seed = _rand32()
	receipt.player_seed = _rand32()
	receipt.manifest_hash = _rand32()
	var key = _rand32()
	
	var now = Time.get_unix_time_from_system() * 1000
	receipt.issued_at = now
	receipt.sign(key)
	_assert(receipt.verify(key), "fresh receipt verifies")
	
	receipt.issued_at = now - 30000
	receipt.sign(key)
	_assert(receipt.verify(key), "30s old receipt verifies")
	
	receipt.issued_at = now - 90000
	receipt.sign(key)
	_assert(not receipt.verify(key), "90s old receipt fails verification")

func _rand32() -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(32)
	for i in range(32):
		b[i] = randi() % 256
	return b
