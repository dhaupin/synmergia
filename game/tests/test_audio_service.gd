extends SceneTree

## AudioService smoke test: the generated WAVs load, the round-robin
## pools cycle, unknown names are rejected loudly, repeated plays never
## crash the pool, and the weather hookup obeys the audio_layers()
## contract (loops start/stop with gains, accents arm with storms,
## clear weather silences everything). Headless Godot has no audio
## device -- the API is exercised structurally (no assertion on actual
## sound output). Run:
##   godot --headless --path . --script res://tests/test_audio_service.gd

var _audio = null


func _initialize() -> void:
	_audio = root.get_node_or_null("AudioService")
	if _audio == null:
		push_error("FAIL: AudioService autoload missing")
		quit(1)
		return
	# Script-mode guard: the autoload's _ready may not have fired yet.
	if _audio.has_method("ensure_initialized"):
		_audio.ensure_initialized()

	var ok := true
	ok = _test_streams_loaded() and ok
	ok = _test_pool_ready() and ok
	ok = _test_unknown_rejected() and ok
	ok = _test_play_all() and ok
	ok = _test_weather_clear_is_silent() and ok
	ok = _test_weather_storm_layers() and ok
	ok = _test_weather_gains_bounded() and ok
	ok = _test_birds_loaded() and ok
	ok = _test_birds_band_contract() and ok
	ok = _test_birds_armed_law() and ok
	ok = _test_bird_fire_law() and ok
	ok = _test_positional_and_music() and ok

	print("--- AUDIO SERVICE: ok=%s ---" % str(ok))
	quit(0 if ok else 1)


func _test_streams_loaded() -> bool:
	if _audio._streams.size() != _audio.SOUNDS.size():
		push_error("FAIL: %d of %d sounds loaded" % [_audio._streams.size(), _audio.SOUNDS.size()])
		return false
	for key in ["ancient_door_open", "mystery_solved", "ui_click"]:
		if not _audio._streams.has(key):
			push_error("FAIL: missing stream %s" % key)
			return false
	print("[OK] %d generated WAVs loaded" % _audio._streams.size())
	return true


func _test_pool_ready() -> bool:
	if _audio._pool.size() != _audio.POOL_SIZE:
		push_error("FAIL: pool size %d != %d" % [_audio._pool.size(), _audio.POOL_SIZE])
		return false
	for p in _audio._pool:
		if p == null or not is_instance_valid(p):
			push_error("FAIL: invalid pool player")
			return false
	print("[OK] player pool of %d ready" % _audio._pool.size())
	return true


func _test_unknown_rejected() -> bool:
	# Unknown names must not crash or play -- just warn.
	_audio.play("not_a_real_sound", 0.0)
	_audio.play_ui("nope", -6.0)
	print("[OK] unknown sound names rejected without error")
	return true


func _test_play_all() -> bool:
	# Every sound plays; round-robin walks the whole pool; overlap is
	# safe (multiple plays in a row).
	var before: int = _audio._next
	var plays: int = 0
	for key in _audio.SOUNDS.keys():
		_audio.play(str(key), 0.0)
		_audio.play_world(str(key), -3.0)
		_audio.play_ui(str(key) if key == "ui_click" else "ui_click", -6.0)
		plays += 3
	var expected: int = (before + plays) % _audio._pool.size()
	if _audio._next != expected:
		push_error("FAIL: round-robin at %d, expected %d (%d + %d plays mod %d)" % [
			_audio._next, expected, before, plays, _audio._pool.size()])
		return false
	print("[OK] all sounds play across the pool; round-robin advances %d -> %d" % [before, _audio._next])
	return true


func _test_positional_and_music() -> bool:
	# Positional pool exists and accepts both one-shot and accent names.
	if _audio._positional_pool.size() != _audio.POSITIONAL_POOL_SIZE:
		push_error("FAIL: positional pool size %d" % _audio._positional_pool.size())
		return false
	for p in _audio._positional_pool:
		if p == null or not is_instance_valid(p):
			push_error("FAIL: invalid positional pool player")
			return false
	_audio.play_at("ancient_door_open", Vector3.ZERO, 0.0)
	_audio.play_at("thunder", Vector3(10, 0, 10), -4.0)
	_audio.play_at("not_a_real_sound", Vector3.ZERO)  # warns, no-op
	# Music contract: missing track warns; stop_music is idempotent.
	_audio.play_music("no_such_track")
	_audio.stop_music()
	print("[OK] positional pool of %d ready; play_at + music contract exercised" % _audio._positional_pool.size())
	return true


## The three committed bird one-shots load into the bird registry.
## Birds are one-shots, not loops: the chorus law fires them
## stochastically, so each variant is shareable across the pool.
func _test_birds_loaded() -> bool:
	if _audio._bird_streams.size() != _audio.BIRDS.size():
		push_error("FAIL: %d of %d bird variants loaded" % [_audio._bird_streams.size(), _audio.BIRDS.size()])
		return false
	for key in ["birds_1", "birds_2", "birds_3"]:
		if not _audio._bird_streams.has(key):
			push_error("FAIL: missing bird variant %s" % key)
			return false
	print("[OK] %d bird chirp variants loaded" % _audio._bird_streams.size())
	return true


## The chorus obeys the sky contract across every weather state:
## birds_enabled true exactly when the sky is clear or cloudy. Rain,
## storm, and aurora mute the chorus -- the heard sky and the seen
## sky stand or fall together.
func _test_birds_band_contract() -> bool:
	var WeatherScript = load("res://core/frame/srv/weather.gd")
	for state in WeatherScript.STATES:
		var name: String = str(state.get("name", "?"))
		var want: bool = name == "clear" or name == "cloudy"
		var got: bool = bool(WeatherScript.audio_layers(state).get("birds_enabled", true))
		if got != want:
			push_error("FAIL: state '%s' birds_enabled=%s, sky wants %s" % [name, str(got), str(want)])
			return false
	print("[OK] birds_enabled matches the sky in every weather state (clear/cloudy only)")
	return true


## Arming law: clear sky arms the chorus and stores the density;
## rain and storm mute it. Density zero never arms, whatever the sky
## says.
func _test_birds_armed_law() -> bool:
	var WeatherScript = load("res://core/frame/srv/weather.gd")
	# Clear: armed with the contracted density.
	var clear_layers: Dictionary = WeatherScript.audio_layers(WeatherScript.STATES[0])
	_audio.apply_weather(clear_layers)
	if not _audio._birds_armed:
		push_error("FAIL: clear sky did not arm the chorus")
		return false
	if _audio._chorus_density != float(clear_layers.get("chorus_density", -1)):
		push_error("FAIL: chorus_density not carried through")
		return false
	if _audio._accents_armed:
		push_error("FAIL: clear sky accidentally armed storm accents")
		return false
	# Rain keeps the accent timer (whistlers) but mutes the birds.
	_audio.apply_weather(WeatherScript.audio_layers(WeatherScript.STATES[2]))
	if _audio._birds_armed:
		push_error("FAIL: rain armed the chorus")
		return false
	# Density zero mutes even a singing sky.
	var silent_layers: Dictionary = WeatherScript.audio_layers(WeatherScript.STATES[0]).duplicate()
	silent_layers["chorus_density"] = 0.0
	_audio.apply_weather(silent_layers)
	if _audio._birds_armed:
		push_error("FAIL: density zero armed the chorus")
		return false
	print("[OK] chorus arming: clear arms, rain/storm mute, density zero mutes")
	return true


## Fire law: an armed chorus with an elapsed interval fires a chirp
## into the accent pool; a muted chorus never fires. And the interval
## shrinks as the chorus densifies.
func _test_bird_fire_law() -> bool:
	# Armed + long wait -> a chirp plays on a pool player.
	_audio._birds_armed = true
	_audio._chorus_density = 8.0
	_audio._ms_since_bird = _audio._bird_interval()
	var had_birds: int = 0
	var before: int = 0
	for p in _audio._accent_pool:
		if p.stream != null and str(p.stream.resource_path).contains("birds_"):
			before += 1
	_audio._on_accent_tick()
	for p in _audio._accent_pool:
		if p.stream != null and str(p.stream.resource_path).contains("birds_"):
			had_birds += 1
	if had_birds <= before:
		push_error("FAIL: armed chorus with elapsed interval fired no chirp")
		return false
	if _audio._ms_since_bird != 0.0:
		push_error("FAIL: chorus clock not reset after the fire")
		return false
	# Muted -> tick is a no-op.
	_audio._birds_armed = false
	var before_next: int = _audio._accent_next
	_audio._on_accent_tick()
	if _audio._accent_next != before_next:
		push_error("FAIL: muted chorus advanced the pool")
		return false
	# Interval law: denser chorus, faster calls.
	_audio._chorus_density = 2.0
	var slow: float = _audio._bird_interval()
	_audio._chorus_density = 14.0
	var fast: float = _audio._bird_interval()
	if not (slow > fast):
		push_error("FAIL: interval %f did not shrink with density (fast %f)" % [slow, fast])
		return false
	print("[OK] bird fire law: armed fires, muted no-ops, interval shrinks with density (%f -> %f)" % [slow, fast])
	return true


## audio_layers() contract: clear weather = soft wind bed ONLY (wind
## 0.1 -> one quiet loop), no rain/aurora, accents unarmed.
func _test_weather_clear_is_silent() -> bool:
	var WeatherScript = load("res://core/frame/srv/weather.gd")
	var layers: Dictionary = WeatherScript.audio_layers(WeatherScript.STATES[0])
	_audio.apply_weather(layers)
	if _audio._loop_players.size() != 1 or not _audio._loop_players.has("wind"):
		push_error("FAIL: clear weather loops = %s, expected just soft wind" % str(_audio._loop_players.keys()))
		return false
	var got: Dictionary = _audio.current_layers()
	if got.get("wind_loop", -1.0) != layers["wind_loop"]:
		push_error("FAIL: current_layers() round-trip mismatch")
		return false
	if _audio._accents_armed:
		push_error("FAIL: clear weather armed accents")
		return false
	print("[OK] clear weather: soft wind bed only, layers round-trip, accents unarmed")
	return true


## audio_layers() contract: storm = wind+rain loops running, accents
## armed (timer alive).
func _test_weather_storm_layers() -> bool:
	var WeatherScript = load("res://core/frame/srv/weather.gd")
	var layers: Dictionary = WeatherScript.audio_layers(WeatherScript.STATES[3])
	_audio.apply_weather(layers)
	if not _audio._loop_players.has("wind") or not _audio._loop_players.has("rain"):
		push_error("FAIL: storm did not start wind+rain loops")
		return false
	for key in ["wind", "rain"]:
		var p: AudioStreamPlayer = _audio._loop_players[key]
		if not is_instance_valid(p):
			push_error("FAIL: storm loop '%s' invalid" % key)
			return false
	if not _audio._accents_armed:
		push_error("FAIL: storm did not arm the accents")
		return false
	print("[OK] storm weather: wind+rain loops live, accents armed")
	return true


## All weather states apply without error and gains stay in [0,1]
## (clamped before the dB conversion; volume_db finite).
func _test_weather_gains_bounded() -> bool:
	var WeatherScript = load("res://core/frame/srv/weather.gd")
	for state in WeatherScript.STATES:
		var layers: Dictionary = WeatherScript.audio_layers(state)
		_audio.apply_weather(layers)
		for loop_name in _audio._loop_players.keys():
			var p = _audio._loop_players[loop_name]
			if not is_instance_valid(p):
				push_error("FAIL: loop '%s' invalid for state %s" % [loop_name, state.get("name", "?")])
				return false
			if is_nan(p.volume_db) or is_inf(p.volume_db):
				push_error("FAIL: non-finite volume_db for '%s'" % loop_name)
				return false
		# Accents armed iff thunder or whistlers present.
		var want: bool = float(layers.get("thunder_chance", 0.0)) > 0.0 \
			or bool(layers.get("whistler_enabled", false))
		if _audio._accents_armed != want:
			push_error("FAIL: accents armed=%s, contract wants %s (state %s)" % [str(_audio._accents_armed), str(want), state.get("name", "?")])
			return false
	_audio.stop_ambience()
	if _audio._loop_players.size() != 0:
		push_error("FAIL: stop_ambience left loops running")
		return false
	print("[OK] all weather states apply; gains finite; accents track the contract")
	return true
