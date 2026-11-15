extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var OVS = load("res://core/schemas/ocean_volume.gd")
	# is band_for STATIC-called on the script in my probe?? No. Try
	# the exact probe construction: does ladder.band_for(52.0, 8.0)
	# on a fresh OVS.new() with max_depth=60 return SUBMERGED(2)?
	var ladder = OVS.new()
	ladder.max_depth = 60.0
	print("a: ", ladder.band_for(52.0, 8.0))
	# now what the probe actually does -- maybe max_depth on the LADDER
	# differs. Print it:
	print("max_depth=", ladder.max_depth)
	# Also: is band_for overloaded in service? grep said no.
	# The probe uses ladder -- b52 grace8 should be 2 (52 < 60-10-8=42? NO: 60-10-8=42, 52>=42 so SQUEEZE!)
	# My test comment math was wrong: grace EXTENDS the swim band
	# DOWNWARD: squeeze starts at max_depth - 10 - grace = 42 only
	# with grace 8. Without grace it starts at 50. So b52 grace0=SQ(3)
	# is right; b52 grace8 should ALSO be SQ (52>42). The assertion
	# "breather pushes squeeze deeper" needs depths straddling 42-50.
	print("b45 g0=", ladder.band_for(45.0, 0.0), " b45 g8=", ladder.band_for(45.0, 8.0))
	quit(0)
