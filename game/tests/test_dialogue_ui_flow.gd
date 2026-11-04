## Regression test: DialogUI drives the real DialogService, including the
## Continue button on a choice-less node.
##
## Bug: _on_continue_pressed called the DEMO fallback _show_node(), which
## renders the placeholder "Hello, traveler!" and never advances the service.
## Every authored dialogue ends on a choice-less node (e.g. the blacksmith's
## closing node), so the Continue button showed placeholder text and the panel
## never closed -- the conversation dead-ended.
##
## Run: godot --headless --path . --script res://tests/test_dialogue_ui_flow.gd

extends SceneTree

func _init() -> void:
	call_deferred("_run")

var _passed: int = 0
var _failed: int = 0

func _run() -> void:
	var root_node := get_root()
	var svc = root_node.get_node_or_null("DialogService")
	if svc == null:
		_fail("DialogService autoload missing")
		_finish()
		return
	_ok("DialogService present")

	var qui_script = load("res://ui/components/dialog_ui.gd")
	if qui_script == null:
		_fail("dialog_ui.gd failed to load")
		_finish()
		return
	var ui = qui_script.new()
	root_node.add_child(ui)
	await process_frame
	await process_frame
	_ok("DialogUI built its panel (%s)" % str(ui.get_panel() != null))

	if not svc.start_dialogue("npc_blacksmith_village", "blacksmith_village_intro"):
		_fail("start_dialogue failed for blacksmith_village_intro")
		_finish()
		return
	await process_frame
	_ok("dialogue started; UI shows node 0 with %d choices" % ui._choice_buttons.get_child_count())
	if ui._choice_buttons.get_child_count() != 2:
		_fail("expected 2 choices on node 0, got %d" % ui._choice_buttons.get_child_count())

	# Walk to the choice-less closing node (node 4): 0 -> 1 -> 3 -> 4.
	svc.select_choice(0)
	await process_frame
	svc.select_choice(0)
	await process_frame
	svc.select_choice(0)
	await process_frame
	var node: Dictionary = svc.get_current_node()
	_ok("reached the choice-less closing node (choices=%d)" % (node.get("choices", []).size()))
	if not node.get("choices", []).is_empty():
		_fail("expected a choice-less node at the close")
		_finish()
		return
	if not ui._continue_btn.visible:
		_fail("Continue button not visible on a choice-less node")
	else:
		_ok("Continue button is visible on the choice-less node")

	# The real bug: pressing Continue must ADVANCE the service and end the
	# dialogue, not paint the demo placeholder.
	ui._continue_btn.pressed.emit()
	await process_frame
	await process_frame
	var ended: bool = svc.get_current_node().is_empty()
	_ok("Continue advanced + ended the dialogue (current=%s)" % str(svc.get_current_node()))
	if not ended:
		_fail("Continue did not advance the service (demo fallback still wired)")
	# The placeholder text must never have replaced the real node text.
	var placeholder: bool = ui._speaker_label != null and str(ui._speaker_label.text) == "NPC"
	if placeholder:
		_fail("Continue painted the demo placeholder instead of advancing")
	else:
		_ok("Continue did not paint the demo placeholder")

	ui.queue_free()
	_finish()

func _ok(msg: String) -> void:
	_passed += 1
	print("  [OK] ", msg)

func _fail(msg: String) -> void:
	_failed += 1
	print("  [FAIL] ", msg)

func _finish() -> void:
	print("--- DIALOGUE UI FLOW: %d passed, %d failed ---" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
