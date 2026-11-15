extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var HudLayerScript = load("res://ui/hud/hud_layer.gd")
	HudLayerScript.ensure_installed(root)
	await process_frame
	await process_frame
	var hud = root.get_node_or_null("HudLayer")
	var settings = hud.get_node_or_null("SettingsPanel")
	print("settings=", settings)
	if settings != null:
		print("panel=", settings.get_node_or_null("Panel"))
		var p = settings.get_node_or_null("Panel")
		if p != null:
			for c in p.get_children():
				print("  child: ", c.name, " (", c.get_class(), ")")
			var m = p.get_node_or_null("Main")
			print("main=", m)
			if m != null:
				for c in m.get_children():
					print("    main-child: ", c.name)
	quit(0)
