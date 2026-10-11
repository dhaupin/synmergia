extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var svc = root.get_node_or_null("OceanService")
	var OVS = load("res://core/schemas/ocean_volume.gd")
	# Probe's band calls: OVS.band_for -- does the SCRIPT have the enum?
	print("script has band_for=", OVS.band_for != null, " script enum=", OVS.DepthBand)
	print("call via script=", OVS.band_for(10.0, 0.0))
	var crater = svc.get_volume("ocean_lunar_crater")
	var shelf = svc.get_volume("ocean_haven_shelf")
	print("vol crater identity=", svc.volume_at(Vector3(0, 1180.0, 0)) == crater, " is shelf=", svc.volume_at(Vector3(0, 1180.0, 0)) == shelf)
	# Crater rock clamp
	print("rock depth=", svc.sample_depth(Vector3(0, 1191.0, 0), crater))
	print("under rock=", svc.sample_depth(Vector3(0, 1190.0, 0), crater))
	# crater current
	print("crater current len=", svc.current_at(Vector3(0, -8, 0)).length(), " declared=", crater.current_vector().length())
	quit(0)
