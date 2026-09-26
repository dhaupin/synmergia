## SkyAlmanacUI -- the Concord's sky almanac (labs/prd-psy.md section 7)
##
## Shows TODAY: the four windows, which glyphs the tribe has revealed,
## observer counts vs the reveal threshold, the current window's Sign
## lore, and whether tomorrow's Ancient is unlocked. The tribal gap is
## the point -- "?" slots are an invitation to go watch the sky
## together, and the almanac never shows un-revealed glyphs.
##
## Hotkey: V (Skyward "V"iew). Registered in MenuManager + HudHotkeys.
extends "res://ui/components/ui_panel.gd"

class_name SkyAlmanacUI

const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind

const WINDOW_HOURS: Array[String] = ["00-06", "06-12", "12-18", "18-24"]

var _day_label: Label
var _rows: VBoxContainer
var _lore_label: Label
var _door_label: Label
var _blessed_label: Label
var _acts_rows: VBoxContainer
var _watch_btn: Button
var _chronicle_btn: Button
var _refresh_btn: Button


func _ready() -> void:
	super._ready()
	set_title("Sky Almanac")
	set_panel_size(Vector2(520, 520))
	_setup_ui()
	refresh()

	# Re-pull SignService truth every time the almanac opens so the
	# rows are live at open (not only at boot).
	panel_opened.connect(refresh)


func _setup_ui() -> void:
	var panel := get_panel()
	if not panel:
		return
	var main: VBoxContainer = panel.get_node_or_null("Main")
	if not main:
		return

	_day_label = Label.new()
	_day_label.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	main.add_child(_day_label)

	main.add_child(HSeparator.new())

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 6)
	main.add_child(_rows)

	main.add_child(HSeparator.new())

	_lore_label = Label.new()
	_lore_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lore_label.custom_minimum_size.y = 84
	_lore_label.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	main.add_child(_lore_label)

	main.add_child(HSeparator.new())

	_door_label = Label.new()
	_door_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main.add_child(_door_label)

	_blessed_label = Label.new()
	_blessed_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main.add_child(_blessed_label)

	main.add_child(HSeparator.new())

	# Concord Chronicle (labs/prd-psy.md section 5): the acts and
	# chapters the tribe has recorded. Scrollable so long acts do not
	# push the buttons off the panel.
	var acts_label := Label.new()
	acts_label.text = "-- The Concord Chronicle --"
	acts_label.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	main.add_child(acts_label)

	var acts_scroll := ScrollContainer.new()
	acts_scroll.custom_minimum_size = Vector2(0, 118)
	acts_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main.add_child(acts_scroll)
	_acts_rows = VBoxContainer.new()
	_acts_rows.add_theme_constant_override("separation", 3)
	_acts_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	acts_scroll.add_child(_acts_rows)

	main.add_child(HSeparator.new())

	# "Watch the sky": records THIS player's insight for the current
	# window from anywhere (the almanac is your far-gaze). This is the
	# same truth the Concord Stone records -- remote players pay the
	# same tribal price (one gaze per window).
	_watch_btn = Button.new()
	_watch_btn.text = "Watch the sky"
	_watch_btn.tooltip_text = "Record your observation of the current window (works wherever the almanac opens)"
	_watch_btn.pressed.connect(_on_watch_pressed)
	main.add_child(_watch_btn)

	_chronicle_btn = Button.new()
	_chronicle_btn.text = "Open the Chronicle"
	_chronicle_btn.tooltip_text = "Read the acts and chapters the tribe has recorded (J)"
	_chronicle_btn.pressed.connect(_on_chronicle_pressed)
	main.add_child(_chronicle_btn)

	_refresh_btn = Button.new()
	_refresh_btn.text = "Watch the sky again"
	_refresh_btn.pressed.connect(refresh)
	main.add_child(_refresh_btn)


## Hand off to the dedicated Chronicle reader (J): the almanac block
## stays the readable minimum, the panel is the shelf.
func _on_chronicle_pressed() -> void:
	if MenuManager == null:
		return
	close()
	MenuManager.toggle_menu("chronicle")


## The far-gaze: record this player's insight for the current window
## without standing at a stone (the button the almanac exists for).
## PlayerManager.get_local_player is the local-player source used by
## the HUD; in headless/script mode the fallback id keeps the panel
## testable. Then refresh() rebuilds the rows from SignService truth.
func _on_watch_pressed() -> void:
	if SignService == null:
		return
	var player_id := "almanac_observer"
	var pm := get_node_or_null("/root/PlayerManager")
	if pm != null and pm.has_method("get_local_player"):
		var local = pm.get_local_player()
		if local != null and "entity_id" in local:
			var eid := str(local.entity_id)
			if not eid.is_empty():
				player_id = eid
	var result: Dictionary = SignService.record_insight(player_id)
	var ok := bool(result.get("ok", false))
	if NotificationService != null:
		var msg := ""
		if not ok:
			msg = "The sky is unreadable right now."
		elif str(result.get("reason", "")) == "already recorded":
			msg = "You have already marked this window. %d watching." % int(result.get("observers", 1))
		elif bool(result.get("revealed_now", false)):
			msg = "Your gaze completes the Concord: the glyph is shared knowledge."
		else:
			msg = "You mark the current window. %d of %d watching." % [int(result.get("observers", 0)), int(SignService.REVEAL_OBSERVERS)]
		NotificationService.notify(
			NotifKind.SIGN_INSIGHT_RECORDED,
			msg,
			"SkyAlmanacUI",
			"almanac:watch:%s:%s" % [player_id, str(result.get("reason", "ok"))],
			{"player_id": player_id, "observers": int(result.get("observers", 0))},
			player_id
		)
	refresh()


## Rebuild the whole panel from SignService truth. Never shows
## un-revealed glyphs -- the almanac honors the tribal rule.
func refresh() -> void:
	if SignService == null:
		return
	SignService.ensure_initialized()
	var w: Dictionary = SignService.get_current_window()
	var glyphs: Array[String] = SignService.get_revealed_glyphs()
	var day: int = int(w.get("day_index", 0))
	var cur_win: int = int(w.get("window_index", 0))

	_day_label.text = "Day %d -- the Concord watches four windows" % day

	for child in _rows.get_children():
		child.queue_free()

	for i in SignService.WINDOWS_PER_DAY:
		var row := HBoxContainer.new()
		var hours := Label.new()
		hours.custom_minimum_size.x = 76
		hours.text = WINDOW_HOURS[i] if i < WINDOW_HOURS.size() else "??"
		var marker := "  <- now" if i == cur_win else ""
		var sign_name := _sign_name_for(day, i)
		var glyph_text: String = str(glyphs[i]) if i < glyphs.size() else "?"
		var glyph_label := Label.new()
		if glyph_text == "?":
			# Rumor: count without revealing.
			var obs := _observer_count_for(day, i)
			glyph_label.text = "sign of %s -- glyph unknown (%d watching)%s" % [sign_name, obs, marker]
			glyph_label.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
		else:
			glyph_label.text = "%s -- glyph '%s'%s" % [sign_name, glyph_text, marker]
			glyph_label.add_theme_color_override("font_color", UIStyles.COLORS.text_primary)
		row.add_child(hours)
		row.add_child(glyph_label)
		_rows.add_child(row)

	# Lore block: current window's Sign (only what's already public).
	var sid := str(w.get("sign_id", ""))
	var sign = SignService._signs.get(sid) if sid != "" else null
	if sign != null:
		var lore := str(sign.description)
		var hint := str(sign.observation_hint)
		if not hint.is_empty():
			lore += "\nReading: " + hint
		_lore_label.text = lore
	else:
		_lore_label.text = "The sky is quiet."

	# Door state for TODAY + tomorrow (the payoff the tribe works toward).
	var tomorrow := day + 1
	var today_open: bool = SignService.is_ancient_unlocked(day)
	var tomorrow_open: bool = SignService.is_ancient_unlocked(tomorrow)
	if tomorrow_open:
		_door_label.text = "Tomorrow's Ancient: UNLOCKED. The door will know its name."
		_door_label.add_theme_color_override("font_color", UIStyles.COLORS.success)
	elif today_open:
		_door_label.text = "Today's Ancient stands open -- pay the debt a visit."
		_door_label.add_theme_color_override("font_color", UIStyles.COLORS.success)
	else:
		_door_label.text = "Tomorrow's Ancient: sealed. Reveal all four glyphs to turn the key."
		_door_label.add_theme_color_override("font_color", UIStyles.COLORS.warning)

	# Daily Class Blessing (prd-psy.md section 8): who the wheel named,
	# and whether the day is earned (no solve, no buff).
	var blessed_id: String = SignService.get_blessed_class_id(day)
	var blessed_name := blessed_id
	if DataService != null:
		var cls = DataService.get_character_class(blessed_id)
		if cls != null:
			blessed_name = str(cls.display_name)
	var pct := int((SignService.BLESSED_DAMAGE_MULTIPLIER - 1.0) * 100.0)
	if SignService.is_blessing_active(day):
		_blessed_label.text = "Blessed today: (*) %s (+%d%% damage/heal/XP, +%d effective levels) -- that sigil rides their name all day" % [blessed_name, pct, SignService.BLESSED_LEVEL_BONUS]
		_blessed_label.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	else:
		_blessed_label.text = "Tomorrow's wheel names %s -- if the tribe turns the key." % blessed_name
		_blessed_label.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)

	# Concord Chronicle (labs/prd-psy.md section 5): acts + chapters the
	# tribe has recorded. Unrecorded chapters read as the act's frame,
	# never the lesson -- the Chronicle withholds what no door has paid
	# for, same honesty as the tribal glyph rule.
	if _acts_rows == null:
		return
	for child in _acts_rows.get_children():
		child.queue_free()
	if ActsService != null:
		ActsService.ensure_initialized()
		var act_ids: Array = ActsService.get_acts().keys()
		act_ids.sort()
		for aid in act_ids:
			var act = ActsService.get_act(str(aid))
			if act == null:
				continue
			var recorded: int = ActsService.get_recorded_chapters(str(aid)).size()
			var total: int = act.get_chapter_count()
			var act_line := Label.new()
			if recorded >= total and total > 0:
				act_line.text = "%s -- complete" % str(act.display_name)
				act_line.add_theme_color_override("font_color", UIStyles.COLORS.success)
			else:
				act_line.text = act.get_summary(recorded)
				act_line.add_theme_color_override("font_color", UIStyles.COLORS.text_primary)
			act_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_acts_rows.add_child(act_line)
			for view in ActsService.get_act_chapter_views(str(aid)):
				var ch_line := Label.new()
				ch_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				if view.recorded:
					ch_line.text = view.get_record_line()
					ch_line.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
				else:
					ch_line.text = "%d. [not yet recorded]" % int(view.index)
					ch_line.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
				_acts_rows.add_child(ch_line)


func _sign_name_for(day: int, window: int) -> String:
	if SignService == null:
		return "none"
	var s = SignService.sign_for_window(day, window)
	return str(s.display_name) if s != null else "none"


func _observer_count_for(day: int, window: int) -> int:
	if SignService == null:
		return 0
	return SignService._observer_count(day, window)
