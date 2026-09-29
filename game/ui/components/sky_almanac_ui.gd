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
const WorldRegistry = preload("res://core/frame/srv/world_registry.gd")

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

## The moon page (S16.5, prd-multiworld sec 4): the blank page fills
## with the same closed-form math the Moon Gate reads -- where the
## moon IS, how aligned the sky is, when the next window opens. The
## chart and the stone can never disagree: one derivation, two
## readers.
var _moon_title: Label
var _moon_rows: VBoxContainer
var _sail_rows: VBoxContainer
var _registry = null


func _ready() -> void:
	super._ready()
	set_title("Sky Almanac")
	set_panel_size(Vector2(520, 620))
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

	# The moon page (prd-multiworld sec 4): "the almanac gets a moon
	# page that has been blank since forever". It reads the lattice
	# live at open/refresh -- where the moon is, how the sky aligns,
	# when the next window opens.
	_moon_title = Label.new()
	_moon_title.text = "-- The Moon Page --"
	_moon_title.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	main.add_child(_moon_title)

	_moon_rows = VBoxContainer.new()
	_moon_rows.add_theme_constant_override("separation", 3)
	main.add_child(_moon_rows)

	main.add_child(HSeparator.new())

	# The sailing page (prd-ocean-depths sec 9: "the almanac gets a
	# sailing page"): the ferry's own declaration, read live -- when
	# the next boat casts off and how long the crossing takes. Closed
	# form off the Concord day, like the moon: chart and dock agree.
	var sail_title := Label.new()
	sail_title.text = "-- The Sailing Page --"
	sail_title.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	main.add_child(sail_title)

	_sail_rows = VBoxContainer.new()
	_sail_rows.add_theme_constant_override("separation", 3)
	main.add_child(_sail_rows)

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

	# The moon page: the same math the Moon Gate reads, derived live.
	# Nothing here is stored -- where the moon is, how aligned the sky
	# is, and when the next window opens are all functions of the
	# epoch (the clock you wind once). The page is the far-gaze's
	# chart: it names the window the Gate will honor.
	_refresh_moon_page(day)

	# The sailing page: the ferry's schedule derived live (sec 9).
	_refresh_sailing_page(day)

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


## The moon page rows (S16.5). The moon's declaration carries its own
## lore; the page reads the sky live and reports what the Gate's law
## will decide. Window math: WorldRegistry.window_favorability (the
## Gate's threshold is the gate's business -- the chart shows the
## alignment itself, plus the next window the Gate's threshold
## implies).
func _refresh_moon_page(day: int) -> void:
	if _moon_rows == null:
		return
	for child in _moon_rows.get_children():
		child.queue_free()
	var reg = _moon_registry()
	var moon = reg.get_world("moon") if reg != null else null
	if reg == null or moon == null:
		var missing := Label.new()
		missing.text = "The moon is not on any chart."
		missing.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
		_moon_rows.add_child(missing)
		return
	var main_w = reg.get_world("main")
	var epoch: float = _moon_epoch_days()

	# Where is it: closed-form orbit position (meters, world frame).
	var pos: Vector3 = WorldRegistry.orbit_position(moon, epoch)
	var pos_row := Label.new()
	if pos == Vector3.ZERO:
		pos_row.text = "The pale stone does not move."
	else:
		pos_row.text = "The pale stone stands %.0f km out, on its %.1f-day walk." % [pos.length() / 1000.0, float(moon.orbit_period_days)]
	pos_row.add_theme_color_override("font_color", UIStyles.COLORS.text_primary)
	_moon_rows.add_child(pos_row)

	# The sky alignment (the Gate's window law reads the same number).
	var fav: float = WorldRegistry.window_favorability(main_w, moon, epoch)
	var fav_row := Label.new()
	if fav <= 0.25:
		fav_row.text = "The sky aligns (%.0f%%) -- the gate will take you." % [(1.0 - fav) * 100.0]
		fav_row.add_theme_color_override("font_color", UIStyles.COLORS.success)
	elif fav >= 0.75:
		fav_row.text = "The sky is against it (%.0f%% aligned)." % [(1.0 - fav) * 100.0]
		fav_row.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	else:
		fav_row.text = "The sky leans your way (%.0f%% aligned) -- soon." % [(1.0 - fav) * 100.0]
		fav_row.add_theme_color_override("font_color", UIStyles.COLORS.warning)
	_moon_rows.add_child(fav_row)

	# The next window (same search the Gate's refusal message uses).
	var next_e: float = WorldRegistry.next_transfer_window(main_w, moon, epoch, 0.25)
	var next_row := Label.new()
	if next_e >= 0.0:
		var days_ahead: float = maxf(next_e - epoch, 0.0)
		var day_of: int = day + int(ceil(days_ahead))
		next_row.text = "Next favorable window: Day %d (%.1f days out)." % [day_of, days_ahead]
		next_row.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	else:
		next_row.text = "No window opens within the chart's horizon."
		next_row.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	_moon_rows.add_child(next_row)

	# The mystery hook (prd-multiworld sec 4): the page has been blank
	# since forever; the lore is the moon's own declaration. One day
	# someone fills it -- the chart already tells them when to go.
	var lore := str(moon.lore).strip_edges()
	if lore != "":
		var lore_row := Label.new()
		lore_row.text = lore
		lore_row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lore_row.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
		_moon_rows.add_child(lore_row)


## The moon page's registry: lazy, per-panel, frame primitive.
func _moon_registry():
	if _registry == null:
		_registry = WorldRegistry.new()
		_registry.load_worlds()
	return _registry


## The moon page reads the same canonical epoch as the Gate and the
## sky (SignService.sky_epoch_days -- override-aware).
func _moon_epoch_days() -> float:
	if SignService != null and SignService.has_method("sky_epoch_days"):
		return SignService.sky_epoch_days()
	return float(Time.get_unix_time_from_system()) / 86400.0


## The sailing page rows (prd-ocean-depths sec 9). The ferry's own
## declaration carries its schedule -- closed form off the Concord
## day, exactly like the moon's orbit -- so the chart and the dock
## can never disagree: one declaration, two readers (the almanac now,
## the FerryService when it sails). No scheduled ferry = the page
## stays honest: the tide table is blank.
func _refresh_sailing_page(day: int) -> void:
	if _sail_rows == null:
		return
	for child in _sail_rows.get_children():
		child.queue_free()
	var ferries := _sail_ferries()
	if ferries.is_empty():
		var none := Label.new()
		none.text = "The tide table is blank. No ferry runs a schedule yet."
		none.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
		_sail_rows.add_child(none)
		return
	var ferry: Dictionary = ferries[0]
	var route_row := Label.new()
	route_row.text = "%s: %s -- %s (%d cast-offs a day)" % [str(ferry["name"]), str(ferry["from"]), str(ferry["to"]), int(ferry["per_day"])]
	route_row.add_theme_color_override("font_color", UIStyles.COLORS.text_primary)
	_sail_rows.add_child(route_row)
	var cross_row := Label.new()
	cross_row.text = "The crossing takes %.0f minutes -- the current does the rowing." % [float(ferry["cross_h"]) * 60.0]
	cross_row.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	_sail_rows.add_child(cross_row)
	var dep: Dictionary = ferry["dep"]
	var dep_row := Label.new()
	if bool(dep.get("departing", false)):
		dep_row.text = "CASTING OFF NOW -- be on the dock."
		dep_row.add_theme_color_override("font_color", UIStyles.COLORS.success)
	else:
		dep_row.text = "Next cast-off: Day %d, %.2f h into the day (%.1f h from now)." % [day + int(dep.get("day_offset", 0)), float(dep.get("hour", 0.0)), float(dep.get("in_h", 0.0))]
		dep_row.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	_sail_rows.add_child(dep_row)
	var law_row := Label.new()
	law_row.text = "The first ride always takes the water. After that, the wake remembers you."
	law_row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	law_row.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	_sail_rows.add_child(law_row)


## The scheduled ferries: every vehicle that declares a route + a
## per-day count (data/vehicles scan -- the almanac is a chart, not a
## service; it reads the declarations directly, like the moon page
## reads the worlds).
func _sail_ferries() -> Array:
	var out: Array = []
	var dir := DirAccess.open("res://data/vehicles")
	if dir == null:
		return out
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			var v = load("res://data/vehicles/" + fname)
			if v != null and "ferries_per_day" in v and int(v.ferries_per_day) > 0 \
					and v.route_gateways != null and v.route_gateways.size() >= 2:
				out.append(_ferry_row(v))
		fname = dir.get_next()
	return out


func _ferry_row(v) -> Dictionary:
	return {
		"name": str(v.display_name),
		"from": str(v.route_gateways[0]).trim_prefix("waypoint_").replace("_", " "),
		"to": str(v.route_gateways[v.route_gateways.size() - 1]).trim_prefix("waypoint_").replace("_", " "),
		"per_day": int(v.ferries_per_day),
		"cross_h": float(v.crossing_hours),
		"dep": _next_departure(int(v.ferries_per_day), float(v.first_departure_hour)),
	}


## The next cast-off for a closed-form schedule: per-day departures
## spread evenly across the sky day, first at first_h. Day boundary
## is the Concord epoch day -- the same day index the sky rows show
## (one clock: calendar, moon, and ferry). Returns {hour, day_offset,
## in_h, departing}.
func _next_departure(per_day: int, first_h: float) -> Dictionary:
	var epoch: float = _moon_epoch_days()
	var hour_now: float = fposmod(epoch, 1.0) * 24.0
	var step: float = 24.0 / float(per_day)
	var best: Dictionary = {}
	for k in per_day:
		var h: float = first_h + float(k) * step
		var d_off := 0
		while h >= 24.0:
			h -= 24.0
			d_off += 1
		var in_h := h - hour_now
		if in_h < 0.0:
			in_h += 24.0
			d_off += 1
		if best.is_empty() or in_h < float(best.get("in_h", 999.0)):
			best = {"hour": h, "day_offset": d_off, "in_h": in_h, "departing": in_h <= 0.25}
	return best


func _sign_name_for(day: int, window: int) -> String:
	if SignService == null:
		return "none"
	var s = SignService.sign_for_window(day, window)
	return str(s.display_name) if s != null else "none"


func _observer_count_for(day: int, window: int) -> int:
	if SignService == null:
		return 0
	return SignService._observer_count(day, window)
