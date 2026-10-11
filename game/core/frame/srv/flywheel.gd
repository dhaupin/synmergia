## Flywheel -- the canonical chaos-accumulation primitive.
##
## One wheel, one law, every system: chaos in, momentum spins up and
## decays between events, and crossing the threshold fires a "spark"
## (hit-and-miss: one spark per fill, never wasted -- momentum resets
## on spark, leftover over the threshold is NOT carried over, matching
## CosmicEntropy's law that has been live in weather since v1).
## Consumers get a snapshot/restore pair so a wheel can persist.
##
## Every mechanism that *is* a flywheel in this codebase -- CosmicEntropy
## (cosmic/weather wheel) and FlywheelService (shard + per-player anomaly
## wheels) -- spins through this primitive, so "accumulate, decay,
## spark" can never mean two different things again.
##
## Frame primitive: NO autoload, NO class_name, NO GameManager dependency.
extends RefCounted

const SPARK_THRESHOLD: float = 100.0
const DECAY_PER_SEC: float = 0.5

## Name for routing (each system names its wheel, e.g. "cosmic",
## "shard:<id>", "player:<id>:<submeter>"). Also carried in sparks.
var wheel_name: String = "wheel"
## Momentum in the wheel.
var momentum: float = 0.0
## Total chaos fed over the wheel's life (deterministic audit trail).
var total_chaos: float = 0.0
## Sparks fired.
var sparks: int = 0
## Decay per second actually in use for this wheel (per-wheel override,
## defaults to DECAY_PER_SEC).
var decay_per_sec: float = DECAY_PER_SEC
## Momentum at which this wheel sparks (per-wheel tuning of the same
## law; the cosmic wheel uses the canonical 100.0).
var spark_threshold: float = SPARK_THRESHOLD
## Hard cap on momentum (0 = uncapped). A capped wheel clamps instead
## of growing without bound; it still sparks at the threshold.
var momentum_cap: float = 0.0

var _spark_listeners: Array[Callable] = []


func _init(p_wheel_name: String = "wheel", p_decay_per_sec: float = DECAY_PER_SEC) -> void:
	wheel_name = p_wheel_name
	decay_per_sec = p_decay_per_sec


## Wire a spark listener; called with a payload Dictionary:
## {wheel, momentum_at_spark, sparks, total_chaos, extra...}.
func on_spark(listener: Callable) -> void:
	_spark_listeners.append(listener)


## Feed chaos into the wheel. Returns momentum after this fill
## (post-spark). One spark per fill -- leftover does NOT carry over.
func accumulate(delta: float, extra: Dictionary = {}) -> float:
	if delta <= 0.0:
		return momentum
	total_chaos += delta
	momentum += delta
	if momentum_cap > 0.0 and momentum > momentum_cap:
		momentum = momentum_cap
	if momentum >= spark_threshold:
		return _fire(extra)
	return momentum


## Advance time: momentum decays. Call on the owning system's tick.
func tick(delta_sec: float) -> float:
	if delta_sec <= 0.0:
		return momentum
	momentum = maxf(0.0, momentum - decay_per_sec * delta_sec)
	return momentum


## Spark payload shape, shared by every wheel in the game.
func _fire(extra: Dictionary = {}) -> float:
	var at_spark: float = momentum
	momentum = 0.0
	sparks += 1
	var payload: Dictionary = {
		"wheel": wheel_name,
		"momentum": at_spark,
		"sparks": sparks,
		"total_chaos": total_chaos,
	}
	payload.merge(extra, true)
	for listener in _spark_listeners:
		listener.call(payload)
	return momentum


## Snapshot for persistence between ticks/restarts.
func snapshot() -> Dictionary:
	return {
		"wheel": wheel_name,
		"momentum": momentum,
		"total_chaos": total_chaos,
		"sparks": sparks,
	}


func restore(data: Dictionary) -> void:
	momentum = float(data.get("momentum", 0.0))
	total_chaos = float(data.get("total_chaos", 0.0))
	sparks = int(data.get("sparks", 0))
