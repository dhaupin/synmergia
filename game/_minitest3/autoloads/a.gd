extends Node

func _ready() -> void:
	# First references Second (which comes LATER in the autoload list)
	if Second:
		print("First sees Second:", Second)
	else:
		print("First does NOT see Second")
