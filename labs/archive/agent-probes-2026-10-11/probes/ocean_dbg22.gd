extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var OVS = load("res://core/schemas/ocean_volume.gd")
	var svc = root.get_node_or_null("OceanService")
	svc.ensure_loaded()
	var crater = svc.get_volume("ocean_lunar_crater")
	var shelf = svc.get_volume("ocean_haven_shelf")
	print("rock(0,-29)=", svc.sample_depth(Vector3(0,-29,0), crater))
	print("vol(0,-12)=", svc.volume_at(Vector3(0,-12,0)).id if svc.volume_at(Vector3(0,-12,0)) != null else "null")
	print("vol(0,-5)=", svc.volume_at(Vector3(0,-5,0)).id if svc.volume_at(Vector3(0,-5,0)) != null else "null")
	var l = OVS.new(); l.max_depth = 60.0
	print("b45 g8=", l.band_for(45.0, 8.0), " (squeeze line = 60-10+8=58; 45<58 -> SUB=2)")
	print("b59 g8=", l.band_for(59.0, 8.0), " (59<60, >=58 -> SQ=3)")
	quit(0)
