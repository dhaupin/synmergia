## Ported from vant axolotl lib/geometry/fragmenter.js
## Aperiodic Fragmenter — stateless data sharding via Knuth multiplicative hash.
##
## Vant lineage: lib/geometry/fragmenter.js (axolotl branch, v0.8.6)
## Pattern: Knuth multiplicative lattice key derivation, XOR-spread fragments.
##
## The fragmenter distributes data across N aperiodic lattice positions
## derived from a sequence integer using floor(phi * 2^32). No central
## manifest, no lookup tables. Given the same inputs, the same outputs.
##
## See labs/prd-geometry.md for the full spec.
extends RefCounted

class_name Fragmenter

const LATTICE_MULTIPLIER: int = 2654435769  # floor(phi * 2^32) = 0x9E3779B9


func derive_lattice_keys(sequence: int, num_fragments: int = 5) -> Array[String]:
	if num_fragments <= 0:
		return []

	var keys: Array[String] = []
	var base_hash: int = ((sequence * LATTICE_MULTIPLIER) & 0xFFFFFFFF)

	for i in range(num_fragments):
		var key: int = (((base_hash + i) * LATTICE_MULTIPLIER) & 0xFFFFFFFF)
		var combined: int = (key >> 16) ^ key
		keys.append(itoa(combined, 36))

	return keys


func fragment(data: Variant, num_fragments: int = 5) -> Array[Dictionary]:
	if num_fragments <= 0:
		return []

	var json: String
	if typeof(data) == TYPE_STRING:
		json = data
	else:
		json = JSON.stringify(data)

	var bytes: PackedByteArray = json.to_utf8()
	var total_bytes: int = bytes.size()
	var fragment_size: int = maxi(1, ceil(float(total_bytes) / float(num_fragments)))
	var fragments: Array[Dictionary] = []

	for i in range(num_fragments):
		var start: int = i * fragment_size
		var end: int = mini(start + fragment_size, total_bytes)
		var chunk_size: int = end - start

		if chunk_size <= 0:
			break

		var chunk: PackedByteArray = bytes.slice(start, end)
		var encoded: PackedByteArray = PackedByteArray()
		encoded.resize(chunk_size)

		for j in range(chunk_size):
			encoded[j] = chunk[j] ^ ((i + 1) * 137 >> 5)

		var checksum: int = 0
		for j in range(chunk_size):
			checksum = (checksum + encoded[j] * (j + 1)) % 65536

		fragments.append({
			shard = i,
			data = encoded.to_base64(),
			size = chunk_size,
			checksum = checksum
		})

	return fragments


func weld(fragments: Array) -> String:
	var normalized: Array[Dictionary] = []
	for f in fragments:
		if typeof(f) == TYPE_STRING:
			normalized.append({ shard = normalized.size(), data = f })
		else:
			normalized.append(f)

	normalized.sort_custom(_compare_shard)

	var buffers: PackedByteArray = PackedByteArray()
	for f in normalized:
		var decoded: PackedByteArray = f.data.base64_decode()
		var restored: PackedByteArray = PackedByteArray()
		restored.resize(decoded.size())
		var shard: int = f.shard

		for j in range(decoded.size()):
			restored[j] = decoded[j] ^ ((shard + 1) * 137 >> 5)

		buffers.append_array(restored)

	return buffers.get_string_from_utf8()


func _compare_shard(a: Dictionary, b: Dictionary) -> int:
	var a_shard: int = a.shard if a.has("shard") else 0
	var b_shard: int = b.shard if b.has("shard") else 0
	if a_shard < b_shard:
		return -1
	elif a_shard > b_shard:
		return 1
	return 0


func itoa(n: int, radix: int) -> String:
	var digits: String = "0123456789abcdefghijklmnopqrstuvwxyz"
	var result: String = ""
	var num: int = n

	if num == 0:
		return "0"

	while num > 0:
		result = digits[num % radix] + result
		num = int(num / radix)

	return result
