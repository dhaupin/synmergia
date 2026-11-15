extends SceneTree
func _init() -> void:
	call_deferred("_go")
func _go() -> void:
	var ds = get_root().get_node_or_null("DataService")
	print("DataService: ", ds)
	if ds == null:
		quit(1); return
	var npc = ds.get_npc("npc_village_elder")
	print("get_npc -> ", npc)
	if npc != null:
		print("display_name -> ", npc.get("display_name"))
	else:
		print("get_npc returned NULL")
	quit(0)
