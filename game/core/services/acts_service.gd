## ActsService -- the Concord Chronicle (labs/prd-psy.md section 5)
##
## The consumer of AncientDoor.door_opened: when the tribe's sky code
## opens the shard's Ancient door, the Chronicle records the next
## chapter of every act whose milestone is met. Acts/chapters teach, as
## historical RECORD of the past world, the lessons religions teach
## anyway (mortality, repair, gratitude, trust) -- they are read, not
## worshipped, and no chapter is faith language (section 4 voice law).
##
## Two gates, both tribal:
## 1. Milestone gate: a chapter's gate_day is a day whose Ancient
##    unlock the tribe must have earned (SignService.is_ancient_unlocked).
##    A chapter with gate_day = -1 advances on the NEXT door open after
##    the previous chapter recorded.
## 2. Door gate: chapters record only on the door's door_opened signal.
##    The door IS the milestone -- reading the sky, not the door, is
##    what the lesson attaches to.
##
## The door re-seals at every dawn (for_day_offset rolls the day it
## names), so door_opened is a recurring daily event -- the Chronicle
## fills one step per solved day, forever.
##
## Persistence mirrors SignService: DictStore KV, loaded in
## ensure_initialized, written on change. Autoload ORDER: after
## SignService (reads is_ancient_unlocked). Door wiring: group scan
## after the first frame + a 2s poll (the world scene attaches after
## the menu, so a one-shot scan would miss it -- the _ready
## null-instance trap in slow motion).
extends Node

const DictStore = preload("res://adapters/persistence/dict_store.gd")
const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind
const KillRewards = preload("res://core/services/kill_rewards.gd")

## Fired when chapters are recorded by a door open (per act_id).
signal chapter_recorded(act_id: String, chapter_index: int, day_index: int)
## Fired when a mystery is solved (mystery_id, player_id).
signal mystery_solved(mystery_id: String, player_id: String)

const _KV := "acts:"

var _acts: Dictionary = {}
var _mysteries: Dictionary = {}
## act_id -> {chapter_index(int) -> day_index(int)} recorded ledgers.
var _recorded: Dictionary = {}
## act_id -> next fill-in chapter index (gate_day = -1 sequencing).
var _next_fill: Dictionary = {}
## mystery_id -> {player_id -> true} solved ledgers.
var _solved: Dictionary = {}
## act_id -> next fill-in chapter index cache (see _rebuild_next_fill).
var _initialized: bool = false


func _ready() -> void:
	ensure_initialized()


## Idempotent boot: safe from _ready AND from script-mode tests that
## resolve the autoload before its _ready has run.
func ensure_initialized() -> void:
	if _initialized:
		return
	_initialized = true
	_load_acts()
	_load_mysteries()
	_load_state()
	_rebuild_next_fill()
	_connect_door_signal()
	GameLog.info("ActsService: Chronicle active (%d acts, %d chapters recorded)" % [
		_acts.size(), _count_recorded()])


## Wire the AncientDoor group's door_opened signal. Doors may exist at
## boot (test probes) or load later (the world scene comes up after the
## menu), so a one-shot scan would miss them -- poll the tiny group on
## a short timer AND scan once after the first frame. Connecting is
## guarded, so repeated scans are free.
func _connect_door_signal() -> void:
	if not is_inside_tree():
		# Script-mode edge: ensure_initialized can run before the autoload
		# joins the tree. Doors (added later by the world scene or a test
		# probe) wire through _scan_doors, which those callers invoke.
		return
	await get_tree().process_frame
	_scan_doors()
	var timer := Timer.new()
	timer.wait_time = 2.0
	timer.autostart = true
	timer.timeout.connect(_scan_doors)
	add_child(timer)
	GameLog.info("ActsService: listening for AncientDoor.door_opened")


## Connect every group door that is not wired yet.
func _scan_doors() -> void:
	if not is_inside_tree():
		return
	for door in get_tree().get_nodes_in_group("ancient_doors"):
		if door == null or not is_instance_valid(door):
			continue
		if not door.has_signal("door_opened"):
			continue
		if not door.door_opened.is_connected(_on_door_opened):
			door.door_opened.connect(_on_door_opened)


## THE CONSUMER: every Ancient door open records the Chronicle's next
## eligible chapters. Idempotent -- chapters already recorded are
## skipped, so repeated opens or multiple doors never double-write.
func _on_door_opened(day_index: int) -> void:
	var recorded_any := false
	for act_id in _acts.keys():
		var act = _acts[act_id]
		if act == null or not ("chapters" in act):
			continue
		var rid := str(act_id)
		var ledger: Dictionary = _recorded.get(rid, {})
		var next_fill: int = int(_next_fill.get(rid, -1))
		for d in act.chapters:
			if not (d is Dictionary):
				continue
			var idx := int(d.get("index", 0))
			if ledger.has(idx):
				continue
			var gate := int(d.get("gate_day", -1))
			if gate >= 0:
				# Milestone gate: that day's Ancient unlock must be earned.
				if SignService == null or not SignService.is_ancient_unlocked(gate):
					continue
			else:
				# Fill-in gate: advances on the next door open after the
				# previous chapter. The open day must fall in the act's
				# range (advance_from_day) and the pending chapter must
				# be this one.
				if next_fill != idx:
					continue
				if int(act.advance_from_day) > day_index:
					continue
			ledger[idx] = day_index
			recorded_any = true
			_announce_chapter(rid, act, d, day_index)
			chapter_recorded.emit(rid, idx, day_index)
		if recorded_any:
			_recorded[rid] = ledger
			_next_fill[rid] = _find_next_fill(act, ledger)
	if recorded_any:
		_save_recorded()
		GameLog.info("ActsService: door opened for day %d -- Chronicle advanced" % day_index)


## The next unrecorded chapter index with gate_day = -1, or -1 when the
## act has no pending fill-in chapter.
func _find_next_fill(act, ledger: Dictionary) -> int:
	for d in act.chapters:
		if not (d is Dictionary):
			continue
		if int(d.get("gate_day", -1)) != -1:
			continue
		var idx := int(d.get("index", 0))
		if not ledger.has(idx):
			return idx
	return -1


func _rebuild_next_fill() -> void:
	for act_id in _acts.keys():
		var act = _acts[act_id]
		if act == null or not ("chapters" in act):
			continue
		var ledger: Dictionary = _recorded.get(str(act_id), {})
		_next_fill[str(act_id)] = _find_next_fill(act, ledger)


func _announce_chapter(act_id: String, act, chapter: Dictionary, day: int) -> void:
	if NotificationService == null:
		return
	var idx := int(chapter.get("index", 0))
	var source := str(chapter.get("source_name", ""))
	var text := str(chapter.get("record_text", ""))
	NotificationService.notify(
		NotifKind.CUSTOM,
		"The Chronicle records, Act '%s', chapter %d -- %s." % [str(act.display_name), idx, source],
		"ActsService",
		"acts:chapter:%s:%d:%d" % [act_id, idx, day],
		{"act_id": act_id, "chapter_index": idx, "day_index": day, "record_text": text}
	)


## ------------------------------------------------------------------
## Read API (almanac, lore panels, tests)
## ------------------------------------------------------------------

func get_act(id: String):
	return _acts.get(id)


func get_acts() -> Dictionary:
	return _acts


func get_recorded_chapters(act_id: String) -> Dictionary:
	return _recorded.get(act_id, {}).duplicate()


func is_chapter_recorded(act_id: String, chapter_index: int) -> bool:
	return _recorded.get(act_id, {}).has(chapter_index)


## Typed chapter views for an act, with recorded flags applied
## (delegates to the schema's from-dict builder).
func get_act_chapter_views(act_id: String) -> Array:
	var act = _acts.get(act_id)
	if act == null or not act.has_method("get_chapter_profiles"):
		return []
	var ledger: Dictionary = _recorded.get(act_id, {})
	return act.get_chapter_profiles(ledger)


## ------------------------------------------------------------------
## Chronicle mysteries (data/mysteries/, prd-psy.md section 5)
## ------------------------------------------------------------------

func get_mystery(id: String):
	return _mysteries.get(id)


func get_mysteries() -> Dictionary:
	return _mysteries


## Is the mystery attemptable? Its gate chapter must be recorded.
func is_mystery_unlocked(mystery_id: String) -> bool:
	var m = _mysteries.get(mystery_id)
	if m == null:
		return false
	return is_chapter_recorded(str(m.gate_act_id), int(m.gate_chapter_index))


func is_mystery_solved(mystery_id: String, player_id: String) -> bool:
	return _solved.get(mystery_id, {}).has(player_id)


func get_mystery_solvers(mystery_id: String) -> Array:
	return (_solved.get(mystery_id, {}) as Dictionary).keys()


## THE CHECK: normalize the attempt and compare to the DERIVED answer
## (the sky's own record -- nothing answer-shaped is stored). Returns
## {ok, reason, solved_now}: reasons are "unknown", "locked",
## "already", "wrong", or "" on success. Rewards on solve: the title
## (TitleService.unlock) + a little XP (KillRewards, duck-typed).
func attempt_mystery(mystery_id: String, player_id: String, attempt: String) -> Dictionary:
	var m = _mysteries.get(mystery_id)
	if m == null:
		return {"ok": false, "reason": "unknown"}
	var pid := str(player_id)
	if not is_mystery_unlocked(mystery_id):
		return {"ok": false, "reason": "locked"}
	if is_mystery_solved(mystery_id, pid):
		return {"ok": false, "reason": "already"}
	var correct := false
	match int(m.answer_kind):
		0:  # MysteryData.AnswerKind.SKY_CODE -- derived from the day.
			var svc = _resolve_service("SignService")
			if svc != null:
				var code: String = svc.get_ancient_code(int(m.answer_day))
				correct = str(attempt).to_upper().strip_edges() == str(m.expected_answer(code))
		1:  # FORECAST family: observation mysteries answer from catalogs.
			correct = _check_forecast_answer(m, attempt)
	if not correct:
		return {"ok": false, "reason": "wrong"}
	# Solved: ledger, rewards, one toast.
	var ledger: Dictionary = _solved.get(mystery_id, {})
	ledger[pid] = true
	_solved[mystery_id] = ledger
	_save_solved()
	_apply_mystery_rewards(m, pid)
	mystery_solved.emit(mystery_id, pid)
	return {"ok": true, "reason": "", "solved_now": true}


## Observation-mystery answers (answer_kind FORECAST): each mystery id
## maps to a derived-from-data check. The tally counts the sign
## catalog; future observation mysteries add cases here.
func _check_forecast_answer(m, attempt: String) -> bool:
	var guess := str(attempt).to_upper().strip_edges()
	match str(m.id):
		"mystery_the_watcher_tally":
			var svc = _resolve_service("SignService")
			if svc == null:
				return false
			return guess == str(svc._signs.size())
		_:
			return false


## Rewards: the NAME (title) and a little XP. Duck-typed recipient --
## the local player node when registered, else a plain xp mirror in
## script-mode tests. NOTE: TitleService.unlock is STATIC -- has_method
## does not see statics, so guard on the instance being present.
func _apply_mystery_rewards(m, player_id: String) -> void:
	var ts = _resolve_service("TitleService")
	if ts != null and str(m.reward_title_id) != "":
		ts.unlock(player_id, str(m.reward_title_id))
	var recipient = null
	var es = _resolve_service("EntityService")
	if es != null and es.has_method("get_entity"):
		recipient = es.get_entity(player_id)
	if recipient == null:
		recipient = {"xp": 0}  # script-mode / offline mirror
	KillRewards._grant_xp(recipient, int(m.reward_xp))
	var nsvc = _resolve_service("NotificationService")
	if nsvc != null:
		nsvc.notify(
			NotifKind.ACHIEVEMENT_UNLOCKED,
			"Mystery solved: %s. The Chronicle remembers." % str(m.display_name),
			"ActsService",
			"mystery:%s:%s" % [str(m.id), player_id],
			{"mystery_id": str(m.id), "player_id": player_id},
			player_id
		)


## Late autoload resolution (the CombatMath static pattern) -- this
## file is preloaded by script-mode tests where bare identifiers do
## not exist.
func _resolve_service(svc_name: String) -> Node:
	var ml := Engine.get_main_loop()
	if ml == null or not (ml is SceneTree):
		return null
	return (ml as SceneTree).root.get_node_or_null(svc_name)


func _count_recorded() -> int:
	var n := 0
	for rid in _recorded.keys():
		n += (_recorded[rid] as Dictionary).size()
	return n


## ------------------------------------------------------------------
## Persistence (DictStore KV, the SignService pattern)
## ------------------------------------------------------------------

func _load_acts() -> void:
	if DataService == null:
		GameLog.warn("ActsService: DataService missing -- no acts")
		return
	if not DataService._loaded:
		DataService.load_all_data()
	_acts = DataService.get_acts()


func _load_mysteries() -> void:
	if DataService == null:
		return
	_mysteries = DataService.get_mysteries()


func _load_state() -> void:
	var store := DictStore.new()
	var keys: Array = store.all_keys()
	for k in keys:
		var ks := str(k)
		if not ks.begins_with(_KV):
			continue
		var val = store.get_kv(ks)
		if ks == _KV + "recorded" and val is Dictionary:
			_recorded = val.duplicate()
		elif ks == _KV + "solved" and val is Dictionary:
			_solved = val.duplicate()
	_normalize_ledgers()
	_normalize_solved()


## DictStore round-trips through JSON, which stringifies dictionary
## keys: after a reboot the ledger keys arrive as "1", not 1. Every
## lookup here indexes with ints, so normalize on load.
func _normalize_ledgers() -> void:
	var clean: Dictionary = {}
	for act_id in _recorded.keys():
		var ledger: Dictionary = _recorded[act_id]
		if not (ledger is Dictionary):
			continue
		var clean_ledger: Dictionary = {}
		for idx in ledger.keys():
			clean_ledger[int(idx)] = int(ledger[idx])
		clean[str(act_id)] = clean_ledger
	_recorded = clean


## Same JSON-key lesson for the mystery solved ledger: player_id keys
## are strings already, but normalize defensively anyway.
func _normalize_solved() -> void:
	var clean: Dictionary = {}
	for mid in _solved.keys():
		var players: Dictionary = _solved[mid]
		if not (players is Dictionary):
			continue
		var clean_players: Dictionary = {}
		for pid in players.keys():
			clean_players[str(pid)] = true
		clean[str(mid)] = clean_players
	_solved = clean


func _save_recorded() -> void:
	var store := DictStore.new()
	store.set_kv(_KV + "recorded", _recorded.duplicate())


func _save_solved() -> void:
	var store := DictStore.new()
	store.set_kv(_KV + "solved", _solved.duplicate())
