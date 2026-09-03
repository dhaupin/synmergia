extends Node3D
class_name SynmergiaEntity

enum EntityType {
    NONE = 0,
    PLAYER = 1,
    ENEMY = 2,
    NPC = 4
}

var entity_id: String = ""
var display_name: String = "Entity"
var entity_type: EntityType = EntityType.NPC

func _ready() -> void:
    pass
