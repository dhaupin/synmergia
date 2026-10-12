## Benchmark for the Penrose family (frame primitive) — the numbers
## labs/world-building-research.md sec 1.7-1.9 wanted measured.
##
## Measures wall-clock (MSEC accumulate via ticks) for:
##   substitution/deflation: deflate_n over fat_seed
##   recursive point lookup: annotation_for_point at depths 4 & 6
##   pentagrid tile_at: per-probe candidate scan at 40-cell depth
##   region + validate: build_region(9) + validate_patch
##   raster soup: triangle_soup over the built region
## Results compared to the research doc's target: sub-millisecond
## point-to-tile at game-relevant scale = PASSING BENCHMARK; we
## report exact numbers so callers judge.
extends SceneTree

const P = preload("res://core/frame/math/penrose.gd")
const PG = preload("res://core/frame/math/pentagrid.gd")

func _init() -> void:
	print("== Penrose/pentagrid benchmark ==")
	var t_start: int = _now()

	var t0: int = _now()
	for _i in range(50):
		P.deflate_n(P.fat_seed(), 8)
	var t_sub: int = _now() - t0
	print("deflate_n(fat_seed, 8) x50      : %5d ms   (%.3f ms/call)" % [t_sub, float(t_sub) / 50.0])

	t0 = _now()
	var probe := Vector2(0.4, 0.3)
	for _i in range(2000):
		P.annotation_for_point(probe, 4)
	var t_lookup4: int = _now() - t0
	print("annotation_for_point(4) x2000   : %5d ms   (%.4f ms/call)" % [t_lookup4, float(t_lookup4) / 2000.0])

	t0 = _now()
	for _i in range(2000):
		P.annotation_for_point(probe, 6)
	var t_lookup6: int = _now() - t0
	print("annotation_for_point(6) x2000   : %5d ms   (%.4f ms/call)" % [t_lookup6, float(t_lookup6) / 2000.0])

	# Pentagrid global lookup: build region once (dominant cost), then
	# measure tile_at probes across the plane.
	t0 = _now()
	PG.build_region(PG.GAMMA, 10.0)
	var t_region: int = _now() - t0
	print("build_region(10.0) x1           : %5d ms" % t_region)

	t0 = _now()
	for i in range(1000):
		PG.tile_at(Vector2(float(i % 97) * 0.13, float(i % 89) * 0.17))
	var t_griddings: int = _now() - t0
	print("pentagrid.tile_at x1000         : %5d ms   (%.4f ms/call)" % [t_griddings, float(t_griddings) / 1000.0])

	t0 = _now()
	var patch: Array = PG.build_region(PG.GAMMA, 9.0)
	var res: Dictionary = PG.validate_patch(patch)
	var t_validate: int = _now() - t0
	print("validate_patch(region 9) x1     : %5d ms   (%s)" % [t_validate, str(res["ok"])])

	t0 = _now()
	PG.triangle_soup(patch)
	var t_soup: int = _now() - t0
	print("triangle_soup(region 9) x1      : %5d ms   (%d tris)" % [t_soup, patch.size() * 2])

	print("total: ", _now() - t_start, " ms")
	quit(0)

func _now() -> int:
	return int(round(Time.get_ticks_usec() / 1000.0))
