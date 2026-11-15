extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var OVS = load("res://core/schemas/ocean_volume.gd")
	var v = OVS.new()
	v.max_depth = 30.0
	print("b10=", v.band_for(10.0, 0.0), " b20=", v.band_for(20.0, 0.0), " b30=", v.band_for(30.0, 0.0), " b1=", v.band_for(1.0, 0.0), " bdry=", v.band_for(-0.5, 0.0))
	print("enum DRY=", OVS.DepthBand.DRY, " WADING=", OVS.DepthBand.WADING, " SUB=", OVS.DepthBand.SUBMERGED, " SQ=", OVS.DepthBand.SQUEEZE, " CR=", OVS.DepthBand.CRUSH)
	quit(0)
