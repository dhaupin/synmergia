extends SceneTree
func _initialize() -> void:
	await process_frame
	var ds = root.get_node_or_null("DataService")
	for e in ["troll_elite", "void_lord"]:
		var enemy = ds.get_enemy(e)
		var seen := {}
		for i in range(200):
			var roll: Dictionary = enemy.roll_loot()
			for it in roll.get("items", []):
				seen[str(it.get("item_id", ""))] = true
		print("ENEMY:", e, " SEEN:", seen.keys())
	quit(0)
