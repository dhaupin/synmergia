extends Node

func _ready() -> void:
	# bare reference to a LATER autoload in a function body
	if Second and not Second.try_start("x"):
		print("blocked")
	print("First ready ok")
