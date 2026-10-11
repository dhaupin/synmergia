## CosmicRng — the master RNG service: one entropy chain for the world.
##
## All world randomness flows through here so that any roll can be
## replayed, audited, and — when fed by cosmic entropy — genuinely
## unpredictable in a way seeded-only RNG is not.
##
## Design:
## - An entropy pool accumulates words from entropy sources: the
##   CosmicEntropy flywheel (solar Kp chaos, sparks), plus local
##   mixing (time, caller-salted randomness).
## - Streams are derived, never shared: each consumer (a loot table,
##   a daily crate, a spawn roll) gets a RandomNumberGenerator seeded
##   from pool_state + scope, so two consumers can never correlate
##   and a roll is reproducible from (pool_state, scope) alone.
## - Deterministic mode: with local mixing disabled and a fixed pool
##   state, the same scope yields the same stream — replayable for
##   tests and anticheat verification.
##
## Integration:
## - cosmic_entropy.gd (frame/srv) is the entropy SOURCE; sparks and
##   Kp readings stir the pool via stir().
## - LootTable.roll_drop(rng) accepts an injected RNG — pass
##   stream_for("loot", id) instead of letting it randomize().
##
## Frame primitive: NO autoload, NO class_name, NO GameManager dependency.
extends RefCounted

const CosmicEntropyScript = preload("res://core/frame/srv/cosmic_entropy.gd")

## Pool mixing constants (FNV-1a inspired, cheap and well-mixed).
const FNV_OFFSET: int = -2128831035  # 0x811C9DC5 as int32
const FNV_PRIME: int = 16777619

## Max stir events kept in the audit ring.
const AUDIT_SIZE: int = 64


var _pool: int = FNV_OFFSET
var _stir_count: int = 0
var _deterministic: bool = false
var _audit: Array[Dictionary] = []  # [{i, source, detail}]


## Create a master RNG. deterministic=true freezes local mixing
## (time-based salt) so identical stir sequences give identical
## streams — used by tests and anticheat replay.
func _init(deterministic: bool = false) -> void:
	_deterministic = deterministic
	if not deterministic:
		stir("boot", Time.get_unix_time_from_system())


## Stir one entropy word into the pool. source: "kp", "spark",
## "event", "hand" (manual). detail: any int-coercible value.
func stir(source: String, detail: Variant) -> void:
	_pool = _mix(_pool, source.hash())
	_pool = _mix(_pool, int(detail))
	_stir_count += 1
	_audit.append({"i": _stir_count, "source": source, "detail": detail})
	if _audit.size() > AUDIT_SIZE:
		_audit.pop_front()


## Stir from the cosmic flywheel: call on every Kp reading.
func stir_from_cosmic(cosmic: Variant) -> void:
	if cosmic == null:
		return
	stir("kp", cosmic.last_kp * 100.0)
	stir("chaos", int(cosmic.total_chaos))


## Derive a scoped stream. Same (scope, pool_state) -> same stream
## (replayable); different scopes never share sequences.
## Example scopes: "loot/daily_crate", "spawn/wolf_42", "quest/daily".
func stream_for(scope: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = _mix(_mix(_pool, scope.hash()), _stir_count)
	return rng


## Convenience: one scoped roll returning [0, 1).
func unit(scope: String) -> float:
	return stream_for(scope).randf()


## Convenience: one scoped integer in [from, to].
func randi_in(scope: String, from: int, to: int) -> int:
	return stream_for(scope).randi_range(from, to)


## Snapshot for persistence: the pool state is the world's RNG seed.
func snapshot() -> Dictionary:
	return {"pool": _pool, "stir_count": _stir_count}


func restore(data: Dictionary) -> void:
	_pool = int(data.get("pool", FNV_OFFSET))
	_stir_count = int(data.get("stir_count", 0))


func audit_tail(count: int = 8) -> Array[Dictionary]:
	var n := mini(count, _audit.size())
	return _audit.slice(_audit.size() - n)


static func _mix(acc: int, word: int) -> int:
	var x: int = acc ^ word
	x = (x * FNV_PRIME) & 0xFFFFFFFF
	# Fold to signed int32 range so GDScript int math stays stable.
	if x > 0x7FFFFFFF:
		x -= 0x100000000
	return x
