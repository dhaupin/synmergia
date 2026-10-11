## Tests for the seeded quantized-direction sector cache
extends SceneTree

const SectorCache = preload("res://core/frame/kv/sector_cache.gd")

func _init() -> void:
	var ok = true
	if not _test_sector_key_stability_and_spread():
		push_error("FAIL: sector_key_stability_and_spread")
		ok = false
	if not _test_bounds_via_lru_eviction():
		push_error("FAIL: bounds_via_lru_eviction")
		ok = false
	if not _test_eviction_preserves_answer_law():
		push_error("FAIL: eviction_preserves_answer_law")
		ok = false
	if not _test_multi_seed_coexistence_no_wholesale_clear():
		push_error("FAIL: multi_seed_coexistence_no_wholesale_clear")
		ok = false
	if not _test_clear_is_full_flush():
		push_error("FAIL: clear_is_full_flush")
		ok = false
	if not _test_poison_guard_rejects_nonfinite():
		push_error("FAIL: poison_guard_rejects_nonfinite")
		ok = false
	quit(0 if ok else 1)

static func _unit(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, y, z).normalized()

func _test_sector_key_stability_and_spread() -> bool:
	var seed_a := PackedByteArray([1, 2, 3])
	var seed_b := PackedByteArray([4, 5, 6])
	# Same direction + seed => same key.
	var d1: Vector3 = _unit(0.1, 0.2, 1.0)
	var d2: Vector3 = _unit(0.15, 0.3, 1.5)  # normalizes to the same dir
	assert(SectorCache.sector_key(d1, seed_a) == SectorCache.sector_key(d2, seed_a))
	# Different seed => never shares a bucket.
	assert(SectorCache.sector_key(d1, seed_a) != SectorCache.sector_key(d1, seed_b))
	# Neighboring distinct sectors get distinct keys (the 2048 law).
	var far: Vector3 = _unit(0.2, 0.2, 1.0)
	assert(SectorCache.sector_key(d1, seed_a) != SectorCache.sector_key(far, seed_a))
	return true

func _test_bounds_via_lru_eviction() -> bool:
	var c: RefCounted = SectorCache.new(4)
	var da := PackedByteArray([9])
	# Fill 5 distinct sectors across 2 seeds; capacity is 4.
	var got: Array = []
	var ok := true
	for i in [0, 1, 2, 3, 4]:
		got.append(_unit(0.01 + float(i) * 0.05, 1.0, 0.3))
	for i in [0, 1, 2, 3]:
		c.set_value(got[i], da, float(i))
	# The 5th insert evicts the LRU (index 0), NOT the whole cache:
	# survivors still answer, size bounded at 4.
	c.set_value(got[4], da, 99.0)
	if c.size() != 4:
		ok = false
	if c.get_value(got[4], da) != 99.0 or c.get_value(got[1], da) != 1.0:
		ok = false
	if c.has(got[0], da):
		ok = false  # LRU-evicted, not wholesale cleared
	return ok

func _test_eviction_preserves_answer_law() -> bool:
	# Pure-law discipline: after any eviction, a re-derive of the SAME
	# key must return the SAME value. Simulate with a pure mapper.
	var c: RefCounted = SectorCache.new(3)
	var da := PackedByteArray([7])
	var d: Vector3 = _unit(0.3, 1.0, 0.7)
	c.set_value(d, da, 42.0)
	# Force the key out.
	for i in [1, 2, 3]:
		c.set_value(_unit(0.5 + float(i) * 0.2, 1.0, 0.6), da, -1.0)
	assert(c.has(d, da) == false)
	# The pure law re-derives the same answer; set it again.
	c.set_value(d, da, 42.0)
	assert(c.get_value(d, da) == 42.0)
	return true

func _test_multi_seed_coexistence_no_wholesale_clear() -> bool:
	# THE bug this primitive exists for: two worlds alternating must
	# NOT clear each other's warm sectors. With capacity >= needs,
	# both seeds' caches stay fully warm across alternation.
	var c: RefCounted = SectorCache.new(64)
	var da := PackedByteArray([1, 1])
	var db := PackedByteArray([2, 2])
	var dirs: Array = []
	var out := true
	for i in [0, 1, 2, 3, 4, 5]:
		dirs.append(_unit(0.05 + float(i) * 0.1, 1.0, 0.4))
	for d in dirs:
		c.set_value(d, da, 1.0)
	for d in dirs:
		c.set_value(d, db, 2.0)
	# Alternate: re-read A, then write B, repeatedly -- nothing evicts.
	for _round in [0, 1, 2]:
		for d in dirs:
			if c.get_value(d, da) != 1.0:
				out = false
		for d in dirs:
			if c.get_value(d, db) != 2.0:
				out = false
			c.set_value(d, db, 2.0)
	return out

func _test_poison_guard_rejects_nonfinite() -> bool:
	# A non-finite law answer is never stored: the set REJECTS (false,
	# nothing written), so no hot sector can be served poisoned forever.
	# A NaN even dodges equality pins (NaN == NaN is false) -- the
	# guard stops it at the door instead.
	var c: RefCounted = SectorCache.new(4)
	var da := PackedByteArray([3])
	var d: Vector3 = _unit(0.4, 1.0, 0.2)
	if c.set_value(d, da, NAN):
		return false
	if c.set_value(d, da, INF):
		return false
	if c.set_value(d, da, -INF):
		return false
	if c.size() != 0:
		return false  # nothing written
	if c.has(d, da):
		return false
	# Finite values still store fine.
	if not c.set_value(d, da, 5.25):
		return false
	# Poisoned color components are rejected too.
	if c.set_value(d, da, Color(0.5, NAN, 0.5)):
		return false
	if not c.set_value(d, da, Color(0.5, 0.5, 0.5)):
		return false
	return true

func _test_clear_is_full_flush() -> bool:
	var c: RefCounted = SectorCache.new(8)
	var da := PackedByteArray([5])
	c.set_value(_unit(1.0, 0.1, 0.1), da, 3.0)
	c.set_value(_unit(0.1, 1.0, 0.1), da, 4.0)
	c.clear()
	var ok := true
	if c.size() != 0:
		ok = false
	if c.has(_unit(1.0, 0.1, 0.1), da):
		ok = false
	return ok
