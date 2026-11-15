extends SceneTree
func _initialize() -> void:
	var svc = root.get_node_or_null("SignService")
	var ds = root.get_node_or_null("DataService")
	if not ds._loaded: ds.load_all_data()
	if svc.has_method("ensure_initialized"): svc.ensure_initialized()
	var day := 66666
	svc._unlocked_days[day] = true
	svc.set_clock_override(day * 86400.0 + 3600.0)
	var blessed: String = svc.get_blessed_class_id(day)
	var other: String = ""
	for cid in svc._playable_class_ids():
		if cid != blessed:
			other = cid
			break
	print("blessed=", blessed, " other=", other)
	print("is_blessed(blessed)=", svc.is_class_blessed(blessed, day))
	print("is_blessed(other)=", svc.is_class_blessed(other, day))
	quit(0)
