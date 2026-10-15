## AudioService -- the shard's sound
##
## Three buses of sound, one service:
##
## 1. ONE-SHOTS (the original batch-14 contract): generated WAVs
##    (scripts/gen_door_open_audio.py) through a round-robin pool of
##    non-positional players. The door bell is communal -- no 3D
##    panning.
## 2. AMBIENCE + WEATHER: seamless generated loops (wind, rain,
##    aurora pad; scripts/gen_ambience_audio.py) on dedicated players,
##    with apply_weather(layers) as the consumer of the frame's
##    weather.gd audio_layers() contract. The sky you see and the sky
##    you hear can never disagree: both key off the same resolved
##    state. Thunder and whistlers are stochastic one-shot accents,
##    fired from storm state via a timer tick.
## 3. POSITIONAL + MUSIC: an AudioStreamPlayer3D pool for world
##    noises (enemies, mounts, vehicles, props) and a music player
##    for static tracks (play_music/stop_music with crossfade-ish
##    volume ramp).
##
## Autoload (after SignService/ActsService so their _ready order is
## untouched; nothing here runs at boot beyond building the pools).
## Headless-safe: every call no-ops without a scene tree, and all
## loops/timers are created lazily on first use.
extends Node

## One-shot name (in game/audio/) -> stream. Preloaded once;
## AudioStreamWAV resources are shareable across players.
const SOUNDS := {
	"ancient_door_open": "res://audio/ancient_door_open.wav",
	"mystery_solved": "res://audio/mystery_solved.wav",
	"ui_click": "res://audio/ui_click.wav",
}

## Ambience loop name -> stream path. Played on LOOP players (their
## own AudioStreamPlayer per layer, looping forever at a gain).
const LOOPS := {
	"wind": "res://audio/ambience/wind_loop.wav",
	"rain": "res://audio/ambience/rain_loop.wav",
	"aurora": "res://audio/ambience/aurora_pad.wav",
}

## Weather accent one-shots (stochastic, storm-driven).
const ACCENTS := {
	"thunder": "res://audio/ambience/thunder.wav",
	"whistler": "res://audio/ambience/whistler.wav",
}

## Ambient bird one-shots (stochastic, chorus-driven). Not ACCENTS:
## accents are storm behavior, birds are the clear-sky day voice --
## separate registry so storm randomness never picks a birds_*.wav.
const BIRDS := {
	"birds_1": "res://audio/ambience/birds_1.wav",
	"birds_2": "res://audio/ambience/birds_2.wav",
	"birds_3": "res://audio/ambience/birds_3.wav",
}

const POOL_SIZE: int = 6
const POSITIONAL_POOL_SIZE: int = 8
## Ambience tick: how often storm accents (thunder rolls, whistlers)
## get a chance to fire.
const ACCENT_TICK_SEC: float = 4.0

var _streams: Dictionary = {}
var _pool: Array = []
var _next: int = 0

var _loop_players: Dictionary = {}      # loop name -> AudioStreamPlayer
var _accent_streams: Dictionary = {}    # accent name -> AudioStreamWAV
var _accent_pool: Array = []            # round-robin one-shot players
var _accent_next: int = 0
var _accent_timer: Timer = null
## Authoritative "accents should fire" flag. The Timer alone can't be
## the source of truth in headless/--script mode (outside the scene
## tree, start() no-ops), so _on_accent_tick gates on this flag and
## tests assert it directly.
var _accents_armed: bool = false
## The birds share the same 4 s tick but obey their own law:
## _birds_enabled comes from audio_layers(birds_enabled), and the
## interval between chirps shrinks with chorus_density (a loud dawn
## chorus calls fast; a single bird calls slow). Headless-safe like
## _accents_armed -- the flag, not the Timer, is the source of truth.
var _birds_armed: bool = false
var _chorus_density: float = 0.0
var _ms_since_bird: float = 0.0
var _bird_streams: Dictionary = {}       # bird variant -> AudioStreamWAV
var _layers: Dictionary = {}            # last applied audio_layers()

var _positional_pool: Array = []        # AudioStreamPlayer3D pool
var _positional_next: int = 0

var _music_player: AudioStreamPlayer = null
var _music_path: String = ""

## _ready may lag the first script-mode probes (autoload attach order)
## -- every entry point funnels through the idempotent boot.
var _initialized: bool = false


func _ready() -> void:
	ensure_initialized()


func ensure_initialized() -> void:
	if _initialized:
		return
	_initialized = true
	for key in SOUNDS.keys():
		var stream = load(str(SOUNDS[key]))
		if stream != null:
			_streams[key] = stream
	for key in ACCENTS.keys():
		var accent = load(str(ACCENTS[key]))
		if accent != null:
			_accent_streams[key] = accent
	for key in BIRDS.keys():
		var bird = load(str(BIRDS[key]))
		if bird != null:
			_bird_streams[key] = bird
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_pool.append(p)
	for i in POSITIONAL_POOL_SIZE:
		var p3 := AudioStreamPlayer3D.new()
		p3.bus = "Master"
		# Tuned to the playable scene's village scale (the starter map is
		# ~30 m across; entities are 1-2 m). unit_size 4.0 = audible
		# falloff starts ~4 m out and a sound is quiet by ~40 m: world
		# noises localize across the square without vanishing at the gate.
		p3.unit_size = 4.0
		add_child(p3)
		_positional_pool.append(p3)
	# Accent round-robin: reuse the one-shot pool shape, accents are
	# short one-shots like any other.
	for i in 4:
		var pa := AudioStreamPlayer.new()
		pa.bus = "Master"
		add_child(pa)
		_accent_pool.append(pa)
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Master"
	add_child(_music_player)
	GameLog.info("AudioService: ready (%d sounds, %d accents, %d birds, pools %d/%d)" % [
		_streams.size(), _accent_streams.size(), _bird_streams.size(), _pool.size(), _positional_pool.size()])


## Play a named sound (SOUNDS key) at a volume offset in dB (0 = full).
## Unknown names warn via GameLog and do nothing. Round-robin pool so
## overlapping one-shots never cut each other off. Missing streams
## (fresh .wav before an editor import pass) warn once and no-op.
func play(sound_name: String, volume_db: float = 0.0) -> void:
	ensure_initialized()
	if not _streams.has(sound_name):
		GameLog.warn("AudioService: unknown sound '%s'" % sound_name)
		return
	if _pool.is_empty():
		return
	var player: AudioStreamPlayer = _pool[_next]
	_next = (_next + 1) % _pool.size()
	player.stream = _streams[sound_name]
	player.volume_db = volume_db
	player.play()


## Convenience wrappers (call sites read as intent, not volumes).
func play_world(sound_name: String, volume_db: float = 0.0) -> void:
	play(sound_name, volume_db)


func play_ui(sound_name: String, volume_db: float = -6.0) -> void:
	play(sound_name, volume_db)


## --- Weather ambience (the audio_layers consumer) ---

## Apply a weather.gd audio_layers() dict to the loop players. Missing
## layers default to silence; gains are clamped to [0,1] before the dB
## conversion (linear_to_db(0) is -inf, so floors at -60 dB when the
## gain is nonzero and mutes at zero). Safe to call every tick: gains
## are set directly (no tween), the loops never restart.
##
## Layers consumed (from weather.gd audio_layers()):
##   wind_loop, rain_loop, aurora_pad  -> loop gains in [0,1]
##   thunder_chance, whistler_enabled  -> accent behavior
##   chorus_density                    -> hint; music layer consumes it
##   birds_enabled                     -> ambient chirps (clear/cloudy)
func apply_weather(layers: Dictionary) -> void:
	ensure_initialized()
	_layers = layers.duplicate()
	_set_loop_gain("wind", float(layers.get("wind_loop", 0.0)))
	_set_loop_gain("rain", float(layers.get("rain_loop", 0.0)))
	_set_loop_gain("aurora", float(layers.get("aurora_pad", 0.0)))
	# The chorus law: birds sing iff the sky says so (clear/cloudy) and
	# the chorus has members; density only modulates the call interval.
	# A rain/storm/aurora sky mutes the chorus -- heard sky, seen sky,
	# one law.
	_chorus_density = float(layers.get("chorus_density", 0.0))
	_birds_armed = bool(layers.get("birds_enabled", false)) and _chorus_density > 0.0 \
		and not _bird_streams.is_empty()
	_ms_since_bird = 0.0
	var want_accents: bool = float(layers.get("thunder_chance", 0.0)) > 0.0 \
		or bool(layers.get("whistler_enabled", false))
	_ensure_accent_timer(want_accents, _birds_armed)


## Last applied layers (tests / HUD read this without re-resolving).
func current_layers() -> Dictionary:
	return _layers.duplicate()


func _play_accent(accent_name: String, volume_db: float) -> void:
	if not _accent_streams.has(accent_name):
		return
	if _accent_pool.is_empty():
		return
	var player: AudioStreamPlayer = _accent_pool[_accent_next]
	_accent_next = (_accent_next + 1) % _accent_pool.size()
	player.stream = _accent_streams[accent_name]
	player.volume_db = volume_db
	player.play()


func _ensure_accent_timer(accents: bool, birds: bool = false) -> void:
	_accents_armed = accents
	if birds:
		_birds_armed = birds
	if accents or _birds_armed:
		if _accent_timer == null:
			_accent_timer = Timer.new()
			_accent_timer.wait_time = ACCENT_TICK_SEC
			_accent_timer.timeout.connect(_on_accent_tick)
			add_child(_accent_timer)
		if not is_inside_tree() or not _accent_timer.is_stopped():
			return
		_accent_timer.start()
	elif _accent_timer != null:
		_birds_armed = birds
		_accent_timer.stop()


func _on_accent_tick() -> void:
	if not (_accents_armed or _birds_armed):
		return
	# The bird law: the chorus clock accumulates real seconds and fires
	# a chirp whenever the density-driven interval has elapsed -- denser
	# chorus, faster calls. Runs alongside the (storm) accent law on
	# the same tick without sharing state with it.
	if _birds_armed:
		_ms_since_bird += ACCENT_TICK_SEC
		if _ms_since_bird >= _bird_interval():
			_ms_since_bird = 0.0
			_play_bird()


## Interval between chirps, driven by chorus density: a loud chorus
## calls fast, a single bird calls slow. Denser sky -> shorter wait.
func _bird_interval() -> float:
	return clampf(12.0 / maxf(1.0, _chorus_density), 1.0, 6.0)


## Fire one ambient bird chirp at a soft volume, round-robin through
## the shared accent pool (storms mute birds, so the pools never
## fight over the same speakers). No-op without loaded streams.
func _play_bird() -> void:
	if _bird_streams.is_empty() or _accent_pool.is_empty():
		return
	var keys := _bird_streams.keys()
	var player: AudioStreamPlayer = _accent_pool[_accent_next]
	_accent_next = (_accent_next + 1) % _accent_pool.size()
	player.stream = _bird_streams[keys[randi() % keys.size()]]
	player.volume_db = -10.0
	player.play()


func _set_loop_gain(loop_name: String, gain: float) -> void:
	var clamped: float = clampf(gain, 0.0, 1.0)
	if clamped <= 0.0:
		if _loop_players.has(loop_name) and is_instance_valid(_loop_players[loop_name]):
			var p: AudioStreamPlayer = _loop_players[loop_name]
			p.stop()
			_loop_players.erase(loop_name)
		return
	var player: AudioStreamPlayer
	if _loop_players.has(loop_name) and is_instance_valid(_loop_players[loop_name]):
		player = _loop_players[loop_name]
	else:
		var stream = load(str(LOOPS.get(loop_name, "")))
		if stream == null:
			GameLog.warn("AudioService: missing ambience loop '%s'" % loop_name)
			return
		# AudioStreamWAV looping is set on a per-stream basis; enable
		# loop mode on the shared resource once (idempotent).
		if stream is AudioStreamWAV:
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_end = stream.data.size() / 2  # 16-bit mono frames
		player = AudioStreamPlayer.new()
		player.bus = "Master"
		player.stream = stream
		add_child(player)
		_loop_players[loop_name] = player
		player.play()
	player.volume_db = linear_to_db(clamped)


## Stop every ambience loop and accents (zone transitions, menus).
func stop_ambience() -> void:
	for loop_name in _loop_players.keys():
		var p = _loop_players[loop_name]
		if is_instance_valid(p):
			p.stop()
	_loop_players.clear()
	_birds_armed = false
	_chorus_density = 0.0
	_ensure_accent_timer(false)
	_layers = {}


## --- Positional world noises (enemies, mounts, vehicles, props) ---

## Play a one-shot at a world position. sound_name is a SOUNDS or
## ACCENTS key; unknown names warn and no-op like play(). Uses the 3D
## pool (AudioStreamPlayer3D under the service node -- add_child keeps
## it in-tree so it emits and attenuates from its global_position).
func play_at(sound_name: String, position: Vector3, volume_db: float = 0.0) -> void:
	ensure_initialized()
	var stream = _streams.get(sound_name, _accent_streams.get(sound_name))
	if stream == null:
		GameLog.warn("AudioService: unknown positional sound '%s'" % sound_name)
		return
	if _positional_pool.is_empty():
		return
	var player: AudioStreamPlayer3D = _positional_pool[_positional_next]
	_positional_next = (_positional_next + 1) % _positional_pool.size()
	player.stream = stream
	player.global_position = position
	player.volume_db = volume_db
	player.play()


## Music: static track playback (studio renders -- almanac suite,
## atmosphere). Tracks live in game/audio/music/ as .wav. Crossfade
## is a volume ramp; a different track replaces the current one.
func play_music(track_name: String, volume_db: float = -8.0) -> void:
	ensure_initialized()
	if _music_player == null:
		return
	var path: String = "res://audio/music/%s.wav" % track_name
	if _music_path == path and _music_player.playing:
		return
	var stream = load(path)
	if stream == null:
		GameLog.warn("AudioService: missing music track '%s'" % track_name)
		return
	_music_path = path
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = stream.data.size() / 2
	_music_player.stream = stream
	_music_player.volume_db = volume_db
	_music_player.play()


func stop_music() -> void:
	if _music_player != null:
		_music_player.stop()
	_music_path = ""


## THE EXIT LAW: leaving the world (character select, logout) stops
## EVERYTHING the world left playing -- ambience loops, storm/bird
## accents, one-shots, positional world noises, music -- not just the
## ambience affinity (stop_ambience). A menu screen must be silent.
func stop_all() -> void:
	stop_ambience()
	stop_music()
	for p in _pool:
		if is_instance_valid(p):
			p.stop()
	for p in _accent_pool:
		if is_instance_valid(p):
			p.stop()
	for p in _positional_pool:
		if is_instance_valid(p):
			p.stop()
