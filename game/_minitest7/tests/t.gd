extends SceneTree

const C = preload("res://scripts/c.gd")

func _init() -> void:
	print("init; C loaded:", C != null)
	quit(0)
