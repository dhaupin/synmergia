extends Node

const First = preload("res://autoloads/a.gd")

func _ready() -> void:
	if Third and Third.has_method("try_start"):
		if not Third.try_start("x"):
			print("blocked")
	print("Second ready")
