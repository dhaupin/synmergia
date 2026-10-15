## ChronicleUI -- the Concord Chronicle reader (labs/prd-psy.md section 5)
##
## The shelf for the shard's shared memory: every act the tribe has
## unlocked, every recorded chapter readable in full, unrecorded ones
## as sealed frames that say what they wait on (never the lesson).
## Built to grow: future mysteries, puzzles, and lore blocks hang on
## the same scroll via _add_section().
##
## Hotkey: J ("journal"). Registered in MenuManager as "chronicle".
## The almanac's "Open the Chronicle" button lands here too.
extends "res://ui/components/ui_panel.gd"

class_name ChronicleUI

var _sections: VBoxContainer


func _ready() -> void:
	super._ready()
	set_title("The Concord Chronicle")
	set_panel_size(Vector2(560, 560))
	_setup_ui()
	refresh()
	# Re-pull service truth every time the panel opens.
	panel_opened.connect(refresh)


func _setup_ui() -> void:
	var panel := get_panel()
	if not panel:
		return
	var main: VBoxContainer = panel.get_node_or_null("Main")
	if not main:
		return
	var scroll := preload("res://ui/components/drag_scroll.gd").new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main.add_child(scroll)
	_sections = VBoxContainer.new()
	_sections.add_theme_constant_override("separation", 10)
	_sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_sections)


## Rebuild every section from service truth. The Chronicle withholds
## what no door has paid for: unrecorded chapters render as sealed
## frames (they name what they WAIT on -- calendar knowledge, not the
## lesson itself).
func refresh() -> void:
	if _sections == null:
		return
	for child in _sections.get_children():
		child.queue_free()
	_add_acts_section()
	_add_mysteries_section()
	_add_concord_hint()


## The acts and chapters, readable in full once recorded.
func _add_acts_section() -> void:
	if ActsService == null:
		return
	ActsService.ensure_initialized()
	var act_ids: Array = ActsService.get_acts().keys()
	act_ids.sort()
	for aid in act_ids:
		var act = ActsService.get_act(str(aid))
		if act == null:
			continue
		var lines: Array = []
		if not str(act.description).is_empty():
			lines.append(str(act.description))
		for view in ActsService.get_act_chapter_views(str(aid)):
			if view.recorded:
				lines.append("")
				lines.append(view.get_record_line())
			elif int(view.gate_day) >= 0:
				lines.append("%d. [sealed -- opens when day %d's Ancient is earned]" % [int(view.index), int(view.gate_day)])
			else:
				lines.append("%d. [sealed -- the next door open records it]" % int(view.index))
		_add_section("%s (%d/%d recorded)" % [str(act.display_name), ActsService.get_recorded_chapters(str(aid)).size(), act.get_chapter_count()], lines)


## Chronicle mysteries (data/mysteries/): locked mysteries tease,
## unlocked ones show the riddle + an answer field, solved ones record
## the finding. The riddle IS the data; answers are derived from the
## sky's own record, never stored.
func _add_mysteries_section() -> void:
	if ActsService == null:
		return
	ActsService.ensure_initialized()
	var mystery_ids: Array = ActsService.get_mysteries().keys()
	mystery_ids.sort()
	for mid in mystery_ids:
		var m = ActsService.get_mystery(str(mid))
		if m == null:
			continue
		if not ActsService.is_mystery_unlocked(str(mid)):
			_add_section("%s [sealed -- the Chronicle gates it]" % str(m.display_name), [
				"Some records wait for their chapter.",
			])
			continue
		if ActsService.is_mystery_solved(str(mid), _observer_id()):
			_add_section("%s -- solved" % str(m.display_name), [
				str(m.riddle),
				"",
				"The record opens. The Concord remembers who paid attention.",
			])
			continue
		# Unlocked and unsolved: the riddle + the attempt field.
		var box := VBoxContainer.new()
		var title := Label.new()
		title.text = str(m.display_name)
		title.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
		box.add_child(title)
		var riddle := Label.new()
		riddle.text = str(m.get_riddle_line())
		riddle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		riddle.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
		box.add_child(riddle)
		var row := HBoxContainer.new()
		var input := LineEdit.new()
		input.name = "AnswerInput_%s" % str(mid)
		input.placeholder_text = "speak the answer"
		input.custom_minimum_size.x = 260
		input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(input)
		var btn := Button.new()
		btn.text = "Speak"
		btn.pressed.connect(_on_mystery_submit.bind(str(mid), input))
		row.add_child(btn)
		box.add_child(row)
		_sections.add_child(box)
		var spacer := Control.new()
		spacer.custom_minimum_size.y = 6
		_sections.add_child(spacer)


## Whose ledger are we reading? PlayerManager local player in-game;
## a stable offline id for headless contexts.
func _observer_id() -> String:
	var pm := get_node_or_null("/root/PlayerManager")
	if pm != null and pm.has_method("get_local_player"):
		var local = pm.get_local_player()
		if local != null and "entity_id" in local:
			var eid := str(local.entity_id)
			if not eid.is_empty():
				return eid
	return "chronicle_reader"


## An attempt was spoken: route through ActsService truth, then
## feedback toast + rebuild (solved mysteries flip their block).
func _on_mystery_submit(mystery_id: String, input: LineEdit) -> void:
	var attempt := str(input.text)
	if ActsService == null or attempt.strip_edges().is_empty():
		return
	var result: Dictionary = ActsService.attempt_mystery(mystery_id, _observer_id(), attempt)
	if NotificationService != null:
		var msg := ""
		var NotifKindConst = load("res://core/notifications/notification_kind.gd").NotifKind
		var kind: int = NotifKindConst.CUSTOM
		match str(result.get("reason", "")):
			"":
				msg = "The Chronicle accepts your answer."
				kind = NotifKindConst.ACHIEVEMENT_UNLOCKED
			"wrong":
				msg = "The record stays silent. That is not what the sky said."
			"locked":
				msg = "The Chronicle gates this mystery still."
			"already":
				msg = "You have already answered this one."
			_:  # "unknown" and anything unexpected
				msg = "The Chronicle holds no such record."
		NotificationService.notify(
			kind,
			msg,
			"ChronicleUI",
			"chronicle:mystery:%s:%s" % [mystery_id, str(result.get("reason", "err"))],
			{"mystery_id": mystery_id},
			_observer_id()
		)
	var audio = get_node_or_null("/root/AudioService")
	if audio != null and audio.has_method("play_ui"):
		if bool(result.get("ok", false)):
			audio.play_ui("mystery_solved", -2.0)
		else:
			audio.play_ui("ui_click", -8.0)
	refresh()


## The living part of the world: a short pointer into the Concord loop.
func _add_concord_hint() -> void:
	_add_section("The Skyward Concord", [
		"Four windows a day, one sign each. Three watchers make a glyph public.",
		"Assemble the code and tomorrow's Ancient door opens -- and the Chronicle takes its chapter.",
		"Watch the sky from the almanac (V) or at any Concord Stone.",
	])


## EXTENSION POINT for future mysteries and puzzles: append a titled
## block of lines to the scroll. Keep copy historical (prd-psy.md
## section 4) -- record, lesson, observation; never faith language.
func _add_section(title: String, lines: Array) -> void:
	if _sections == null:
		return
	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	_sections.add_child(title_label)
	for line in lines:
		var l := Label.new()
		l.text = str(line)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
		_sections.add_child(l)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 6
	_sections.add_child(spacer)
