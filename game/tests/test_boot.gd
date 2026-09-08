extends SceneTree
func _init() -> void:
	# Simulate a normal boot: give it time to load autoloads and
	# the main scene, then report what actually made it into the tree.
	var timer := Timer.new()
	add_child(timer)
	timer.wait_time = 3.0
	timer.timeout.connect(_report)
	timer.start()
	await self.process_frame
	await self.process_frame

func _report() -> void:
	var root = self
	print("ROOT CLASS:", root.get_class())
	print("ROOT CHILDREN:", root.get_child_count())
	for i in range(min(root.get_child_count(), 20)):
		print("  child:", root.get_child(i).name)
	quit(0)
