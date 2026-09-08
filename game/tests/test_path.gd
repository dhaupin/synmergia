extends SceneTree
func _init() -> void:
	# List what's actually at these paths via DirAccess
	var d = DirAccess.open("res://adapters/persistence/")
	if d:
		print("res://adapters/persistence/ exists")
		print("  contents:", d.get_current_dir())
		for e in d.get_list():
			print("   -", e)
	else:
		print("res://adapters/persistence/ NOT accessible")
	var d2 = DirAccess.open("res://tests/")
	if d2:
		print("res://tests/ contents:", d2.get_list())
	quit(0)
