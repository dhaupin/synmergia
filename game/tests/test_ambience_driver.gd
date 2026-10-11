extends SceneTree

## AmbienceDriver smoke test: the driver resolves weather at the player
## and feeds AudioService.apply_weather() on its own tick. Verified
## structurally (headless has no audio device): the driver node builds,
## resolves real states through the SAME frame laws, and the layers it
## produces satisfy AudioService's contract. Run:
##   godot --headless --path . --script res://tests/test_ambience_driver.gd

var _ok := true


func _initialize() -> void:
	var audio = root.get_node_or_null("AudioService")
	if audio == null:
		push_error("FAIL: AudioService autoload missing")
		quit(1)
		return
	if audio.has_method("ensure_initialized"):
		audio.ensure_initialized()

	var WeatherScript = load("res://core/frame/srv/weather.gd")
	var CosmicScript = load("res://core/frame/srv/cosmic_entropy.gd")
	var driver_script = load("res://entities/ambience_driver.gd")
	if driver_script == null:
		push_error("FAIL: ambience_driver.gd not loadable")
		quit(1)
		return

	# 1. The driver script instantiates standalone (RefCounted-style
	#    API surface: current_layers exists, no parse errors).
	var driver = driver_script.new()
	if not driver.has_method("current_layers"):
		push_error("FAIL: driver missing current_layers()")
		_ok = false
	if not driver.has_method("_tick"):
		push_error("FAIL: driver missing _tick()")
		_ok = false
	print("[OK] driver script loads with the driver API")

	# 2. The chain the driver runs, exercised directly with a REAL
	#    cosmic instance (no Kp fed -> trad fallback law): resolve ->
	#    audio_layers -> apply_weather. Same calls _tick() makes.
	var cosmic = CosmicScript.new()
	var state: Dictionary = WeatherScript.resolve(45.0, 10.0, 100.0, cosmic)
	if str(state.get("source", "")) != "trad":
		push_error("FAIL: empty flywheel should fall back to trad, got %s" % str(state.get("source")))
		_ok = false
	var layers: Dictionary = WeatherScript.audio_layers(state)
	audio.apply_weather(layers)
	if audio.current_layers().get("wind_loop", -1.0) != layers["wind_loop"]:
		push_error("FAIL: apply_weather did not take the driver's layers")
		_ok = false
	print("[OK] driver chain (resolve -> audio_layers -> apply_weather) end-to-end, source=%s" % str(state.get("source")))

	# 3. A FED cosmic flywheel flips the source law: fresh Kp 6.5 is
	#    storm band -> storm state -> rain+wind+accents. This is the
	#    NOAA -> sound path the driver realizes in the world.
	cosmic.feed_kp(6.5, Time.get_unix_time_from_system())
	var state2: Dictionary = WeatherScript.resolve(45.0, 10.0, 100.0, cosmic)
	if str(state2.get("source", "")) != "cosmic":
		push_error("FAIL: fresh Kp should resolve cosmic, got %s" % str(state2.get("source")))
		_ok = false
	if str(state2.get("name", "")) != "storm":
		push_error("FAIL: Kp 6.5 should be storm band, got %s" % str(state2.get("name")))
		_ok = false
	var layers2: Dictionary = WeatherScript.audio_layers(state2)
	audio.apply_weather(layers2)
	if float(layers2.get("thunder_chance", 0.0)) <= 0.0:
		push_error("FAIL: storm layers should carry thunder_chance")
		_ok = false
	print("[OK] fed flywheel (Kp 6.5) -> cosmic storm -> thunder armed")

	# 4. All five states pass through apply_weather without error and
	#    leave finite loop gains (AudioService clamps; driver only
	#    forwards).
	for s in WeatherScript.STATES:
		audio.apply_weather(WeatherScript.audio_layers(s))
		for loop_name in audio._loop_players.keys():
			var p = audio._loop_players[loop_name]
			if is_nan(p.volume_db) or is_inf(p.volume_db):
				push_error("FAIL: non-finite gain after %s" % str(s.get("name")))
				_ok = false
	audio.stop_ambience()
	print("[OK] all weather states forward cleanly; gains finite")

	print("--- AMBIENCE DRIVER: ok=%s ---" % str(_ok))
	quit(0 if _ok else 1)
