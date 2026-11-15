extends SceneTree
func _initialize() -> void:
	var ds = root.get_node_or_null("DataService")
	if not ds._loaded:
		ds.load_all_data()
	print("signs dict: ", ds.get_signs().keys())
	var d := DirAccess.open("res://data/signs")
	if d == null:
		print("dir open FAILED")
		quit(1)
		return
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		print("file: ", f)
		f = d.get_next()
	var res = load("res://data/signs/sign_the_awakening.tres")
	print("direct load: ", res)
	if res != null:
		print("  id=", res.get("id"), " glyph=", res.get("glyph"), " script=", res.get_script().resource_path)
	quit(0)
