extends SceneTree
func _init() -> void:
	# Load base, then try to use its class_name
	var ps = preload("res://adapters/persistence/persistence_store.gd")
	print("persistence_store loaded:", ps != null)
	# Try to instantiate via class_name
	var s = PersistenceStore.new()
	print("PersistenceStore.new():", s)
	quit(0)
