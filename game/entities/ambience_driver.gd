## AmbienceDriver -- the scene-side seam between the sky and its sound.
##
## Resolves weather for the PLAYER'S position once per AMBIENCE_TICK_SEC
## and hands the audio_layers() contract to AudioService. The sky you
## see and the sky you hear can never disagree: both key off the same
## weather.gd resolve() (cosmic primary, trad fallback) and the same
## SignService sky clock.
##
## Placement: instanced by world_playable._setup_ambience() as a child
## node (the SkySun/SkySigns pattern). Reads the scene's Player node;
## without one it idles silently (headless/lobby-safe).
##
## Player position law, both worlds: on the GLOBE (the player carries
## planet_radius / planet_center -- the globe entities do) the lat/lon
## is the real cartesian read, so band/season weather follows the
## sphere's cells. On the flat shard the player's (x, z) maps to
## latitude/lon via the 20 km planet scale -- position on the ground
## stands in for position on the globe. One driver, one law, both
## worlds; nothing else changes.
##
## Purely a driver: zero gameplay authority. All actual audio lives in
## AudioService (tests pin its contract; this node only feeds it).
extends Node3D

const WeatherScript = preload("res://core/frame/srv/weather.gd")
const SphericalScript = preload("res://core/frame/math/spherical.gd")
const CosmicEntropyScript = preload("res://core/frame/srv/cosmic_entropy.gd")

## Weather doesn't change fast enough to justify per-frame resolve;
## 2 seconds keeps transitions responsive and costs ~nothing.
const AMBIENCE_TICK_SEC: float = 2.0
## Seconds a cosmic Kp reading may drive weather before the resolve
## law itself decides fresh-vs-stale (has_fresh_kp needs "now").
## The driver trusts the frame's own staleness law -- this is only the
## clock it evaluates against (the sky clock, one clock for all).

var _timer: Timer = null
var _layers: Dictionary = {}
var _last_source: String = ""
var _last_state_name: String = ""
## The cosmic flywheel instance (created lazily on first tick; when
## the server feeds real NOAA Kp, this object receives feed_kp()).
var _cosmic = null


func _ready() -> void:
	# Best-effort audio: headless/script-mode boots may lack the
	# autoload; a missing AudioService means this node idles quietly.
	if root_or_null("AudioService") == null:
		GameLog.warn("AmbienceDriver: no AudioService, idling")
		return
	_timer = Timer.new()
	_timer.wait_time = AMBIENCE_TICK_SEC
	_timer.timeout.connect(_tick)
	add_child(_timer)
	_tick()
	if is_inside_tree():
		_timer.start()
	GameLog.info("AmbienceDriver: watching the sky every %.0fs (%s)" % [
		AMBIENCE_TICK_SEC, _describe_source(_last_source)])


func root_or_null(node_name: String) -> Node:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("AudioService")


## Resolve current weather at the player and apply it. Public so tests
## and the debug overlay can force a re-resolve without waiting a tick.
func _tick() -> void:
	var audio = get_tree().root.get_node_or_null("AudioService")
	if audio == null:
		return
	var player := get_parent().get_node_or_null("Player") if get_parent() != null else null
	if player == null and get_parent() != null:
		player = get_parent().get_node_or_null("GlobePlayer")
	if player == null:
		return
	var day: float = float(SignService.current_day_index()) if SignService != null else 0.0
	var ll: Vector2 = _player_latlon(player)
	if _cosmic == null:
		# Consolidation seam (this session): the driver no longer builds
		# a private wheel. CosmicService owns the ONE live cosmic wheel
		# fed by real NOAA Kp; the driver borrows it so seen sky, heard
		# sky, and spark events all share one flywheel. Falls back to a
		# local instance only when the autoload is absent (headless
		# script tests).
		var cosmic_svc = get_tree().root.get_node_or_null("CosmicService")
		if cosmic_svc != null and cosmic_svc.cosmic != null:
			_cosmic = cosmic_svc.cosmic
		else:
			_cosmic = CosmicEntropyScript.new()
	# The moon-shield seam: resolve reads the SHIELDED aurora at the
	# current sky epoch (the moon standing in the solar stream trims
	# the aurora the world sees). The epoch is the Concord clock, the
	# one the moon orbits on.
	var epoch: float = SignService.sky_epoch_days() if SignService != null and SignService.has_method("sky_epoch_days") else -1.0
	var state: Dictionary = WeatherScript.resolve(ll.x, ll.y, day, _cosmic, epoch)
	var layers: Dictionary = WeatherScript.audio_layers(state)
	audio.apply_weather(layers)
	_layers = layers

	# The world reacts to band changes too, not just the sound: the
	# WeatherEventService sibling gets a push whenever the resolved
	# STATE name changes (storm rolls in / clears). Zero new law — the
	# driver only reports what resolve() already decided.
	var st_name: String = str(state.get("name", ""))
	if st_name != _last_state_name:
		_last_state_name = st_name
		if _last_state_name != "":  # skip the first resolve (boot)
			var we = get_parent().get_node_or_null("WeatherEvents")
			if we != null and we.has_method("on_weather_band_changed"):
				we.on_weather_band_changed(state)

	if state.get("source", "") != _last_source:
		_last_source = str(state.get("source", ""))
		GameLog.info("AmbienceDriver: weather source -> %s (%s)" % [
			_last_source, str(state.get("name", "?"))])


## Player (lat, lon) in degrees, by which world the player belongs to.
## Globe entities carry planet_radius/planet_center (globe_player.gd):
## their cartesian read is the real sphere position, planet-relative
## (immune to floating origin). Flat players don't carry those, so the
## (x, z) -> lat/lon shard mapping stays. ~55 km weather cells
## (CELL_DEG 0.5) span either world the same way.
func _player_latlon(player: Node3D) -> Vector2:
	if "planet_radius" in player:
		var center: Vector3 = player.planet_center if "planet_center" in player else Vector3.ZERO
		return SphericalScript.cartesian_to_spherical(
			player.global_position - center, float(player.planet_radius))
	var p: Vector3 = player.global_position
	var lat: float = p.z / SphericalScript.PLANET_RADIUS_METERS * 57.2957795
	var lon: float = p.x / SphericalScript.PLANET_RADIUS_METERS * 57.2957795
	return Vector2(lat, lon)


## Last resolved layers (HUD/debug read without re-resolving).
func current_layers() -> Dictionary:
	return _layers.duplicate()


func _describe_source(source: String) -> String:
	return source if source != "" else "unresolved"
