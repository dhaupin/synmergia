extends SceneTree
var _t := 0.0
var _step := 0
func _initialize() -> void:
	change_scene_to_file("res://ui/menus/main_menu.tscn")
func _process(delta: float) -> bool:
	_t += delta
	if _t > 1.0 and _step == 0:
		_step = 1
		var btn: Button = current_scene.get_node_or_null("MenuButtons/PlayButton")
		if btn: btn.pressed.emit()
	elif _t > 2.0 and _step == 1:
		_step = 2
		if current_scene and current_scene.has_method("_auto_play"):
			current_scene._auto_play()
	elif _t > 4.5 and _step == 2:
		_step = 3
		print("scene=", current_scene.name if current_scene else "null")
		var hud := current_scene.get_node_or_null("HudLayer") if current_scene else null
		print("hud=", hud)
		if hud:
			var mm := hud.get_node_or_null("MenuManager")
			print("mm=", mm)
			if mm:
				var p: Control = mm._get_panel("inventory")
				print("inventory panel=", p, " visible=", p.visible if p else "-")
				print("open_panels=", mm._open_panels)
				print("instance=", mm.instance)
		quit(0)
	return false
