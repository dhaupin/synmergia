extends Node

# Second references EARLIER autoload First in function body
func _ready() -> void:
	if First and First.has_method("try_start"):
		if not First.try_start("x"):
			print("blocked")
	print("Second ready")
