extends SceneTree
func _init() -> void:
	var RS = load("res://core/frame/srv/resource_scan.gd")
	var all: Array[String] = RS.list_resources("res://data")
	var seen := {}
	for p in all:
		var b: String = RS.resource_base(str(p).get_file())
		if seen.has(b):
			print("DUPE: ", seen[b], " <-> ", p)
		seen[b] = p
	quit(0)
