## MysteryData -- one Chronicle mystery (labs/prd-psy.md section 5)
##
## Riddles keyed to the Concord Chronicle: a mystery's gate names an
## act chapter; once that chapter RECORDS, the riddle becomes
## attemptable. Answers are DERIVED, never stored: `answer_day` names
## a day whose sky code (SignService.get_ancient_code) is the
## answer -- the almanac is the world's memory, and the sky's own
## record is the key. Sky-code mysteries first; future cipher/observation
## types hang on the same data shape.
##
## Rewards read like the Concord's values: a NAME (title via
## TitleService) and a little XP -- attention is the highest honor.
## Pure data, consumed via DataService. No behavior lives here.
extends Resource
class_name MysteryData

## How the answer is checked. SKY_CODE = the day's 4-glyph code,
## joined with dashes ("WAKE-SUNKEN-GROVE-WAKE").
enum AnswerKind {
	SKY_CODE,       # Answer is get_ancient_code(answer_day)
	FORECAST,       # Future: observation/pattern mysteries
}

@export var id: String = ""
@export var display_name: String = "Unnamed Mystery"
@export var riddle: String = ""
## The gate: act + chapter that must be RECORDED before attempts count.
@export var gate_act_id: String = ""
@export var gate_chapter_index: int = 1

## Answer derivation.
@export var answer_kind: AnswerKind = AnswerKind.SKY_CODE
## Day whose sky code IS the answer (derived at check time -- the
## answer exists in the world, not in this file).
@export var answer_day: int = -1

## Hint line the Chronicle shows to observant readers.
@export var hint: String = ""

## Rewards: a name and a little progress.
@export var reward_title_id: String = ""
@export var reward_xp: int = 50


func _init() -> void:
	if id == "":
		id = display_name.to_lower().replace(" ", "_")


## Normalized answer text for SKY_CODE mysteries (derived, dashes).
func expected_answer(sky_code: String) -> String:
	match answer_kind:
		AnswerKind.SKY_CODE:
			return str(sky_code).to_upper().strip_edges()
		_:
			return ""


func get_riddle_line() -> String:
	var line := riddle
	if not hint.is_empty():
		line += "\nReading: " + hint
	return line
