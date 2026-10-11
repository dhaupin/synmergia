extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var r = load("res://data/gliders/glider_weaver_kite.tres")
	print("HIGH res=", r)
	if r != null:
		print("HIGH id=", r.get("id"), " script=", r.get_script())
	print("HIGH ResourceLoader.exists=", ResourceLoader.exists("res://data/gliders/glider_weaver_kite.tres"))
	quit(0)
