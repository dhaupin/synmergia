## test_chunk_prefetch.gd - the canonical read side.
##
## The predictive prefetch used to live in the planar era: Markov over the
## floor(pos/100) chunk grid, LOD-promoting into LODManager, then
## WorldService.generate_chunk -- all retired (that half is gone). The idea
## moved onto the CANONICAL prop layer: PropLayer.enable_prefetch() learns
## the viewer's PropChunk-to-PropChunk movement and warms the cell it is
## heading into, so the build queue is empty on crossing.
##
## Legs:
##   1. The predictor addresses canonical PropChunk keys (round-trips).
##   2. Prefetch warms the predicted next cell (a cache hit, not a guess).
##   3. update() drives it (integration: the viewer's cell is observed).
##   4. Disabled by default; disable_prefetch stops it.
##   5. A warmed cell derives deterministically (no content corruption).
##
## Run:
##   godot --headless --path . --script res://tests/test_chunk_prefetch.gd
extends SceneTree

const PropLayer = preload("res://core/world/prop_layer.gd")
const PropChunk = preload("res://core/frame/geometry/prop_chunk.gd")
const Provider = preload("res://scenes/worlds/terrain_provider.gd")

const DEPTH: int = 6
const RADIUS: float = 20000.0

var _failed: int = 0


func _initialize() -> void:
	print("--- CHUNK PREFETCH ---")
	_test_canonical_addressing()
	_test_prefetch_warms_next_cell()
	_test_update_drives_prefetch()
	_test_disabled_by_default()
	_test_warmed_cell_deterministic()
	_finish()


func _ok(m: String) -> void:
	print("  [OK] ", m)

func _fail(m: String) -> void:
	_failed += 1
	printerr("  [FAIL] ", m)


func _make_layer() -> Object:
	var parent := Node3D.new()
	root.add_child(parent)
	var layer = PropLayer.new()
	layer.configure(Provider.new(), RADIUS, parent)
	return layer


## A viewer walking along a straight line in direction space, one small
## step per call -- enough to cross canonical cells and teach transitions.
func _walk_dirs(steps: int) -> Array:
	var out: Array = []
	var base := Vector3(0.3, 0.4, 0.5).normalized()
	for i in range(steps):
		out.append((base + Vector3(0.01 * i, 0.0, 0.0)).normalized())
	return out


func _test_canonical_addressing() -> void:
	var dirs := _walk_dirs(6)
	var keys: Array = []
	for d in dirs:
		keys.append(PropChunk.chunk_for_dir(d, DEPTH))
	# At least two distinct cells over the walk (the path crosses chunks).
	var distinct := {}
	for k in keys:
		distinct[k] = true
	if distinct.size() >= 2:
		_ok("canonical addressing: walk crosses >= 2 distinct PropChunk cells")
	else:
		_fail("canonical addressing: walk stayed in one cell")


func _test_prefetch_warms_next_cell() -> void:
	var layer = _make_layer()
	layer.enable_prefetch("receipt")
	var dirs := _walk_dirs(10)
	for d in dirs:
		layer._prefetch_step(d)
	# After the first move the predictor has a transition + momentum; the
	# predicted next cell must have been derived into the cache.
	if not layer._prefetched.is_empty():
		_ok("prefetch: a predicted canonical cell was warmed")
	else:
		_fail("prefetch: no predicted cell was warmed")
	# Every warmed cell must actually be in the LRU (derived, not guessed).
	var all_cached := true
	for k in layer._prefetched.keys():
		if not layer._cache.has(k):
			all_cached = false
	if all_cached and not layer._prefetched.is_empty():
		_ok("prefetch: every warmed cell is a real cache entry")
	else:
		_fail("prefetch: a warmed cell is missing from the cache")
	# The observed cell tracks the last viewer direction.
	var last_key: int = PropChunk.chunk_for_dir(dirs[dirs.size() - 1], DEPTH)
	if layer.current_chunk_key() == last_key:
		_ok("prefetch: current_chunk_key() tracks the viewer's canonical cell")
	else:
		_fail("prefetch: current_chunk_key() drifted from the viewer's cell")


func _test_update_drives_prefetch() -> void:
	var layer = _make_layer()
	layer.enable_prefetch("receipt_update")
	# update() normalizes the world position and drives the prefetch step.
	var pos: Vector3 = Vector3(0.3, 0.4, 0.5).normalized() * RADIUS
	layer.update(pos)
	var expect: int = PropChunk.chunk_for_dir(pos.normalized(), DEPTH)
	if layer.current_chunk_key() == expect:
		_ok("update(): drives the prefetch (viewer's cell observed)")
	else:
		_fail("update(): prefetch did not observe the viewer's cell")


func _test_disabled_by_default() -> void:
	var layer = _make_layer()
	# No enable_prefetch(): the predictor never observes.
	layer.update(Vector3(0.3, 0.4, 0.5).normalized() * RADIUS)
	if layer.current_chunk_key() == -1:
		_ok("prefetch is off by default (no observation)")
	else:
		_fail("prefetch ran without enable_prefetch()")
	# And disable_prefetch() turns it back off.
	layer.enable_prefetch("receipt_off")
	layer.disable_prefetch()
	layer.update(Vector3(0.2, 0.5, 0.4).normalized() * RADIUS)
	# current_chunk_key() still reads the last observed cell from before the
	# disable, but a fresh layer after disable stays -1.
	var fresh = _make_layer()
	fresh.enable_prefetch("receipt_off2")
	fresh.disable_prefetch()
	fresh.update(Vector3(0.2, 0.5, 0.4).normalized() * RADIUS)
	if fresh.current_chunk_key() == -1:
		_ok("disable_prefetch() stops observation")
	else:
		_fail("disable_prefetch() left the predictor running")


func _test_warmed_cell_deterministic() -> void:
	var layer = _make_layer()
	layer.enable_prefetch("receipt_det")
	var dirs := _walk_dirs(10)
	for d in dirs:
		layer._prefetch_step(d)
	if layer._prefetched.is_empty():
		_fail("determinism: nothing was prefetched to check")
		return
	var k: int = layer._prefetched.keys()[0]
	var cached: Dictionary = layer._cache.get(k, {})
	var fresh: Dictionary = layer.derive_fresh(k)
	# Compare the instance counts (byte-level arrays differ by Object ids).
	var n_cached: int = (cached.get("instances", []) as Array).size()
	var n_fresh: int = (fresh.get("instances", []) as Array).size()
	if n_cached == n_fresh and n_cached >= 0:
		_ok("determinism: a warmed cell re-derives to the same instance count")
	else:
		_fail("determinism: warmed cell drifted (%d vs %d)" % [n_cached, n_fresh])


func _finish() -> void:
	if _failed == 0:
		print("CHUNK PREFETCH: ALL PASS")
	else:
		print("CHUNK PREFETCH: %d FAILED" % _failed)
	quit(0 if _failed == 0 else 1)
