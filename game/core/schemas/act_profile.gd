## ActProfile -- one Act of the Concord Chronicle (labs/prd-psy.md)
##
## Acts are unlockable narrative blocks that teach, as historical
## RECORD of the past world, the lessons religions teach anyway. Pure
## data: no behavior lives here. Consumed via DataService.
##
## The tribal rule holds: an act advances only when the shard's Ancient
## door opens (the tribe assembled the sky code). No single player can
## unseal an act alone -- the door IS the milestone.
extends Resource
class_name ActProfile

## One recorded chapter: a lesson from the past world. The typed view
## over an authored chapter Dictionary -- .tres chapters are plain
## Dictionaries (the QuestData objectives pattern: typed inner-class
## arrays do not survive .tres serialization). `recorded` is runtime
## state supplied by ActsService persistence, never authored.
class ChapterProfile:
	## Chapter number within the act (1-based, sequential).
	var index: int = 1
	## Who wrote this record (in-world author or people).
	var source_name: String = ""
	## The lesson, written as history. Never faith language
	## (prd-psy.md section 4): no prayer, holy, sacred, worship,
	## divine, miracle. "Blessed" is reserved for the wheel's
	## observational usage and appears nowhere in act copy.
	var record_text: String = ""
	## Day whose Ancient unlock must be open for this chapter to
	## record. -1 = record on the next door open after the previous
	## chapter (fill-in-the-sequence).
	var gate_day: int = -1
	## True once the chapter has been recorded (runtime).
	var recorded: bool = false

	## Build the typed view from an authored chapter dict.
	static func from_dict(d: Dictionary, is_recorded: bool) -> ChapterProfile:
		var ch := ChapterProfile.new()
		ch.index = int(d.get("index", 0))
		ch.source_name = str(d.get("source_name", ""))
		ch.record_text = str(d.get("record_text", ""))
		ch.gate_day = int(d.get("gate_day", -1))
		ch.recorded = is_recorded
		return ch

	## The record line shown in the almanac.
	func get_record_line() -> String:
		return "%d. %s: %s" % [index, source_name, record_text]


@export var id: String = ""
@export var display_name: String = "Unnamed Act"
@export var description: String = ""

## How the act's unlock relates to the clock. Door opens for days
## >= advance_from_day advance this act; -1 = the act fills from the
## next door open (records what already happened).
@export var advance_from_day: int = -1

## The act's chapters, in order. Authored as Dictionaries:
## {index, source_name, record_text, gate_day}.
@export var chapters: Array = []


func _init() -> void:
	if id == "":
		id = display_name.to_lower().replace(" ", "_")


func get_chapter_count() -> int:
	return chapters.size()


## Typed chapter views with ActsService's recorded flags applied.
## recorded_flags maps chapter index (int) -> true.
func get_chapter_profiles(recorded_flags: Dictionary = {}) -> Array[ChapterProfile]:
	var out: Array[ChapterProfile] = []
	for d in chapters:
		if not (d is Dictionary):
			continue
		var idx := int(d.get("index", 0))
		out.append(ChapterProfile.from_dict(d, recorded_flags.has(idx)))
	return out


## Human-readable act summary for the almanac / lore panels.
## recorded = how many chapters ActsService has recorded so far.
func get_summary(recorded: int = 0) -> String:
	return "%s (%d/%d chapters recorded) -- %s" % [
		display_name, recorded, get_chapter_count(), description]
