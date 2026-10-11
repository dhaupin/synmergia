## Tests for WeatherSystem — dual-provider weather (co-located per
## frame conventions).
##
## Covers: latitude band classification (sphere tie-in), seasonal
## tilt phase (hemispheres opposite), trad determinism per cell,
## trad monotonic storm bias by band, the cosmic/trad fallback law
## (fresh Kp -> cosmic, stale/null -> trad), cosmic state mapping
## (storm Kp -> storm state, aurora gate outside the tropics), and
## resolve_at_position plumbing through the spherical math.
extends SceneTree

const WeatherScript = preload("res://core/frame/srv/weather.gd")
const CosmicScript = preload("res://core/frame/srv/cosmic_entropy.gd")
const SphericalScript = preload("res://core/frame/math/spherical.gd")

var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	_test_latitude_bands()
	_test_season_tilt()
	_test_trad_deterministic()
	_test_trad_band_bias()
	_test_fallback_law()
	_test_cosmic_mapping()
	_test_position_plumbing()
	_test_audio_layers()
	print("Weather tests: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_latitude_bands() -> void:
	_check("equator is tropic", WeatherScript.band_for_latitude(0.0) == "tropic")
	_check("23.0 is tropic (inside tropic line)", WeatherScript.band_for_latitude(23.0) == "tropic")
	_check("45N is temperate", WeatherScript.band_for_latitude(45.0) == "temperate")
	_check("45S is temperate", WeatherScript.band_for_latitude(-45.0) == "temperate")
	_check("70N is polar", WeatherScript.band_for_latitude(70.0) == "polar")
	_check("-70S is polar", WeatherScript.band_for_latitude(-70.0) == "polar")


func _test_season_tilt() -> void:
	# Day 90: northern midsummer, southern midwinter.
	var north: float = WeatherScript.season_factor(45.0, 90.0)
	var south: float = WeatherScript.season_factor(-45.0, 90.0)
	_check("hemispheres out of phase", north > 0.9 and south < -0.9)
	# Equinoxes cross zero for both hemispheres.
	_check("equinox near zero", absf(WeatherScript.season_factor(45.0, 0.0)) < 0.1
		and absf(WeatherScript.season_factor(-45.0, 0.0)) < 0.1)


func _test_trad_deterministic() -> void:
	var a: Dictionary = WeatherScript.trad_weather(12.3, -45.6, 100.0)
	var b: Dictionary = WeatherScript.trad_weather(12.3, -45.6, 100.0)
	_check("same cell + day -> same trad sky", a["name"] == b["name"])
	var c: Dictionary = WeatherScript.trad_weather(12.3, -45.6, 101.0)
	# Not asserting difference (could coincide) but the hash must differ.
	_check("different day changes the roll", WeatherScript._hash3(12.3, -45.6, 101.0) != WeatherScript._hash3(12.3, -45.6, 100.0))
	# Cell quantization: nearby points share a cell.
	var near: Dictionary = WeatherScript.trad_weather(12.34, -45.61, 100.0)
	_check("nearby points share the cell", near["name"] == a["name"])


func _test_trad_band_bias() -> void:
	# Average storminess over many cells/days per band.
	var bands := {"tropic": 0.0, "temperate": 0.0, "polar": 0.0}
	var lats := {"tropic": 10.0, "temperate": 45.0, "polar": 75.0}
	for band in bands:
		var stormy := 0
		var total := 0
		for i in range(200):
			var lat: float = lats[band] + (i % 5) * 0.5
			var lon: float = (i * 7.3)
			var w: Dictionary = WeatherScript.trad_weather(lat, lon, float(i))
			total += 1
			if w["name"] in ["rain", "storm"]:
				stormy += 1
		bands[band] = float(stormy) / float(total)
	_check("tropics stormier than polar (sampled)", bands["tropic"] > bands["polar"])
	_check("wet states exist in temperate sample", bands["temperate"] > 0.05)


func _test_fallback_law() -> void:
	# Null cosmic -> trad.
	var r1: Dictionary = WeatherScript.resolve(45.0, 10.0, 100.0, null)
	_check("null cosmic falls back to trad", r1["source"] == "trad")
	# Stale cosmic -> trad.
	var stale = CosmicScript.new()
	stale.feed_kp(5.0, 0.0)
	var r2: Dictionary = WeatherScript.resolve(45.0, 10.0, 4.0 * 3600.0, stale)
	_check("stale Kp falls back to trad", r2["source"] == "trad")
	# Fresh cosmic -> cosmic.
	var fresh = CosmicScript.new()
	fresh.feed_kp(5.0, 4.0 * 3600.0)
	var r3: Dictionary = WeatherScript.resolve(45.0, 10.0, 4.0 * 3600.0, fresh)
	_check("fresh Kp uses cosmic", r3["source"] == "cosmic" and r3["kp"] == 5.0)


func _test_cosmic_mapping() -> void:
	# Storm Kp -> storm state anywhere.
	var stormy = CosmicScript.new()
	stormy.feed_kp(6.5, 1000.0)
	var s: Dictionary = WeatherScript.resolve(0.0, 0.0, 1000.0, stormy)
	_check("tempest Kp -> storm state (even tropics)", s["name"] == "storm")
	# Calm Kp -> cloudy baseline.
	var calm = CosmicScript.new()
	calm.feed_kp(0.5, 1000.0)
	var c: Dictionary = WeatherScript.resolve(45.0, 10.0, 1000.0, calm)
	_check("calm Kp -> cloudy baseline", c["name"] == "cloudy")
	# Active band with aurora > 0.5: only outside the tropics.
	var lit = CosmicScript.new()
	lit.feed_kp(5.0, 1000.0)  # storm band wind 0.75 aurora 0.70
	var polar: Dictionary = WeatherScript.resolve(70.0, 10.0, 1000.0, lit)
	_check("polar gate: Kp 5 maps to storm before aurora", polar["name"] == "storm")
	var mid = CosmicScript.new()
	mid.feed_kp(3.8, 1000.0)  # active: wind 0.50 aurora 0.40 -> not aurora gate
	var m: Dictionary = WeatherScript.resolve(70.0, 10.0, 1000.0, mid)
	_check("active band (aurora 0.4) -> rain, no aurora", m["name"] == "rain")

	# The moon-shield seam: when the epoch is passed, resolve reads
	# the SHIELDED aurora (aurora_at_epoch = band aurora lerped toward
	# the SHIELD_MIN_AURORA floor by the moon's CME shadow).
	var shield_lit = CosmicScript.new()
	shield_lit.feed_kp(5.0, 1000.0)  # storm band: base aurora 0.70
	var unshielded: Dictionary = WeatherScript.resolve(70.0, 10.0, 1000.0, shield_lit, 10.0)
	var shielded: Dictionary = WeatherScript.resolve(70.0, 10.0, 1000.0, shield_lit, 4.0)
	# world_moon.tres: P = 8 d, phase = 0.7. At epoch 4.0 (P/2) the
	# moon sits on the anti-solar apex (full shield); at epoch 10.0
	# (P/2 + 6 d) it is elsewhere (epoch mod 4 clears the penumbra).
	_check("epoch 10 keeps the band's own aurora (shield elsewhere)", \
		absf(float(unshielded["aurora"]) - 0.70) < 0.02)
	_check("anti-solar apex trims the aurora toward the floor", \
		float(shielded["aurora"]) < 0.70 and float(shielded["aurora"]) >= 0.70 * CosmicScript.SHIELD_MIN_AURORA - 0.001)
	_check("shielded aurora stays shapable (still > 0)", float(shielded["aurora"]) > 0.1)
	_check("no epoch passed = flat band law unchanged", \
		float(WeatherScript.resolve(70.0, 10.0, 1000.0, lit)["aurora"]) > 0.69)


func _test_position_plumbing() -> void:
	# A point on the sphere resolves to the same weather as its lat/lon.
	var pos: Vector3 = SphericalScript.spherical_to_cartesian(45.0, 10.0, 0.0, 100.0)
	var via_pos: Dictionary = WeatherScript.resolve_at_position(pos, 100.0, 100.0, null)
	var via_ll: Dictionary = WeatherScript.resolve(45.0, 10.0, 100.0, null)
	_check("position plumbing matches lat/lon resolve", via_pos["name"] == via_ll["name"]
		and via_pos["source"] == via_ll["source"])


func _test_audio_layers() -> void:
	# The audio contract: storm vs clear vs aurora produce distinct
	# layer beds, all gains bounded.
	var storm: Dictionary = WeatherScript.audio_layers(WeatherScript.STATES[3])
	var clear: Dictionary = WeatherScript.audio_layers(WeatherScript.STATES[0])
	var aurora: Dictionary = WeatherScript.audio_layers(WeatherScript.STATES[4])
	_check("storm: rain + thunder + whistlers", storm["rain_loop"] > 0.0 and storm["thunder_chance"] > 0.0 and storm["whistler_enabled"])
	_check("clear: silent rain, no thunder", clear["rain_loop"] == 0.0 and clear["thunder_chance"] == 0.0)
	_check("aurora: pad up, chorus richest", aurora["aurora_pad"] == 1.0 and aurora["chorus_density"] > clear["chorus_density"])
	var bounded := true
	for s in WeatherScript.STATES:
		var l: Dictionary = WeatherScript.audio_layers(s)
		for k in ["wind_loop", "rain_loop", "thunder_chance", "aurora_pad"]:
			var v: float = float(l[k])
			if v < 0.0 or v > 1.0:
				bounded = false
	_check("all layer gains in [0,1] across states", bounded)


func _check(label: String, cond: bool) -> void:
	if cond:
		_passed += 1
		print("  PASS %s" % label)
	else:
		_failed += 1
		print("  FAIL %s" % label)
