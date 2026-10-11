## CosmicEntropy — the world's flywheel: solar entropy in, weather out.
##
## The hit-and-miss engine pattern, on the frame's canonical Flywheel
## primitive (core/frame/srv/flywheel.gd): chaos weight accumulates
## (the wheel spins) from cosmic entropy events — Kp index readings,
## flare notices, observer reports. Momentum decays between events.
## When momentum reaches the threshold -> spark: a weather event
## fires, and the wheel resets. "Nature doesn't rush. But everything
## gets done."
##
## Consumers:
## - Weather: kp_to_band() turns the current Kp into a world weather
##   band (calm .. tempest) that world scopes can subscribe to.
## - Underworld: tide_amplitude() realizes the lore contract in
##   world_underworld.tres — "tides that follow the far-off weather".
## - AmbienceDriver / CosmicService: feed_kp() is the ingest seam the
##   NOAA sidecar (srv/noaa_kp_sidecar.py, port 8082) fills.
##
## Sources (production): NOAA SWPC planetary Kp, the same feed vant's
## encrypt.getCosmicEntropy() reads. Offline/test: feed_kp() accepts
## any recorded reading; the flywheel is deterministic given the same
## event sequence.
##
## Frame primitive: NO autoload, NO class_name, NO GameManager dependency.
extends RefCounted

const FlywheelScript = preload("res://core/frame/srv/flywheel.gd")
const WorldRegistryScript = preload("res://core/frame/srv/world_registry.gd")

## The orbiting body whose shadow shields the world from CME flux
## ("moon": world_moon.tres, parent_world == "main"). Empty string =
## no shielding (headless/script boots without the lattice) -- the
## default law is the UNSHIELDED sky; the shield is an improvement
## over it, never a dependency.
const SHIELD_WORLD_ID: String = "moon"

## Re-exported from the canonical Flywheel primitive (the one copy of
## these numbers); tests and tuning reads reference them here for
## backward compatibility with the pre-rebase API.
const SPARK_THRESHOLD: float = FlywheelScript.SPARK_THRESHOLD
const DECAY_PER_SEC: float = FlywheelScript.DECAY_PER_SEC

## Kp is published on 3-hour NOAA cadence; readings older than this
## are stale and stop feeding the momentum baseline.
const KP_STALE_SEC: float = 3.0 * 3600.0

## The world this shield protects (the parent the wind strikes).
const SHIELDED_WORLD_ID: String = "main"

## Aurora band multiplier ceiling when the shield is fully down (the
## body sits squarely in the wind). Even complete shadowing does not
## zero the aurora: a real CME bathes the whole magnetosphere; the
## moon trims the peak, not the event.
const SHIELD_MIN_AURORA: float = 0.35

## Weather bands, ascending with Kp. Boundaries are inclusive except
## the first element of each pair (band switches at the lower edge).
## Mirrors the NOAA geomagnetic activity scale, renamed for the world:
## quiet -> unsettled -> active -> storm -> severe storm -> extreme.
const WEATHER_BANDS: Array[Dictionary] = [
	{"name": "calm",     "min_kp": 0.0, "wind": 0.10, "aurora": 0.0},
	{"name": "unsettled","min_kp": 2.0, "wind": 0.30, "aurora": 0.15},
	{"name": "active",   "min_kp": 3.5, "wind": 0.50, "aurora": 0.40},
	{"name": "storm",    "min_kp": 4.5, "wind": 0.75, "aurora": 0.70},
	{"name": "tempest",  "min_kp": 6.0, "wind": 1.00, "aurora": 1.00},
]

## Underworld tide law (world_underworld.tres lore): tide amplitude
## follows the far-off weather. Max tide rise above still-water level,
## meters, at Kp 9 (the underworld has no sun; the weather IS its moon).
const TIDE_MAX_M: float = 2.5

## The wheel this system rides.
var wheel: FlywheelScript = FlywheelScript.new("cosmic")

## Newest reading.
var last_kp: float = 0.0
var last_kp_time: float = -INF

var _spark_listeners: Array[Callable] = []


func _init() -> void:
	wheel.on_spark(_relay_spark)


## Wire a spark listener; called with {wheel: "cosmic", kp, momentum}.
func on_spark(listener: Callable) -> void:
	_spark_listeners.append(listener)


## Relay from the canonical wheel, tagging our domain keys (kp rides
## along so listeners can route without querying last_kp).
func _relay_spark(payload: Dictionary) -> void:
	payload["kp"] = last_kp
	for listener in _spark_listeners:
		listener.call(payload)


## Feed one cosmic entropy reading. kp: NOAA planetary K-index 0..9.
## Returns the wheel momentum after accumulation.
func feed_kp(kp: float, at_time: float = 0.0) -> float:
	last_kp = clampf(kp, 0.0, 9.0)
	last_kp_time = at_time
	# Chaos weight: quadratic in Kp — a Kp 9 storm carries ~20x the
	# chaos of Kp 2. The sky is mostly quiet; storms must dominate.
	return wheel.accumulate(last_kp * last_kp * 2.5, {"kp": last_kp})


## Accumulate raw chaos (no Kp attached) — flare notices, observer
## reports, any cosmic-entropy source without its own reading.
func accumulate(chaos: float) -> float:
	return wheel.accumulate(chaos)


## Advance time: momentum decays. Call on the weather tick.
func tick(delta_sec: float) -> float:
	return wheel.tick(delta_sec)


## Convenience reads for consumers/tests (was var momentum pre-rebase).
func momentum() -> float:
	return wheel.momentum


func total_chaos() -> float:
	return wheel.total_chaos


func sparks() -> int:
	return wheel.sparks


## The accumulated sparkotal over the wheel's life (compat read for
## the old `sparks` var; kept so no consumer ever breaks).
func spark_count() -> int:
	return wheel.sparks


## True if the newest reading is fresh enough to trust.
func has_fresh_kp(now: float) -> bool:
	return (now - last_kp_time) <= KP_STALE_SEC


## Munich: the flywheel's own law is unchanged (threshold 100, decay
## 0.5/s) — those constants now live in ONE place, FlywheelScript.
## ---- Consumer reads ----

## Weather band for a Kp reading: the highest band whose min_kp is
## not exceeded. Deterministic — every client given the same Kp
## derives the same weather.
static func kp_to_band(kp: float) -> Dictionary:
	var band: Dictionary = WEATHER_BANDS[0]
	for b in WEATHER_BANDS:
		if kp >= b["min_kp"]:
			band = b
	return band


## Underworld tide amplitude (meters) for a Kp reading — the far-off
## weather pulling on the inside of the world. Still-water level at
## Kp 0 is 0.15 m (the strata glow breathes even in calm).
static func tide_amplitude(kp: float) -> float:
	var x: float = clampf(kp, 0.0, 9.0) / 9.0
	return 0.15 + TIDE_MAX_M * (x * x)


## The moon's CME-shield factor at an epoch (1 = wind fully reaches
## the world, 0 = the moon sits squarely in the stream). Resolves the
## shield body from the lattice lazily; a missing world or a non-
## orbiting body means no shield (factor 1). Instance method so
## tests can inject the epoch without an autoload clock.
func moon_shield_factor(epoch_days: float) -> float:
	var reg: RefCounted = WorldRegistryScript.new()
	reg.load_worlds()
	var shield_w = reg.get_world(SHIELD_WORLD_ID)
	var parent_w = reg.get_world(SHIELDED_WORLD_ID)
	if shield_w == null or parent_w == null or str(shield_w.parent_world) != SHIELDED_WORLD_ID:
		return 1.0
	return WorldRegistryScript.cme_shield_factor(shield_w, epoch_days)


## Aurora intensity AT AN EPOCH: the flat kp_to_band aurora with the
## moon's CME shadow applied. aurora lerps between the unshielded
## value and the SHIELD_MIN_AURORA floor as the shield closes.
## Deterministic: same epoch + same Kp => same aurora, on every
## client, no sync.
func aurora_at_epoch(kp: float, epoch_days: float) -> float:
	var base: float = float(kp_to_band(kp).get("aurora", 0.0))
	var shield: float = moon_shield_factor(epoch_days)
	return lerpf(base * SHIELD_MIN_AURORA, base, shield)


## Snapshot for persistence (weather scopes store this between ticks).
func snapshot() -> Dictionary:
	var out: Dictionary = wheel.snapshot()
	out["last_kp"] = last_kp
	out["last_kp_time"] = last_kp_time
	return out


func restore(data: Dictionary) -> void:
	wheel.restore(data)
	last_kp = float(data.get("last_kp", 0.0))
	last_kp_time = float(data.get("last_kp_time", -INF))
