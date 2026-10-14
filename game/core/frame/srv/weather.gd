## WeatherSystem — dual-provider weather for the sphere world.
##
## Two providers, one interface:
## - COSMIC (primary): the CosmicEntropy flywheel's weather bands —
##   real solar wind (Kp) drives world weather. When the feed is
##   fresh, the whole planet shares the sky's mood, and the
##   underworld's tides follow the same far-off weather.
## - TRAD (fallback): a traditional climate model — latitude bands,
##   seasonal tilt, deterministic per-cell noise. There for when the
##   cosmic feed is stale or unavailable, and as the substrate for
##   more systems later (monsoons, el-nino-like oscillations).
##
## The fallback law: resolve() uses cosmic weather iff the flywheel
## has a fresh Kp reading; otherwise every cell falls back to trad.
## Clients must never mix providers for the same tick — the returned
## source field is the contract for that.
##
## Sphere tie-in: weather is a function of latitude band + season +
## cell (lat/lon quantized), not of the camera. Two players standing
## in the same cell on the same day get the same sky.
##
## Frame primitive: NO autoload, NO class_name, NO GameManager dependency.
extends RefCounted

const SphericalScript = preload("res://core/frame/math/spherical.gd")
const CosmicEntropyScript = preload("res://core/frame/srv/cosmic_entropy.gd")

## Climate bands by absolute latitude (degrees).
const TROPIC_LAT: float = 23.5
const POLAR_LAT: float = 66.5

## Quantization for trad weather cells: weather changes on ~55 km
## cells (1/2 degree at planet scale) so a zone has a handful of them.
const CELL_DEG: float = 0.5

## Seasonal tilt: hemisphere phase offset in days (half a 360-day
## world year; the calendar is the almanac's, not Earth's).
const YEAR_DAYS: float = 360.0

## Weather states, shared by both providers so consumers need no
## provider branching. wind in [0,1], aurora in [0,1].
const STATES: Array[Dictionary] = [
	{"name": "clear",     "wind": 0.10, "aurora": 0.0},
	{"name": "cloudy",    "wind": 0.30, "aurora": 0.0},
	{"name": "rain",      "wind": 0.55, "aurora": 0.0},
	{"name": "storm",     "wind": 0.85, "aurora": 0.0},
	{"name": "aurora",    "wind": 0.25, "aurora": 1.0},
]


## Climate band for a latitude: "tropic", "temperate", "polar".
static func band_for_latitude(lat: float) -> String:
	var a: float = absf(lat)
	if a < TROPIC_LAT:
		return "tropic"
	if a >= POLAR_LAT:
		return "polar"
	return "temperate"


## Season factor for a latitude and day: +1 midsummer, -1 midwinter
## at that latitude, crossing zero at the equinoxes. Southern
## hemisphere is half a year out of phase.
static func season_factor(lat: float, day: float) -> float:
	var phase: float = TAU * (day / YEAR_DAYS)
	var tilt: float = sin(phase)
	return tilt if lat >= 0.0 else -tilt


## Traditional weather for one quantized cell. Deterministic in
## (lat, lon, day): same cell, same day, same sky — forever.
static func trad_weather(lat: float, lon: float, day: float) -> Dictionary:
	var band := band_for_latitude(lat)
	# Quantize the cell so nearby players share one roll.
	var cell_lat: float = floorf(lat / CELL_DEG) * CELL_DEG
	var cell_lon: float = floorf(lon / CELL_DEG) * CELL_DEG
	var h: int = _hash3(cell_lat, cell_lon, day)
	var r: float = float(h & 0xFFFF) / 65536.0

	# Base storm likelihood by band (tropics: convective; temperate:
	# frontal; polar: sparse), modulated by season.
	var base := 0.30
	match band:
		"tropic":
			base = 0.40
		"polar":
			base = 0.15
		"temperate":
			base = 0.30
	var winter: float = maxf(0.0, -season_factor(lat, day))
	base += 0.10 * winter * (1.0 if band == "temperate" else 0.0)

	if r < base:
		return STATES[3] if (r < base * 0.4) else STATES[2]  # storm : rain
	if r < base + 0.30:
		return STATES[1]                                     # cloudy
	return STATES[0]                                         # clear


## Resolve weather at a sphere position. pos: world-space position on
## the planet; radius: planet radius. cosmic: the flywheel (may be
## null/stale -> trad fallback). day: almanac day number.
static func resolve_at_position(pos: Vector3, radius: float, day: float, cosmic: Variant) -> Dictionary:
	var ll: Vector2 = SphericalScript.cartesian_to_spherical(pos, radius)
	return resolve(ll.x, ll.y, day, cosmic)


## Audio contract: map a resolved weather state to atmosphere layer
## gains. Consumers (AudioService, the client's ambience bus) read
## these — the music generator and the studio atmosphere synth key
## off the same numbers, so the game's sky and its soundtrack can
## never disagree. All gains in [0,1]; chorus_density is a count
## hint for the bird/chorus synth layer; birds_enabled gates the
## ambient chirps (the chorus sleeps in rain, storm, and aurora
## shimmer — only clear and cloudy skies sing).
static func audio_layers(state: Dictionary) -> Dictionary:
	var wind: float = float(state.get("wind", 0.0))
	var aurora: float = float(state.get("aurora", 0.0))
	var name: String = str(state.get("name", "clear"))
	return {
		"wind_loop": wind,                          # low rumble bed
		"rain_loop": 1.0 if name == "rain" else (0.6 if name == "storm" else 0.0),
		"thunder_chance": 0.8 if name == "storm" else 0.0,
		"chorus_density": 2 + int(round(6.0 * wind + 4.0 * aurora)),  # sky-birds per stanza
		"birds_enabled": name == "clear" or name == "cloudy",
		"aurora_pad": aurora,                       # high shimmer drone
		"whistler_enabled": wind >= 0.5,            # dispersive chirps in storms
	}


## Resolve weather for lat/lon with the fallback law. Returns the
## state plus {"source": "cosmic"|"trad"} and the driving Kp when
## cosmic. When `cosmic` exposes aurora_at_epoch() (the moon-shield
## aware read — see cosmic_entropy.gd), the aurora gate reads the
## SHIELDED aurora at the current sky epoch instead of the flat band
## value: the moon standing in the solar stream trims the aurora the
## world sees.
static func resolve(lat: float, lon: float, day: float, cosmic: Variant, epoch_days: float = -1.0) -> Dictionary:
	var fresh := false
	if cosmic != null and cosmic.has_method("has_fresh_kp"):
		fresh = cosmic.has_fresh_kp(day)
	if fresh:
		var aurora: float = float(CosmicEntropyScript.kp_to_band(cosmic.last_kp).get("aurora", 0.0))
		if cosmic.has_method("aurora_at_epoch") and epoch_days >= 0.0:
			aurora = float(cosmic.aurora_at_epoch(cosmic.last_kp, epoch_days))
		var band_name: String = str(CosmicEntropyScript.kp_to_band(cosmic.last_kp).get("name", "calm"))
		# Map the global sky band onto the shared state vocabulary:
		# storm-band Kp raises local storms; aurora values can paint
		# aurora over any non-storm cell (polar first is the consumer's
		# choice — resolve is band-agnostic about latitude except for
		# the aurora gate).
		var state: Dictionary
		if band_name in ["storm", "tempest"]:
			state = STATES[3]
		elif aurora > 0.5 and absf(lat) > TROPIC_LAT:
			state = STATES[4]
		elif float(CosmicEntropyScript.kp_to_band(cosmic.last_kp).get("wind", 0.0)) > 0.4:
			state = STATES[2]
		else:
			state = STATES[1]
		var out := state.duplicate()
		out["source"] = "cosmic"
		out["kp"] = cosmic.last_kp
		out["aurora"] = aurora
		return out
	var out2: Dictionary = trad_weather(lat, lon, day).duplicate()
	out2["source"] = "trad"
	return out2


static func _hash3(a: float, b: float, c: float) -> int:
	var x: int = int(a * 100.0)
	x = (x * 374761393 + int(b * 100.0) * 668265263) & 0x7FFFFFFF
	x = (x * 1274126177 + int(c * 100.0) * 2654435761) & 0x7FFFFFFF
	x = (x ^ (x >> 13)) * 1103515245 & 0x7FFFFFFF
	return x ^ (x >> 16)
