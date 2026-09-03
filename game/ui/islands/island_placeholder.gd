## Placeholder node for the Islands system.
##
## Drop one of these into a scene where you want a UI panel to mount.
## Set [member island_name] to a key registered in [IslandRegistry],
## and [member load_strategy] to one of: "eager" | "visible" | "idle".
##
## [IslandManager] scans the scene tree on boot, finds these placeholders,
## and replaces each one with the actual scene from the registry.
##
## Children placed under the placeholder act as fallback content shown
## before the island mounts. They are removed when the real scene
## attaches.
extends Node
class_name IslandPlaceholder

@export var island_name: String = ""
@export var load_strategy: String = "eager"
@export var island_scene: PackedScene

var _mounted: bool = false


func _init() -> void:
	add_to_group("island_placeholders")


func is_mounted() -> bool:
	return _mounted


func mark_mounted() -> void:
	_mounted = true
