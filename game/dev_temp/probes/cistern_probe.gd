## cistern_probe - S15.5 the Glow Cistern's receipt (the pool gets the glow):
##   1) the water lives as DATA: ocean_deep_root_pool loads off
##      OceanService (LOCAL floor, floor on the walk line, gentle pool);
##   2) the claim law on the underworld shelf: a body standing ON the
##      dish slab reads swim depth (~1.4 m below the waterline); a body
##      standing on the camp shelf OUTSIDE the dish is DRY (no volume
##      claims it); a mid-air splash reads negative (above the line);
##      a body pushed INTO the stone reads the -1 sentinel (the rock
##      is not water);
##   3) the stone stands named: 1 slab + 7 tall walls + 1 sheave bench
##      under one GlowCistern root, and the bench tops BELOW the wall
##      tops (the one honest exit is the bench, not a fence-hop);
##   4) the glow law: cistern_glow(0) > cistern_glow(0.5), and the
##      runtime water material's emission sits in the law's band.
## Run headless: godot --headless --path . --script res://dev_temp/probes/cistern_probe.gd
extends SceneTree

const UNDER_SCENE := "res://scenes/worlds/globe_underworld.tscn"
const WADING_DEPTH_M := 1.2   # the swim law's own threshold (swim_state)

# SCRIPT-MODE LAW: no const preloads of game scripts -- autoload
# identifiers register AFTER parse, so a parse-time preload of any
# script that names an autoload fails to compile here (the
# probe_underworld lesson: load at RUNTIME, inside _run).

var _fails := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("CISTERN-PASS %s %s" % [label, detail])
	else:
		_fails += 1
		print("CISTERN-MISS %s %s" % [label, detail])


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var OceanServiceScript = load("res://core/services/ocean_service.gd")
	var OceanVolumeScript = load("res://core/schemas/ocean_volume.gd")
	var GlobeScript = load("res://scenes/worlds/globe_underworld.gd")
	# Boot the conjured globe (the probe_underworld pattern: the scene
	# SceneTree root, frames flowed for _ready and the first physics).
	var packed: PackedScene = load(UNDER_SCENE)
	if packed == null:
		print("CISTERN-MISS globe_underworld.tscn missing")
		quit(1)
		return
	var under: Node = packed.instantiate()
	root.add_child(under)
	for _i in range(10):
		await root.get_tree().process_frame
	# 1) THE WATER IS DATA
	var svc = OceanServiceScript.new()
	root.add_child(svc)
	for _i in range(2):
		await root.get_tree().process_frame
	var vol = svc.get_volume("ocean_deep_root_pool")
	if vol == null:
		print("CISTERN-MISS ocean_deep_root_pool did not load")
		quit(1)
		return
	_check("volume", true, "id=%s local=%s floor_y=%.1f" % [str(vol.id), str(bool(vol.floor_is_radial)), float(vol.floor_y)])
	_check("local_floor", not bool(vol.floor_is_radial) and absf(float(vol.floor_y) - 2000.0) < 0.001)
	_check("gentle", float(vol.pressure_per_meter) == 0.0 and float(vol.max_depth) >= 2.5)
	# 2) THE CLAIM LAW (all four readings, one truth per stance)
	var in_standing := Vector3(12.0, 2001.0, 0.0)       # slab center, chest line
	var out_shelf := Vector3(17.0, 2001.0, 0.0)         # dry ground beside the dish
	var mid_splash := Vector3(12.0, 2003.0, 0.0)        # mid-air above the pool
	var in_rock := Vector3(12.0, 1999.5, 0.0)           # pressed into the stone
	var d_in: float = svc.sample_depth(in_standing)
	var d_out: float = svc.sample_depth(out_shelf)
	var d_air: float = svc.sample_depth(mid_splash)
	var d_rock: float = svc.sample_depth(in_rock)
	print("CISTERN depth in=%.2f out=%.2f air=%.2f rock=%.2f" % [d_in, d_out, d_air, d_rock])
	_check("swim_depth", absf(d_in - 1.4) < 0.2 and d_in > WADING_DEPTH_M)
	_check("dry_shelf", d_out < 0.0 and svc.volume_at(out_shelf) == null)
	_check("air_negative", d_air < 0.0)
	_check("rock_sentinel", d_rock == -1.0)
	var band_in: int = svc.band_at(in_standing)
	_check("band_wet", band_in != OceanVolumeScript.DepthBand.DRY, "band=%d" % band_in)
	_check("band_air", svc.band_at(mid_splash) == OceanVolumeScript.DepthBand.DRY)
	# 3) THE STONE (named pieces, one root, the bench is the low exit)
	var wr: Node = under.get("world_root")
	var jug: Node = wr.get_node_or_null("GlowCistern")
	if jug == null:
		print("CISTERN-MISS GlowCistern missing under WorldRoot")
		quit(1)
		return
	var slab: Node = jug.get_node_or_null("CisternSlab")
	var bench: Node = jug.get_node_or_null("CisternBench")
	var water: Node = jug.get_node_or_null("CisternWater")
	_check("stones", slab != null and bench != null and water != null)
	var walls := 0
	for c in jug.get_children():
		if c.name.begins_with("CisternWall_"):
			walls += 1
	_check("wall_ring", walls == 7, "walls=%d" % walls)
	if bench != null:
		var bench_top: float = float(bench.position.y) + float(bench.mesh.size.y) / 2.0
		var wall_top: float = 0.0
		var water_y: float = float(water.position.y)
		for c in jug.get_children():
			if c.name.begins_with("CisternWall_"):
				wall_top = float(c.position.y) + float(c.mesh.size.y) / 2.0
		print("CISTERN tops water=%.2f bench=%.2f wall=%.2f" % [water_y, bench_top, wall_top])
		_check("bench_exit_low", bench_top < wall_top)
		_check("water_under_wall", water_y < wall_top)
		_check("exit_above_water", bench_top > water_y and bench_top - water_y <= 0.4, "step=%.2f" % (bench_top - water_y))
	# 4) THE GLOW LAW
	var g_hi: float = GlobeScript.cistern_glow(0.0)
	var g_lo: float = GlobeScript.cistern_glow(0.5)
	print("CISTERN glow hi=%.3f lo=%.3f" % [g_hi, g_lo])
	_check("glow_band", g_hi > g_lo and g_lo >= 0.45 and g_hi <= 1.0)
	var wmat = under.get("_cistern_water_mat")
	if wmat != null:
		var phase: float = under._glow_tide_phase()
		var expected: float = GlobeScript.cistern_glow(phase)
		var actual: float = float(wmat.emission_energy_multiplier)
		print("CISTERN rider phase=%.3f expected=%.3f actual=%.3f" % [phase, expected, actual])
		_check("rider_in_band", absf(actual - expected) < 0.05 and actual >= g_lo - 0.05 and actual <= g_hi + 0.05)
	else:
		print("CISTERN-MISS cistern water material absent")
	if _fails > 0:
		print("CISTERN-FAIL %d" % _fails)
		quit(1)
		return
	print("CISTERN-OK")
	quit(0)
