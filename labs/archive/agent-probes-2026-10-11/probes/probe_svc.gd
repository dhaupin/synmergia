extends SceneTree
func _initialize() -> void:
	var svc = root.get_node_or_null("SignService")
	print("svc: ", svc)
	if svc == null:
		quit(1); return
	print("has day_index_for: ", svc.has_method("day_index_for"))
	print("has sign_for_window: ", svc.has_method("sign_for_window"))
	print("day(1790371200)=", svc.day_index_for(1790371200.0), " vs day(+21599)=", svc.day_index_for(1790371200.0 + 21599.0))
	print("signs loaded: ", svc._sign_ids.size(), " -> ", svc._sign_ids)
	print("sign(1000,0): ", svc.sign_for_window(1000, 0))
	print("script: ", svc.get_script().resource_path)
	quit(0)
