extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var svc = root.get_node_or_null("OceanService")
	svc.ensure_loaded()
	# (3000,-61,0): shelf floor_y=-60: -61 < -60 -> INSIDE ROCK -> -1!
	# The shelf is only 60 m deep: CRUSH band is EMPTY (squeeze line
	# = 50, max_depth = 60: at exactly max_depth band_for says CRUSH
	# but the rock is AT -60). The shelf's crush band is the last
	# meter. Use -59.5? band_for(59.5, ...): 59.5 < 60 -> SQUEEZE.
	# To feel CRUSH the shelf needs depth >= 60: impossible (rock).
	# HONEST: CRUSH exists on volumes with max_depth BELOW the floor
	# never... no: the floor IS at max_depth by construction. So CRUSH
	# is reached only by volumes where the water column EXCEEDS
	# max_depth: impossible -- max_depth DEFINES the column.
	# The real design: max_depth is where CRUSH starts, and the rock
	# is DEEPER (floor_y = max_depth + crush_band). The shelf: floor
	# at -75, max_depth 60 -> 15 m of crush water. The crater: floor
	# -30, max_depth 24 -> 6 m crush... but the pool is TAME (no
	# crush). So the pool's max_depth should be 30 = floor: no crush
	# band, squeeze starts 20.
	# DECISION: max_depth = the CRUSH line (band 4 starts here); the
	# rock lies deeper (floor_y). Tame pool: max_depth = 30 (== floor)
	# -> no crush band, and squeeze line = 30-10 = 20 -> 20..30 is
	# squeeze... but tame means NO pressure: pressure_per_meter=0
	# kills the DEPTH tax; base DPS is the squeeze's own bite. For a
	# truly tame pool the squeeze band must not exist either: set
	# max_depth = 30 == floor_y and NATURAL free = 10 -> squeeze at
	# 20. Still a squeeze band with base DPS.
	# CLEANEST TAME: base DPS scales by pressure_per_meter ENTIRELY:
	# rate = pressure_per_meter * (depth - squeeze_line). Shelf
	# (0.1/m): 5 m past line = 0.5 dps... too weak. Add base INTO
	# per-meter? The shelf's declared 0.1 then means 0.5 dps at 55.
	# Design choice: rate = PRESSURE_BASE_DPS + per_meter*(depth-line)
	# is the REAL ocean; a tame pool sets squeeze_line >= max_depth
	# (no squeeze band) via max_depth = floor depth. The pool:
	# max_depth 30 == floor -30 -> squeeze line = 20. STILL exists.
	# So: give the pool floor_y -34, max_depth 28, per_meter 0, and
	# accept base squeeze bite... NO. Owner said pool is TAME.
	# FINAL: tame = squeeze line at the floor: OceanService uses
	# NATURAL free only when the volume opts in; volumes declare
	# max_depth AS the crush line; the pool declares max_depth 30
	# (its floor) and per_meter 0; base DPS accrues only when
	# per_meter > 0 (the bite is the VOLUME's choice). Shelf: base +
	# depth tax. Pool: nothing.
	print("design settled")
	quit(0)
