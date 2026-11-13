## diag_thread_scale - does the terrain law scale across threads?
## Times N independent cold ground_sample derives serially, then the same
## N spread over W worker threads. Reports both walls + the speedup.
extends SceneTree

const TerrainGen := preload("res://scenes/worlds/terrain_gen.gd")


func _init() -> void:
	call_deferred("_run")


var _seed: PackedByteArray
var _results := {}
var _mutex := Mutex.new()


func _dir(i: int, salt: int) -> Vector3:
	var ga: float = PI * (3.0 - sqrt(5.0))
	var y: float = 1.0 - 2.0 * (float(i) + 0.5) / 50000.0
	var r: float = sqrt(maxf(0.0, 1.0 - y * y))
	var th: float = ga * float(i)
	var rot := Vector3(0.137, 0.211, 0.093) * float(salt)
	return (Vector3(cos(th) * r, y, sin(th) * r) + rot).normalized()


func _job(lo: int, hi: int, salt: int, slot: int) -> void:
	for i in range(lo, hi):
		TerrainGen.ground_sample(_dir(i, salt), _seed)
	_mutex.lock()
	_results[slot] = true
	_mutex.unlock()


func _run() -> void:
	_seed = PackedByteArray()
	for i in range(8):
		_seed.append((i * 37 + 11) & 0xFF)
	var n: int = 1600
	print("DIAG_THREAD_SCALE procs=%d n=%d" % [OS.get_processor_count(), n])

	var t0: int = Time.get_ticks_msec()
	_job(0, n, 1, 0)
	var serial: int = Time.get_ticks_msec() - t0
	print("  SERIAL_MS=%d" % serial)

	for w in [2, 4, 8]:
		var per: int = int(ceil(float(n) / float(w)))
		var threads: Array = []
		var t1: int = Time.get_ticks_msec()
		for k in range(w):
			var lo: int = k * per
			var hi: int = mini(n, lo + per)
			var t := Thread.new()
			threads.append(t)
			t.start(Callable(self, "_job").bind(lo, hi, 2 + w, k), Thread.PRIORITY_LOW)
		for t in threads:
			t.wait_to_finish()
		var par: int = Time.get_ticks_msec() - t1
		print("  PAR_W=%d MS=%d SPEEDUP=%.2fx" % [w, par, float(serial) / maxf(1.0, float(par))])
	quit(0)
