extends SceneTree

# In --script mode, autoload singletons are added to /root during
# SceneTree initialization, which happens AFTER _init(). Check in
# _initialize (after a process frame) to see them.
# NOTE: SceneTree is a MainLoop, not a Node -- it has no _ready()
# virtual. Everything must run from _init/_initialize.
func _init() -> void:
	print("--- in _init: root children ---")
	for c in get_root().get_children():
		print("  child: %s" % c.name)


func _initialize() -> void:
	await process_frame
	print("--- in _initialize (after 1 frame): root children ---")
	for c in get_root().get_children():
		print("  child: %s" % c.name)
	quit(0)
