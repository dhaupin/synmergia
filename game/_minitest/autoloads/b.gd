extends Node

func _ready() -> void:
	if Second:
		print("bare Second works:", Second)
	else:
		print("bare Second is null/missing")
	First.info("from B")
