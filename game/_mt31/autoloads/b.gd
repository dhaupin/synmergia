extends Node

# b preloads a (autoload, no class_name) as const -- shadow
const First = preload("res://autoloads/a.gd")

func _ready() -> void:
	# bare reference to LATER autoload Third
	if Third and Third.has_method("try_start"):
		if not Third.try_start("x"):
			print("blocked")
	print("b ready")
