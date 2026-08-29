extends Node

func _ready():
    var entity_class = load("res://core/entities/entity.gd")
    print("Entity class loaded: ", entity_class)
    get_tree().quit()
