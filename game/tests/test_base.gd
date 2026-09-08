extends SceneTree
func _init() -> void:
	# Load base, then try to use its class_name
	var ps = preload("res://adapters/persistence/persistence_store.gd")
	print("persistence_store:", ps, "has class_name:", ps.has_method("class_name") if ps else false)
	# Try to instantiate via class_name
	var s = PersistenceStore.new()
	print("PersistenceStore.new():", s)
	quit(0)
