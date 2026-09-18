## SeedReceipt - Signed seed bundle for login verification
##
## Contains 4 character-scoped seeds (world, shard, instance, player),
## the world manifest hash, a timestamp, and an HMAC-SHA256 signature.
## Serialized as 200 bytes: 4*32 + 32 + 32 + 8 = 200
##
## PRD: labs/prd-login-seed-chain.md US-004
## Timestamp: issued_at is in Unix milliseconds (64-bit integer).
## Replay protection window: 60,000 ms (60 seconds).
extends Resource
class_name SeedReceipt

var world_seed: PackedByteArray = PackedByteArray()
var shard_seed: PackedByteArray = PackedByteArray()
var instance_seed: PackedByteArray = PackedByteArray()
var player_seed: PackedByteArray = PackedByteArray()
var manifest_hash: PackedByteArray = PackedByteArray()
var signature: PackedByteArray = PackedByteArray()
var issued_at: int = 0

## Serializes the payload for signing (excludes signature field).
## Payload: 4 seeds (4*32) + manifest_hash (32) + issued_at (8) = 168 bytes
func _payload_bytes() -> PackedByteArray:
	var buf := PackedByteArray()
	_write_32(buf, world_seed)
	_write_32(buf, shard_seed)
	_write_32(buf, instance_seed)
	_write_32(buf, player_seed)
	_write_32(buf, manifest_hash)
	_write_u64(buf, issued_at)
	return buf

## Signs the receipt with the server's HMAC key.
## Must be called before sending to client.
func sign(server_key: PackedByteArray) -> void:
	var payload := _payload_bytes()
	var hmac := HMACContext.new()
	if hmac.start(HashingContext.HASH_SHA256, server_key) != OK:
		return
	hmac.update(payload)
	signature = hmac.finish()

## Verifies the receipt signature against the server key.
## Includes 60-second replay protection based on issued_at timestamp.
## issued_at is in Unix milliseconds; tolerance is 60,000 ms.
func verify(server_key: PackedByteArray) -> bool:
	if signature.is_empty():
		return false

	# Check replay protection: receipt must be within 60,000 ms of issued_at.
	var now := Time.get_unix_time_from_system() * 1000  # Convert to milliseconds
	if now < issued_at:
		return false  # issued_at in the future
	if now - issued_at > 60000:
		return false  # expired (more than 60 seconds old)

	var payload := _payload_bytes()
	var hmac := HMACContext.new()
	if hmac.start(HashingContext.HASH_SHA256, server_key) != OK:
		return false
	hmac.update(payload)
	var expected := hmac.finish()
	if expected.size() != signature.size():
		return false
	for i in range(expected.size()):
		if expected[i] != signature[i]:
			return false
	return true

## Serializes to 200 bytes: 4 seeds (4*32) + manifest_hash (32) + signature (32) + issued_at (8)
func to_bytes() -> PackedByteArray:
	var buf := PackedByteArray()
	_write_32(buf, world_seed)
	_write_32(buf, shard_seed)
	_write_32(buf, instance_seed)
	_write_32(buf, player_seed)
	_write_32(buf, manifest_hash)
	_write_32(buf, signature)
	_write_u64(buf, issued_at)
	return buf

## Deserializes from 200 bytes.
static func from_bytes(b: PackedByteArray) -> SeedReceipt:
	var script = load("res://core/schemas/seed_receipt.gd")
	var receipt: SeedReceipt = script.new()
	var pos := 0
	receipt.world_seed = _read_32(b, pos); pos += 32
	receipt.shard_seed = _read_32(b, pos); pos += 32
	receipt.instance_seed = _read_32(b, pos); pos += 32
	receipt.player_seed = _read_32(b, pos); pos += 32
	receipt.manifest_hash = _read_32(b, pos); pos += 32
	receipt.signature = _read_32(b, pos); pos += 32
	receipt.issued_at = _read_u64(b, pos)
	return receipt

static func _write_32(buf: PackedByteArray, src: PackedByteArray) -> void:
	if src.size() < 32:
		var padded := PackedByteArray()
		padded.resize(32)
		for i in range(src.size()):
			padded[i] = src[i]
		buf.append_array(padded)
	else:
		buf.append_array(src.slice(0, 32))

static func _write_u64(buf: PackedByteArray, val: int) -> void:
	for i in range(8):
		buf.append((val >> (i * 8)) & 0xFF)

static func _read_32(b: PackedByteArray, pos: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(32)
	for i in range(32):
		if pos + i < b.size():
			out[i] = b[pos + i]
	return out

static func _read_u64(b: PackedByteArray, pos: int) -> int:
	var val: int = 0
	for i in range(8):
		if pos + i < b.size():
			val |= (b[pos + i] & 0xFF) << (i * 8)
	return val