## ModelData - the canonical model record.
## The .glb is the runtime asset; this record is the only place that names it.
extends Resource
class_name ModelData

enum Kind {
	ACTOR,
	PROP,
	BLOCK
}

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var kind: Kind = Kind.ACTOR
@export_file("*.glb") var asset_path: String = ""
@export var scale: float = 1.0
@export var animation_clips: Dictionary = {}
@export var source_path: String = ""
@export var generator: String = ""
@export var license: String = ""
@export var attachment_points: Dictionary = {}
