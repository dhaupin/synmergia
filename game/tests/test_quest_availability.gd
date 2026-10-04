## Regression test: quest availability (QuestService.get_available_quests /
## _get_available_quest_ids).
##
## Round 20 fixed two live defects here:
##  1. DataService.get_all_quests() returns the VALUES (Array[QuestData]),
##     but the code indexed the array BY the value (`all_quests[quest_id]`),
##     an invalid index that aborted the function.
##  2. `quest.get("min_level", 1)` used Resource.get's default argument,
##     which 4.7.2 removed -> runtime "Expected 1 argument(s)".
##
## The contract these functions must honor: iterate the values, key by the
## resource's own `id`, and read exports directly. This test fails on the
## old code (the call aborts and returns null / drops the entry) and passes
## on the fixed code.
##
## Run: godot --headless --path . --script res://tests/test_quest_availability.gd

extends SceneTree

## Preloaded type (a variable cannot be used as a `is` type in GDScript).
const QuestDataScript = preload("res://core/schemas/quest_data.gd")

var _passed: int = 0
var _failed: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var root_node := get_root()
	var qs = root_node.get_node_or_null("QuestService")
	var ds = root_node.get_node_or_null("DataService")
	if qs == null:
		_fail("QuestService autoload missing")
		_finish()
		return
	if ds == null:
		_fail("DataService autoload missing")
		_finish()
		return
	_ok("QuestService + DataService present")

	var all_quests: Array = ds.get_all_quests()
	if all_quests.is_empty():
		_fail("no quests loaded from data/quests")
		_finish()
		return
	_ok("data/quests loaded (%d quests)" % all_quests.size())

	# Locate a level-1 quest and a level-gated quest from the real catalog
	# so the test does not hardcode content.
	var low = null
	var high = null
	for q in all_quests:
		if not (q is QuestDataScript):
			continue
		if int(q.min_level) <= 1 and low == null:
			low = q
		elif int(q.min_level) > 1 and high == null:
			high = q
	if low == null:
		_fail("no level-1 quest found to exercise availability")
		_finish()
		return

	var pid := "quest_avail_tester"
	var ids = qs._get_available_quest_ids(pid)
	if not (ids is Array):
		_fail("_get_available_quest_ids did not return an Array (call aborted)")
		_finish()
		return
	_ok("_get_available_quest_ids returned %d ids" % ids.size())

	# Every returned id must be a String that resolves to a real QuestData.
	# The old value-as-key bug appended QuestData objects here instead.
	var all_ids_ok := true
	for id in ids:
		if not (id is String) or ds.get_quest(id) == null:
			all_ids_ok = false
			_fail("returned id is not a resolvable String: %s" % str(id))
			break
	if all_ids_ok:
		_ok("every available id is a String resolving through DataService.get_quest")

	if ids.has(str(low.id)):
		_ok("level-1 quest '%s' is available to a level-1 player" % str(low.id))
	else:
		_fail("level-1 quest '%s' missing from availability" % str(low.id))
	if high != null:
		if not ids.has(str(high.id)):
			_ok("gated quest '%s' (min_level %d) excluded for a level-1 player" % [str(high.id), int(high.min_level)])
		else:
			_fail("gated quest '%s' wrongly available to a level-1 player" % str(high.id))

	# The dict form must carry id/name/description/min_level with the right
	# shapes (the old Resource.get path errored before the dict was built).
	var available = qs.get_available_quests(pid)
	if not (available is Array) or available.is_empty():
		_fail("get_available_quests returned nothing")
		_finish()
		return
	var entry_found := false
	for entry in available:
		if not (entry is Dictionary):
			_fail("get_available_quests entry is not a Dictionary")
			break
		if entry.get("id", null) == str(low.id):
			entry_found = true
			var fields_ok: bool = entry.get("name", "") is String \
				and entry.get("description", "") is String \
				and entry.get("min_level", null) is int \
				and str(entry.get("id")) == str(low.id)
			if fields_ok:
				_ok("dict form carries String id/name/description + int min_level")
			else:
				_fail("dict form has wrong field shapes: %s" % str(entry))
	if not entry_found:
		_fail("level-1 quest '%s' missing from get_available_quests" % str(low.id))

	# The live UI consumer: QuestUI.refresh_quest_list iterates the three
	# tabs' results and feeds each element to a String-typed button
	# builder. The AVAILABLE tab yields Dictionaries, so the UI must
	# normalize to an id -- passing one straight through is a runtime
	# "Cannot convert Dictionary to String" error that leaves the list
	# empty. Assert the tab actually renders buttons.
	var pm = root_node.get_node_or_null("PlayerManager")
	if pm == null:
		_fail("PlayerManager autoload missing (cannot exercise QuestUI)")
		_finish()
		return
	qs._player_quests[pid] = {}
	var fake_player = load("res://core/entities/entity.gd").new()
	fake_player.entity_id = pid
	pm.local_player = fake_player
	# quest_ui.gd references autoload globals, so load() it at RUNTIME
	# (a parse-time preload cannot resolve QuestService in --script mode).
	var qui_script = load("res://ui/components/quest_ui.gd")
	if qui_script == null:
		_fail("quest_ui.gd failed to load")
		_finish()
		return
	var qui = qui_script.new()
	root_node.add_child(qui)
	await process_frame
	qui._current_tab = qui_script.Tab.AVAILABLE
	qui.refresh_quest_list()
	var buttons := 0
	for child in qui._quest_list.get_children():
		if child is Button:
			buttons += 1
	if buttons > 0:
		_ok("QuestUI AVAILABLE tab rendered %d quest buttons" % buttons)
	else:
		_fail("QuestUI AVAILABLE tab rendered no buttons (dict->id normalization broken)")
	qui.queue_free()

	_finish()

func _ok(msg: String) -> void:
	_passed += 1
	print("  [OK] ", msg)

func _fail(msg: String) -> void:
	_failed += 1
	print("  [FAIL] ", msg)

func _finish() -> void:
	print("--- QUEST AVAILABILITY: %d passed, %d failed ---" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
