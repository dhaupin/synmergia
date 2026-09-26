## AudioService -- the shard's sound (the first audio in the repo)
##
## Generated one-shot WAVs (scripts/gen_door_open_audio.py, the
## model-pipeline convention: deterministic assets from scripts) played
## through a small round-robin pool of non-positional players. The door
## bell is meant to be heard EVERYWHERE in the shard -- the payoff is
## communal -- so no 3D panning: everything routes through plain
## AudioStreamPlayers at per-call volume.
##
## Autoload (after SignService/ActsService so their _ready order is
## untouched; nothing here runs at boot beyond building the pool).
## Headless-safe: every call no-ops without a scene tree.
extends Node

## name (in game/audio/) -> stream. Preloaded once; AudioStreamWAV
## resources are shareable across players.
const SOUNDS := {
	"ancient_door_open": "res://audio/ancient_door_open.wav",
	"mystery_solved": "res://audio/mystery_solved.wav",
	"ui_click": "res://audio/ui_click.wav",
}

const POOL_SIZE: int = 6

var _streams: Dictionary = {}
var _pool: Array = []
var _next: int = 0
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
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_pool.append(p)
	GameLog.info("AudioService: ready (%d sounds, pool of %d)" % [_streams.size(), _pool.size()])


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
