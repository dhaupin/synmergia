## Seeded quantized-direction sector cache (the canonical frame cache).
## Wraps LRUCache with the documented terrain sector pattern: a
## quantized unit direction + the world seed fused into one String key.
## THIS is the canonical system for per-direction memoization on
## globes -- terrain_gen's hand-rolled Dictionary statics (height,
## water surface, biome blend, river channel) all ride it.
##
## Why LRU instead of clear-on-overflow: the old per-class statics
## kept a plain Dictionary, checked `size() > 524288`, and cleared
## WHOLESALE on overflow. Bounded memory, yes -- but one multi-world
## hot swap (or a scan far from the hot hemisphere) threw away every
## warm sector, and the next patch walk re-derived all of it. LRUCache
## evicts only the least-recently-used KEEPER at the same bound, so
## the hot set survives every walk including multi-seed alternation.
##
## Determinism contract: the cache answers a PURE function -- it
## never changes WHAT the law returns, only how fast. Same key must
## always mean the same (dir sector, seed, field) bucket, and eviction
## is invisible to callers (a miss just re-derives the same number).
## Probes pin bit-identical heights with the cache in or out.
##
## Frame rule: no autoload, no class_name -- consumers preload the
## const (same as definition_tree / folded_shell); co-located test
## (test_sector_cache.gd).
extends RefCounted

const LRU_CACHE = preload("res://core/frame/kv/lru_cache.gd")

## Sector quantization: a unit direction's components are scaled by
## this and floored to ints -- the same 2048-sector law every
## terrain_gen cache used, so EXACTLY the same buckets (a cache warm
## from the old statics would hit in the new one if both were alive;
## nothing invalidates across the swap because the law is pure).
const SECTORS_PER_AXIS: int = 2048

var _lru: LRUCache

## max_entries: per-cache bound (not per-CLASS global). Defaults to
## the old 524288 wholesale-clear capacity; pass a smaller number for
## niche caches (river specs etc.) -- memory stays linear in THIS
## number, never in how many caches exist.
func _init(max_entries: int = 524288) -> void:
	_lru = LRU_CACHE.new(max_entries)

## THE key law: quantized direction + "|" + seed hex. Shared by every
## consumer so cross-cache key confusion is impossible.
##
## LANE-H2 KEY-PACK: the quantized components live in [-2048, 2048]
## (a unit dir times SECTORS_PER_AXIS, truncated). str(Vector3i) cost
## ~0.53 us/call and was the dominant term in the ~0.73 us key build
## -- 1.55M key builds per level-6 patch. Offsetting by SECTORS_PER_AXIS
## puts each in [0, 4096], which fits 13 bits; the three fuse into ONE
## int (2.1x cheaper to stringify). The mapping is injective and keeps
## EXACTLY the same equivalence classes (same dir sector + seed => same
## key; different either => different key), so the test_sector_cache
## stability/spread pins still hold.
const _KEY_OFFSET: int = SECTORS_PER_AXIS
const _KEY_MASK: int = 0x1FFF

static func sector_key(dir: Vector3, world_seed: PackedByteArray) -> String:
	var x: int = (int(dir.x * float(SECTORS_PER_AXIS)) + _KEY_OFFSET) & _KEY_MASK
	var y: int = (int(dir.y * float(SECTORS_PER_AXIS)) + _KEY_OFFSET) & _KEY_MASK
	var z: int = (int(dir.z * float(SECTORS_PER_AXIS)) + _KEY_OFFSET) & _KEY_MASK
	return str((x << 26) | (y << 13) | z) + "|" + world_seed.hex_encode()

func get_value(dir: Vector3, world_seed: PackedByteArray) -> Variant:
	var key: String = sector_key(dir, world_seed)
	return _lru.get_value(key)

func has(dir: Vector3, world_seed: PackedByteArray) -> bool:
	return _lru.has(sector_key(dir, world_seed))

## Store. Value must be a PURE derivative of (dir sector, seed):
## same inputs, same value, forever -- the LRU may re-derive on miss,
## never serve a different answer for a served key.
##
## POISON GUARD: a non-finite float value is REJECTED at the door
## (returns false, nothing written): NaN/inf is never a legal answer
## to a pure law (heights/temperatures/tables all clamp to real
## numbers), and a poisoned sector would otherwise be served forever
## -- eviction-free if hot -- and NaN even dodges equality pins
## (NaN == NaN is false; a "same answer twice" check can't catch it).
## Color values are tuples of finite floats, checked component-wise.
func set_value(dir: Vector3, world_seed: PackedByteArray, value: Variant) -> bool:
	if value is float and not is_finite(value):
		return false
	if value is Color and not _color_finite(value):
		return false
	_lru.set_value(sector_key(dir, world_seed), value)
	return true

## Drop everything (backend reinstall / uninstall -- the one legal
## wholesale clear: the LAW changed, so warm sectors are not stale-able
## but wrong). NOT used for capacity management.
func clear() -> void:
	_lru.clear()

func size() -> int:
	return _lru.size()

func max_size() -> int:
	return _lru.max_size()

static func _color_finite(c: Color) -> bool:
	return is_finite(c.r) and is_finite(c.g) and is_finite(c.b) and is_finite(c.a)
