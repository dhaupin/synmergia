extends SceneTree
func _initialize() -> void:
	await process_frame
	var bs = root.get_node_or_null("BlacksmithService")
	var bal = bs._balance()
	print("bal=", bal)
	if bal != null:
		print("base=", bal.base_chance, " delta=", bal.ore_bonus_delta, " cap=", bal.my_thic_cap)
	var chance: float = clampf(float(bal.base_chance[0]) + float(bal.ore_bonus_delta[4]), 0.0, float(bal.my_thic_cap))
	print("computed_chance=", chance)
	quit(0)
