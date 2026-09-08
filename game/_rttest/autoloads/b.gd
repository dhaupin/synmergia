extends Node

# Second references First bare (First is autoload + class_name)
func _ready() -> void:
	if First and First.has_method("try_start"):
		if not First.try_start("x"):
			print("blocked")
	print("Second ready")
