extends SceneTree

## One-shot verification: every .tres in data/npc/ loads as a valid
## NPCData resource. Prints a table; exits 1 on any failure.

func _init() -> void:
	var ok := true
	var dir := DirAccess.open("res://data/npc")
	if dir == null:
		push_error("FAIL: cannot open res://data/npc")
		quit(1)
		return
	var files := []
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".tres"):
			files.append(f)
		f = dir.get_next()
	files.sort()
	for fname in files:
		var path: String = "res://data/npc/" + fname
		var res := load(path)
		if res == null:
			push_error("FAIL: %s did not load" % path)
			ok = false
			continue
		if not ("id" in res):
			push_error("FAIL: %s is not NPCData (no id)" % path)
			ok = false
			continue
		print("[OK] %-38s id=%s zone=%s" % [fname, res.id, res.get("zone_id")])
	print("--- data/npc validation: %d files, ok=%s ---" % [files.size(), str(ok)])
	quit(0 if ok else 1)
