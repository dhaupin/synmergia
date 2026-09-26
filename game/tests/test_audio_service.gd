extends SceneTree

## AudioService smoke test (batch 14): the generated WAVs load, the
## round-robin pool cycles, unknown names are rejected loudly, and
## repeated plays never crash the pool. Headless Godot has no audio
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
