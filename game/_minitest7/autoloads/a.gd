extends Node

func _ready() -> void:
	print("A ready")

func request(x):
	if Second and not Second.try_start(x):
		print("blocked")
