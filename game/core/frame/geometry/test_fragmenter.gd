## Tests for Vant Fragmenter
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
	if not _test_fragment_weld_roundtrip_empty():
		push_error("FAIL: fragment_weld_roundtrip_empty")
		ok = false
	if not _test_fragment_weld_roundtrip_simple():
		push_error("FAIL: fragment_weld_roundtrip_simple")
		ok = false
	if not _test_fragment_weld_roundtrip_json():
		push_error("FAIL: fragment_weld_roundtrip_json")
		ok = false
	if not _test_fragment_weld_roundtrip_large():
		push_error("FAIL: fragment_weld_roundtrip_large")
		ok = false
	if not _test_fragment_equal_distribution():
		push_error("FAIL: fragment_equal_distribution")
		ok = false
	if not _test_fragment_xor_spreading():
		push_error("FAIL: fragment_xor_spreading")
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
	if not _test_non_ascii_utf8():
		push_error("FAIL: non_ascii_utf8")
		ok = false
	if not _test_num_fragments_exceeds_data():
		push_error("FAIL: num_fragments_exceeds_data")
		ok = false
	if not _test_negative_sequence():
		push_error("FAIL: negative_sequence")
		ok = false
	if not _test_fragment_weld_checksum():
		push_error("FAIL: fragment_weld_checksum")
		ok = false
	if not _test_non_ascii_utf8():
		push_error("FAIL: non_ascii_utf8")
		ok = false
	if not _test_num_fragments_exceeds_data():
		push_error("FAIL: num_fragments_exceeds_data")
		ok = false
	if not _test_negative_sequence():
		push_error("FAIL: negative_sequence")
		ok = false
	if not _test_fragment_weld_checksum():
		push_error("FAIL: fragment_weld_checksum")
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
	return typeof(parsed) == TYPE_DICTIONARY && parsed == data


func _test_fragment_weld_roundtrip_large() -> bool:
	var frag: Fragmenter = Fragmenter.new()
	var data: String = "A" * 10000  # 10KB string
	var fragments: Array[Dictionary] = frag.fragment(data, 7)
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
	var bytes: PackedByteArray = data.to_utf8()
	for i in range(min(3, bytes.size())):
		var decoded: int = fragments[i].data.base64_decode()[0] ^ ((i+1)*137>>5)
		if decoded != bytes[i]:
			return false
	return true


func _test_weld_handles_string_fragments() -> bool:
	var frag: Fragmenter = Fragmenter.new()
	var original: String = "test"
	var fragments: Array[Dictionary] = frag.fragment(original, 2)
	var string_only: Array[String] = [fragments[0].data, fragments[1].data]
	var welded: String = frag.weld(string_only)
	return welded == original


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


func _test_non_ascii_utf8() -> bool:
	var frag: Fragmenter = Fragmenter.new()
	var data: String = "你好世界 🌍"
	var fragments: Array[Dictionary] = frag.fragment(data, 4)
	var welded: String = frag.weld(fragments)
	return welded == data


func _test_num_fragments_exceeds_data() -> bool:
	var frag: Fragmenter = Fragmenter.new()
	var data: String = "hi"
	var fragments: Array[Dictionary] = frag.fragment(data, 10)
	if fragments.size() >= 10:
		return false
	var welded: String = frag.weld(fragments)
	return welded == data


func _test_negative_sequence() -> bool:
	var frag: Fragmenter = Fragmenter.new()
	var keys1: Array[String] = frag.derive_lattice_keys(-1, 3)
	var keys2: Array[String] = frag.derive_lattice_keys(-1, 3)
	if keys1.size() != 3:
		return false
	for i in range(3):
		if keys1[i] != keys2[i]:
			return false
	return true


func _test_fragment_weld_checksum() -> bool:
	var frag: Fragmenter = Fragmenter.new()
	var data: String = "checksum_test"
	var fragments: Array[Dictionary] = frag.fragment(data, 3)
	var decoded: PackedByteArray = fragments[0].data.base64_decode()
	decoded[0] = (decoded[0] + 1) % 256
	fragments[0].data = decoded.to_base64()
	var welded: String = frag.weld(fragments)
	return welded != data