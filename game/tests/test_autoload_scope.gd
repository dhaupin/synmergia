extends SceneTree

# In --script mode, autoload singletons are added to /root during
# SceneTree initialization, which happens AFTER _init(). Check in
# _ready (or after a process frame) to see them.
func _init() -> void:
	print("--- in _init: root children ---")
	for c in get_root().get_children():
		print("  child: %s" % c.name)

func _ready() -> void:
	print("--- in _ready: root children ---")
	for c in get_root().get_children():
		print("  child: %s" % c.name)
	quit(0)
