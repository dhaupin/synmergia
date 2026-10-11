## CosmicService — the one live cosmic flywheel in the world.
##
## Consolidation seam (this session's parity work): before now every
## consumer built its OWN CosmicEntropy instance (AmbienceDriver made a
## fresh one per scene) and flywheels had two unrelated laws. Now:
##
## - ONE wheel lives here, on the frame's canonical Flywheel primitive,
##   fed by real NOAA SWPC Kp (planetary K-index 0..9).
## - Sparks fire through the SAME shape every wheel reports and are
##   bridged onto EventHub.cosmic_weather_spark so gameplay can listen
##   (thunder staged events, aurora visuals, quest hooks) without
##   touching the frame.
## - Snapshot/restore keeps the flywheel alive across server restarts.
##
## Ingest: the srv/noaa_kp_sidecar.py (port 8082, stdlib only) polls
## NOAA SWPC every 5 minutes and serves {kp, time}; this service polls
## THE SIDECAR (not NOAA directly) every KP_POLL_SEC. If the sidecar is
## down, the wheel keeps its last reading until the frame's own
## staleness law (KP_STALE_SEC) demotes weather to the trad fallback —
## the world never crashes because the sun went quiet.
##
## Autoload registered in project.godot after SignService (needs the
## sky clock for deterministic test feeds; live reads use unix time).
extends Node

const CosmicEntropyScript = preload("res://core/frame/srv/cosmic_entropy.gd")

## Poll cadence for the Kp sidecar. NOAA publishes on a 3h cadence, so
## 5 min is generous — headless servers save cycles and clients share
## one sky.
const KP_POLL_SEC: float = 300.0
## Where the NOAA sidecar lives (container-internal). Overridable for
## tests via the url property.
const DEFAULT_SIDECAR_URL: String = "http://127.0.0.1:8082/kp"

## Tolled off SignService when available so the almanac is the one
## clock; unix time elsewhere.
const snap_property: String = "cosmic"


signal kp_ingested(kp: float, at_time: float)
## Bridged from the canonical wheel's spark: {wheel: "cosmic", kp,
## momentum, sparks, total_chaos}. Gameplay listens HERE, never on the
## frame primitive directly.
signal spark(payload: Dictionary)

var url: String = DEFAULT_SIDECAR_URL
## The frame system object (deterministic for tests; live is same lib).
var cosmic = null
## Last HTTP error (diagnostic surface for the ops dashboard).
var last_error: String = ""

var _poll_timer: Timer = null
var _decay_accum: float = 0.0
var _decay_last_time: float = -1.0


func _ready() -> void:
	if cosmic == null:
		cosmic = CosmicEntropyScript.new()
	cosmic.on_spark(_on_wheel_spark)
	_restore_state()
	_poll()


## Feed one Kp reading (the sidecar's job on live servers; tests feed
## deterministic values). Sparse/no-op if the value is unchanged AND
## the cadence has not advanced — repeated identical readings still
## count (they represent real passage of quiet time).
func ingest_kp(kp: float, at_time: float = -1.0) -> void:
	var t := float(at_time)
	if t < 0.0:
		t = _now()
	cosmic.feed_kp(kp, t)
	_persist_state()
	kp_ingested.emit(kp, t)


## Injectable decay driver (TickService calls steer_decay each tick).
## The wheel's decay law lives in the frame; the service only routes
## real elapsed time into it.
func steer_decay(delta_sec: float) -> void:
	if delta_sec > 0.0:
		cosmic.tick(delta_sec)


## Deterministic clock: SignService's day index when present, else unix.
func _now() -> float:
	if SignService != null and SignService.has_method("current_day_index"):
		return float(SignService.current_day_index())
	return Time.get_unix_time_from_system()


## Fetch a fresh reading from the sidecar. Best-effort: errors keep the
## last reading (stale law handles demotion downstream).
func _poll() -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_poll_response.bind(http))
	var err := http.request(url)
	if err != OK:
		last_error = "request failed: %d" % err
		http.queue_free()


func _on_poll_response(_result: int, response_code: int, _headers, body, http: HTTPRequest) -> void:
	http.queue_free()
	if response_code != 200:
		last_error = "sidecar http %d" % response_code
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if parsed is Dictionary and parsed.has("kp"):
		last_error = ""
		ingest_kp(float(parsed["kp"]), float(parsed.get("time", -1.0)))


func _on_wheel_spark(payload: Dictionary) -> void:
	GameLog.info("CosmicService: cosmic spark (%.1f Kp, %.1f momentum)" % [
		float(payload.get("kp", 0.0)), float(payload.get("momentum", 0.0))])
	spark.emit(payload)
	if EventHub != null and EventHub.has_method("emit_cosmic_weather_spark"):
		EventHub.emit_cosmic_weather_spark(payload)


## Persistence: momentum/last_kp/last_kp_time via DictStore.
func _persist_state() -> void:
	var store := DictStore.new()
	store.set_value("cosmic:flywheel", cosmic.snapshot(), 0)


func _restore_state() -> void:
	var store := DictStore.new()
	var snap = store.get_value("cosmic:flywheel")
	if snap is Dictionary and not snap.is_empty():
		cosmic.restore(snap)
		GameLog.info("CosmicService: restored cosmic wheel (%.1f momentum, Kp %.1f)" % [
			cosmic.momentum(), cosmic.last_kp])
