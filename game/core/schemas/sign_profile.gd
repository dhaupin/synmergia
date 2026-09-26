## SignProfile -- one Sky Sign (Skyward Concord lore, labs/prd-psy.md)
##
## A Sign is a data-defined celestial arrangement the whole shard sees
## in the sky. The shard's "code to the next day's Ancient unlock" is
## assembled from the day's four sign windows: each window shows one
## Sign, whose glyph order maps to a code word; the assembled sequence
## IS the vault key for tomorrow's Ancient door. Players must compare
## observations (who saw which Sign when) to assemble the order --
## the tribal clue hunt.
##
## Pure data: no behavior lives here. Consumed via DataService.
extends Resource
class_name SignProfile

@export var id: String = ""
@export var display_name: String = "Unnamed Sign"
@export var description: String = ""

## Glyph emitted to the observant: the single code word this Sign
## contributes when it is the active Sign of a window.
@export var glyph: String = ""

## Visual identity for the sky renderer (placeholder: color tint).
@export var sky_tint: Color = Color(0.6, 0.8, 1.0, 1.0)

## Optional hint line the constellation could "whisper" to players
## who study it closely. Keeps the clue hunt fair without chat spam.
@export var observation_hint: String = ""

## Icon shown in the sky-almanac UI.
@export var icon_path: String = ""


func _init() -> void:
	if id == "":
		id = display_name.to_lower().replace(" ", "_")


## One-line summary for chat/almanac output.
func get_summary() -> String:
	var line := "%s (%s)" % [display_name, id]
	if not observation_hint.is_empty():
		line += " -- %s" % observation_hint
	return line
