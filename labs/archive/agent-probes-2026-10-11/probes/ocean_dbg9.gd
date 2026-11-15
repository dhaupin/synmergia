extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var OVS = load("res://core/schemas/ocean_volume.gd")
	var svc = root.get_node_or_null("OceanService")
	var ladder = OVS.new()
	ladder.max_depth = 60.0
	print("grace8 b52=", ladder.band_for(52.0, 8.0), " DRY=", OVS.DepthBand.DRY, " SUB=", OVS.DepthBand.SUBMERGED)
	quit(0)
