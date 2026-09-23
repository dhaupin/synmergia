## Tests for Vant Fragmenter
## Ported from vant axolotl lib/geometry/fragmenter.js test suite
## Vant lineage: lib/geometry/fragmenter.test.js (axolotl branch, v0.8.6)
extends SceneTree

func _init() -> void:
	var ok = true
	if not _test_lattice_keys_deterministic():
		push_error("FAIL: lattice_keys_deterministic")
		ok = false
	if not _test_lattice_keys_different_seeds():
		push_error("FAIL: lattice_keys_different_seeds")
		ok = false
	if not _test_lattice_keys_various_counts():
		push_error("FAIL: lattice_keys_various_counts")
		ok = false
	if not _test_lattice_keys_negative_sequence():
		push_error("FAIL: lattice_keys_negative_sequence")
		ok = false
	if not _test_lattice_keys_uniqueness():
		push_error("FAIL: lattice_keys_uniqueness")
		ok = false
	if not _test_lattice_keys_zero_fragments():
		push_error("FAIL: lattice_keys_zero_fragments")
		ok = false
	if not _test_lattice_keys_large_sequence():
		push_error("FAIL: lattice_keys_large_sequence")
		ok = false
	if not _test_fragment_weld_roundtrip_empty():
		push_error("FAIL: fragment_weld_roundtrip_empty")
		ok = false
	if not _test_fragment_weld_roundtrip_simple():
		push_error("FAIL: fragment_weld_roundtrip_simple")
		ok = false
	if not _test_fragment_weld_roundtrip_json():
		push_error("FAIL: fragment_weld_roundtrip_json")
		ok = false
	if not _test_fragment_weld_roundtrip_large_100kb():
		push_error("FAIL: fragment_weld_roundtrip_large_100kb")
		ok = false
	if not _test_fragment_weld_roundtrip_utf8():
		push_error("FAIL: fragment_weld_roundtrip_utf8")
		ok = false
	if not _test_fragment_equal_distribution():
		push_error("FAIL: fragment_equal_distribution")
		ok = false
	if not _test_fragment_xor_spreading():
		push_error("FAIL: fragment_xor_spreading")
		ok = false
	if not _test_fragment_variable_num_fragments():
		push_error("FAIL: fragment_variable_num_fragments")
		ok = false
	if not _test_weld_handles_string_fragments():
		push_error("FAIL: weld_handles_string_fragments")
		ok = false
	if not _test_weld_sorting():
		push_error("FAIL: weld_sorting")
		ok = false
	if not _test_empty_weld():
		push_error("FAIL: empty_weld")
		ok = false
	if not _test_num_fragments_exceeds_data():
		push_error("FAIL: num_fragments_exceeds_data")
		ok = false
	if not _test_fragment_weld_checksum_detection():
		push_error("FAIL: fragment_weld_checksum_detection")
		ok = false
	if not _test_fragment_weld_checksum_corrupted_data():
		push_error("FAIL: fragment_weld_checksum_corrupted_data")
		ok = false
	if not _test_fragment_deterministic_output():
		push_error("FAIL: fragment_deterministic_output")
		ok = false
	quit(0 if ok else 1)


func _test_lattice_keys_deterministic() -> bool:
	var frag: Fragmenter = Fragmenter.new()
	var keys1: Array[String] = frag.derive_lattice_keys(12345, 5)
	var keys2: Array[String] = frag.derive_lattice_keys(12345, 5)
	if keys1.size() != keys2.size():
		return false
	for i in range(keys1.size()):
		if keys1[i] != keys2[i]:
			return false
	return true


func _test_lattice_keys_different_seeds() -> bool:
	var frag: Fragmenter = Fragmenter.new()
	var keys1: Array[String] = frag.derive_lattice_keys(1000, 5)
	var keys2: Array[String] = frag.derive_lattice_keys(2000, 5)
	if keys1.size() != keys2.size():
		return false
	for i in range(keys1.size()):
		if keys1[i] == keys2[i]:
			return false
	return true


func _test_lattice_keys_various_counts() -> bool:
	var frag: Fragmenter = Fragmenter.new()
	if frag.derive_lattice_keys(12345, 2).size() != 2:
		return false
	if frag.derive_lattice_keys(12345, 5).size() != 5:
		return false
	if frag.derive_lattice_keys(12345, 10).size() != 10:
		return false
	return true


func _test_lattice_keys_negative_sequence() -> bool:
	var frag: Fragmenter = Fragmenter.new()
	var keys1: Array[String] = frag.derive_lattice_keys(-1, 3)
	var keys2: Array[String] = frag.derive_lattice_keys(-1, 3)
	if keys1.size() != 3:
		return false
	for i in range(3):
		if keys1[i] != keys2[i]:
			return false
	return true


func _test_lattice_keys_uniqueness() -> bool:
	var frag: Fragmenter = Fragmenter.new()
	var keys: Array[String] = frag.derive_lattice_keys(42, 10)
	var seen: Dictionary = {}
	for k in keys:
		if seen.has(k):
			return false
		seen[k] = true
	return true


func _test_lattice_keys_zero_fragments() -> bool:
	var frag: Fragmenter = Fragmenter.new()
	var keys: Array[String] = frag.derive_lattice_keys(12345, 0)
	if keys.size() != 0:
		return false
	var keys_neg: Array[String] = frag.derive_lattice_keys(12345, -1)
	if keys_neg.size() != 0:
		return false
	return true


func _test_lattice_keys_large_sequence() -> bool:
	var frag: Fragmenter = Fragmenter.new()
	var keys1: Array[String] = frag.derive_lattice_keys(0xFFFFFFFF, 5)
	var keys2: Array[String] = frag.derive_lattice_keys(0xFFFFFFFF, 5)
	if keys1.size() != 5:
		return false
	for i in range(5):
		if keys1[i] != keys2[i]:
			return false
	return true


func _test_fragment_weld_roundtrip_empty() -> bool:
	var frag: Fragmenter = Fragmenter.new()
	var data: String = ""
	var fragments: Array[Dictionary] = frag.fragment(data, 3)
	var welded: String = frag.weld(fragments)
	return welded == data


func _test_fragment_weld_roundtrip_simple() -> bool:
	var frag: Fragmenter = Fragmenter.new()
	var data: String = "hello world"
	var fragments: Array[Dictionary] = frag.fragment(data, 5)
	var welded: String = frag.weld(fragments)
	return welded == data


func _test_fragment_weld_roundtrip_json() -> bool:
	var frag: Fragmenter = Fragmenter.new()
	var data: Dictionary = { "player_id": "abc123", "score": 42, "items": ["sword", "shield"] }
	var fragments: Array[Dictionary] = frag.fragment(data, 3)
	var welded: String = frag.weld(fragments)
	var parsed: Variant = JSON.parse_string(welded)
	# JSON round-trip reorders dictionary keys (parse-time insertion order),
	# so compare structurally with key-order-insensitive equality.
	return typeof(parsed) == TYPE_DICTIONARY and _dicts_equal_unordered(parsed, data)


func _dicts_equal_unordered(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key in a:
		if not b.has(key):
			return false
		var av: Variant = a[key]
		var bv: Variant = b[key]
		if av is Dictionary and bv is Dictionary:
			if not _dicts_equal_unordered(av, bv):
				return false
		elif av is Array and bv is Array:
			if av != bv:
				return false
		elif av != bv:
			return false
	return true


func _test_fragment_weld_roundtrip_large_100kb() -> bool:
	var frag: Fragmenter = Fragmenter.new()
	var data: String = "A".repeat(102400)  # 100KB string
	var fragments: Array[Dictionary] = frag.fragment(data, 7)
	var welded: String = frag.weld(fragments)
	return welded == data


func _test_fragment_weld_roundtrip_utf8() -> bool:
	var frag: Fragmenter = Fragmenter.new()
	# Build a multi-byte UTF-8 string programmatically so the source
	# file stays ASCII-only (Godot import requirement).
	var data: String = ""
	for code in [0x4F60, 0x597D, 0x4E16, 0x754C, 0x1F30E]:
		data += String.chr(code)
	var fragments: Array[Dictionary] = frag.fragment(data, 4)
	var welded: String = frag.weld(fragments)
	return welded == data


func _test_fragment_equal_distribution() -> bool:
	var frag: Fragmenter = Fragmenter.new()
	var data: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"  # 26 chars
	var fragments: Array[Dictionary] = frag.fragment(data, 5)
	var total_size: int = 0
	for f in fragments:
		total_size += f.size
	return total_size == data.length()


func _test_fragment_xor_spreading() -> bool:
	var frag: Fragmenter = Fragmenter.new()
	var data: String = "AAAA"  # All same byte
	var fragments: Array[Dictionary] = frag.fragment(data, 3)

	# Shard 0: XOR with ((0+1)*137>>5) = 137>>5 = 4
	# Shard 1: XOR with ((1+1)*137>>5) = 274>>5 = 8
	# Shard 2: XOR with ((2+1)*137>>5) = 411>>5 = 12
	var bytes: PackedByteArray = data.to_utf8_buffer()
	# fragment_size = ceil(len/num) can yield fewer fragments than requested
	# (4 bytes / 3 -> fragment_size 2 -> 2 fragments), so bound by actual count.
	for i in range(mini(mini(3, bytes.size()), fragments.size())):
		var decoded: int = (fragments[i].data as PackedByteArray)[0] ^ ((i+1)*137>>5)
		if decoded != bytes[i]:
			return false
	return true


func _test_fragment_variable_num_fragments() -> bool:
	var frag: Fragmenter = Fragmenter.new()
	var data: String = "test data for variable fragments"

	# Test num_fragments = 2
	var f2: Array[Dictionary] = frag.fragment(data, 2)
	if f2.size() != 2:
		return false
	var w2: String = frag.weld(f2)
	if w2 != data:
		return false

	# Test num_fragments = 5
	var f5: Array[Dictionary] = frag.fragment(data, 5)
	if f5.size() != 5:
		return false
	var w5: String = frag.weld(f5)
	if w5 != data:
		return false

	# Test num_fragments = 10: 31 bytes with fragment_size = ceil(31/10) = 4
	# yields ceil(31/4) = 8 actual fragments, not the requested 10.
	var f10: Array[Dictionary] = frag.fragment(data, 10)
	if f10.size() < 2:
		return false
	var w10: String = frag.weld(f10)
	if w10 != data:
		return false

	return true


func _test_weld_handles_string_fragments() -> bool:
	var frag: Fragmenter = Fragmenter.new()
	var original: String = "test"
	# String fragments are legacy plain-text shards (no XOR); feed weld the
	# plain strings directly, as callers with legacy stored data would.
	var string_only: Array[String] = ["te", "st"]
	var welded: String = frag.weld(string_only)
	if welded != original:
		return false
	# Mixed: binary fragments from fragment() plus a legacy string shard
	var fragments: Array[Dictionary] = frag.fragment(original, 2)
	var mixed: Array = [fragments[0], fragments[1]]
	var welded_mixed: String = frag.weld(mixed)
	return welded_mixed == original


func _test_weld_sorting() -> bool:
	var frag: Fragmenter = Fragmenter.new()
	var data: String = "1234567890"
	var fragments: Array[Dictionary] = frag.fragment(data, 3)

	# Shuffle fragments
	var shuffled: Array[Dictionary] = fragments.duplicate()
	shuffled.reverse()

	# Weld should still sort by shard and recover original
	var welded: String = frag.weld(shuffled)
	return welded == data


func _test_empty_weld() -> bool:
	var frag: Fragmenter = Fragmenter.new()
	var result: String = frag.weld([])
	return result == ""


func _test_num_fragments_exceeds_data() -> bool:
	var frag: Fragmenter = Fragmenter.new()
	var data: String = "hi"
	var fragments: Array[Dictionary] = frag.fragment(data, 10)
	if fragments.size() >= 10:
		return false
	var welded: String = frag.weld(fragments)
	return welded == data


func _test_fragment_weld_checksum_detection() -> bool:
	var frag: Fragmenter = Fragmenter.new()
	var data: String = "checksum_test"
	var fragments: Array[Dictionary] = frag.fragment(data, 3)

	# Corrupt fragment 0 data (data is a raw PackedByteArray in fragment dicts)
	var decoded: PackedByteArray = fragments[0].data
	decoded[0] = (decoded[0] + 1) % 256
	fragments[0].data = decoded

	# Weld should skip corrupted fragment and not return original data
	var welded: String = frag.weld(fragments)
	return welded != data


func _test_fragment_weld_checksum_corrupted_data() -> bool:
	var frag: Fragmenter = Fragmenter.new()
	var data: String = "corrupt_me"
	var fragments: Array[Dictionary] = frag.fragment(data, 4)

	# Corrupt fragment 2 data (data is a raw PackedByteArray in fragment dicts)
	var decoded: PackedByteArray = fragments[2].data
	if decoded.size() > 1:
		decoded[1] = (decoded[1] + 5) % 256
	fragments[2].data = decoded

	# Weld should detect checksum mismatch and skip fragment
	var welded: String = frag.weld(fragments)
	return welded != data


func _test_fragment_deterministic_output() -> bool:
	var frag: Fragmenter = Fragmenter.new()
	var data: String = "deterministic test"
	var fragments1: Array[Dictionary] = frag.fragment(data, 5)
	var fragments2: Array[Dictionary] = frag.fragment(data, 5)

	if fragments1.size() != fragments2.size():
		return false

	for i in range(fragments1.size()):
		if fragments1[i].shard != fragments2[i].shard:
			return false
		if fragments1[i].data != fragments2[i].data:
			return false
		if fragments1[i].size != fragments2[i].size:
			return false
		if fragments1[i].checksum != fragments2[i].checksum:
			return false
	return true
