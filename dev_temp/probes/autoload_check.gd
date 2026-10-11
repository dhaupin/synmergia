extends SceneTree
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	for n in ["UIStyles", "GameManager", "PlayerManager", "InventoryService", "TitleService"]:
		print(n, "=", root.get_node_or_null(n) != null)
	quit(0)
