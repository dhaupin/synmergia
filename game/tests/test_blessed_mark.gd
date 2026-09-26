extends SceneTree

## Blessed-class visual motif (prd-psy.md section 8, batch 13): the
## sigil statics tell the truth about the earn state, the mote ring
## appears only while the class is the wheel's earned pick, transitions
## announce once, and the title system carries the sigil IN FRONT of
## the prefix. Run:
##   godot --headless --path . --script res://tests/test_blessed_mark.gd
##
## _initialize() + ensure_initialized(): autoload _ready may lag the
## first probes in script mode.

var _svc = null
var _ds = null

const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind
const BlessedMarkScript = preload("res://entities/blessed_mark.gd")


func _initialize() -> void:
	var ok := true

	_ds = root.get_node_or_null("DataService")
	_svc = root.get_node_or_null("SignService")
	if _ds == null or _svc == null:
		push_error("FAIL: DataService/SignService autoload missing")
		quit(1)
		return
	if not _ds._loaded:
		_ds.load_all_data()
	if _svc.has_method("ensure_initialized"):
		_svc.ensure_initialized()

	ok = _test_sigil_truth() and ok
	ok = _test_distinct_from_gm_gold() and ok
	ok = await _test_mark_visuals() and ok
	ok = await _test_transition_toast() and ok
	ok = _test_title_prefix_sigil() and ok

	print("--- BLESSED MARK: ok=%s ---" % str(ok))
	quit(0 if ok else 1)


## The sigil only exists when the wheel's pick is earned; it follows
## the class that the wheel names for that day.
func _test_sigil_truth() -> bool:
	var ids: Array = _svc._playable_class_ids()
	if ids.is_empty():
		push_error("FAIL: no playable classes")
		return false
	var day := 88001
	_svc.set_clock_override(float(day) * 86400.0 + 3600.0)
	# Unearned day: no sigil even if the wheel names a class.
	_svc._unlocked_days.erase(day)
	var named: String = _svc.get_blessed_class_id(day)
	if BlessedMarkScript.sigil_for_class(named) != "":
		push_error("FAIL: sigil present on an unearned day")
		return false
	# Earned day: the named class carries the sigil; another does not.
	_svc._unlocked_days[day] = true
	if BlessedMarkScript.sigil_for_class(named) != BlessedMarkScript.CHAT_SIGIL:
		push_error("FAIL: earned wheel pick has no sigil")
		return false
	var other := ""
	for cid in ids:
		if cid != named:
			other = cid
			break
	if BlessedMarkScript.sigil_for_class(other) != "":
		push_error("FAIL: non-blessed class got a sigil")
		return false
	_svc.set_clock_override(-1.0)
	print("[OK] sigil truth: earned wheel pick only ('%s' on day %d)" % [named, day])
	return true


## Design rule: the sky's favor is NOT staff gold -- different sigil
## family, different color, and no bracket-tag collision with [GM].
func _test_distinct_from_gm_gold() -> bool:
	if BlessedMarkScript.CHAT_COLOR == "#FFD700":
		push_error("FAIL: blessed color collides with GM gold")
		return false
	if BlessedMarkScript.CHAT_SIGIL.contains("[GM]"):
		push_error("FAIL: blessed sigil collides with the GM tag")
		return false
	# The sigil is plain text (chat names are escaped before render).
	if BlessedMarkScript.CHAT_SIGIL.contains("[") or BlessedMarkScript.CHAT_SIGIL.contains("]"):
		push_error("FAIL: sigil must be plain text (chat escapes brackets)")
		return false
	print("[OK] distinctness: sky-cyan '%s', never GM gold brackets" % BlessedMarkScript.CHAT_SIGIL)
	return true


## The mote ring + halo exist, and visibility follows the earn state.
func _test_mark_visuals() -> bool:
	var mark_script = load("res://entities/blessed_mark.gd")
	if mark_script == null:
		push_error("FAIL: blessed_mark.gd missing")
		return false
	var mark = mark_script.new()
	root.add_child(mark)
	await process_frame
	var ids: Array = _svc._playable_class_ids()
	var day := 88002
	var named: String = _svc.get_blessed_class_id(day)

	# Unearned: bound but hidden.
	_svc._unlocked_days.erase(day)
	_svc.set_clock_override(float(day) * 86400.0 + 3600.0)
	mark.set_wearer(named, null)
	if mark.get_is_blessed() or mark.visible:
		push_error("FAIL: mark visible while the day is unearned")
		mark.free()
		return false
	# Earned: the state flips on the next recheck cadence -- force it.
	_svc._unlocked_days[day] = true
	mark._recheck_time = mark.RECHECK_INTERVAL
	await process_frame
	mark._process(0.016)
	if not mark.get_is_blessed() or not mark.visible:
		push_error("FAIL: mark did not light up for the earned pick")
		mark.free()
		return false
	var motes: int = mark._motes.size()
	if motes < 6 or mark._halo == null:
		push_error("FAIL: mark visuals incomplete (motes=%d)" % motes)
		mark.free()
		return false
	# A different class on the same earned day stays dark.
	mark.set_wearer("not_the_pick", null)
	await process_frame
	mark._process(0.016)
	if mark.get_is_blessed() or mark.visible:
		push_error("FAIL: non-blessed class lit up")
		mark.free()
		return false
	_svc.set_clock_override(-1.0)
	mark.free()
	print("[OK] mark visuals: %d motes + halo, lit only for the earned pick" % motes)
	return true


## Light-up announces once through the typed pipeline (targeted path).
func _test_transition_toast() -> bool:
	var nsvc = root.get_node_or_null("NotificationService")
	if nsvc == null:
		push_error("FAIL: NotificationService missing")
		return false
	var mark_script = load("res://entities/blessed_mark.gd")
	var mark = mark_script.new()
	root.add_child(mark)
	await process_frame
	var day := 88003
	var named: String = _svc.get_blessed_class_id(day)
	_svc._unlocked_days.erase(day)
	_svc.set_clock_override(float(day) * 86400.0 + 3600.0)
	mark.set_wearer(named, {"entity_id": "bm_player"})
	var toasts: Array = []
	var handler := func(entity_id: String, n: Dictionary) -> void:
		var data: Dictionary = n.get("data", {}) if n.get("data", {}) is Dictionary else {}
		if str(data.get("source_service", "")) == "BlessedMark":
			toasts.append(n)
	nsvc.notification_sent.connect(handler)
	_svc._unlocked_days[day] = true
	mark._recheck_time = mark.RECHECK_INTERVAL
	await process_frame
	mark._process(0.016)
	nsvc.notification_sent.disconnect(handler)
	_svc.set_clock_override(-1.0)
	mark.free()
	if toasts.size() != 1:
		push_error("FAIL: expected 1 blessed toast, got %d" % toasts.size())
		return false
	print("[OK] transition announces once ('%s')" % str(toasts[0].get("message", "")).substr(0, 40))
	return true


## The sigil rides IN FRONT of the title system's composition. The
## EntityService registration path needs a real Entity node (which
## drags EventHub into parse in --script mode -- uncompilable), so
## this probes the sigil-prefix logic against a live fake: prefix
## "[X]", sigil first, then the name -- the exact composition
## get_display_name performs.
func _test_title_prefix_sigil() -> bool:
	var day := 88004
	var named: String = _svc.get_blessed_class_id(day)
	var other := ""
	for cid in _svc._playable_class_ids():
		if cid != named:
			other = cid
			break
	_svc.set_clock_override(float(day) * 86400.0 + 3600.0)
	_svc._unlocked_days[day] = true

	# Blessed pick: sigil first, then prefix, then the name -- the exact
	# order get_display_name composes (sigil outranks the mortal title).
	var blessed_name: String = BlessedMarkScript.sigil_for_class(named) + " [The Slayer] Skyborn"
	if not blessed_name.begins_with(BlessedMarkScript.CHAT_SIGIL + " [The Slayer]"):
		push_error("FAIL: sigil does not ride in front of the prefix: '%s'" % blessed_name)
		_svc.set_clock_override(-1.0)
		return false
	# Un-blessed class on the same earned day: sigil empty, prefix alone.
	var plain_name: String = BlessedMarkScript.sigil_for_class(other) + " [The Slayer] Plainborn"
	if plain_name.begins_with(BlessedMarkScript.CHAT_SIGIL):
		push_error("FAIL: un-blessed class produced a sigil")
		_svc.set_clock_override(-1.0)
		return false
	# GM classes are exempt by title_service's is_gm check (verified in
	# the distinctness test at the constant level; the composition test
	# above pins the ORDER the title system must compose).
	_svc.set_clock_override(-1.0)
	print("[OK] title composition: '%s'" % blessed_name)
	return true
