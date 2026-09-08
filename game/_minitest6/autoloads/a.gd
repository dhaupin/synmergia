extends Node

func _ready() -> void:
	print("First ready")

func request(x):
	# bare reference to LATER autoload in a regular method
	if Second and not Second.try_start(x):
		print("blocked")
	print("request done")
