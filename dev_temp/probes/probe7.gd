extends SceneTree

func _initialize() -> void:
	var order: Array[String] = []
	var f = FileAccess.open("res://project.godot", FileAccess.READ)
	var in_auto := false
	while f != null and not f.eof_reached():
		var line: String = f.get_line()
		if line.begins_with("[autoload]"):
			in_auto = true
			continue
		if in_auto and line.begins_with("["):
			break
		if in_auto and "=" in line:
			var name: String = line.split("=")[0]
			var m := RegEx.create_from_string('res://([^"]+\\.gd)')
			var mm := m.search(line)
			if mm:
				order.append(name + "|" + mm.get_string(1))
	var bad := 0
	for entry in order:
		var parts: PackedStringArray = entry.split("|")
		var sc = load("res://" + parts[1])
		if sc == null:
			print("FIRST-FAIL: %s (%s)" % [parts[0], parts[1]])
			bad += 1
			if bad >= 3:
				break
	if bad == 0:
		print("ALL AUTOLOAD SCRIPTS LOAD OK")
	quit(0)
