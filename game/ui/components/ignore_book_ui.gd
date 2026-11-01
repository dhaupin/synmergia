## IgnoreBookUI - the ignore-book consumer (MenuManager panel)
## The chat moderation surface. '/ignore' existed as a bare command
## with ZERO persistent storage and ZERO listening UI (the list
## evaporated every reboot, and the typed command reported "Unknown
## command" because the chat UI's local star-match never passed it
## on). This round the loop is live: the panel reads and writes
## ChatService.ignore_player/unignore_player, the persisted list
## survives reboots (KV), and both chat surfaces drop blocked
## senders' lines at display time. channel_settings_changed stays
## contract-surface (its per-channel semantics needs a channel-mute
## feature this panel does not fake).
##
## Shell law: builds inside UIPanel's standard "Panel/Main" content
## box with an idempotent synchronous build (the ContainerUI lesson).

extends "res://ui/components/ui_panel.gd"

class_name IgnoreBookUI

signal book_changed()

## Build-once content refs (inside the base Panel/Main shell).
var _title_label: Label
var _rows_box: VBoxContainer
var _name_input: LineEdit
var _hint_label: Label

func _setup_content() -> void:
	pass

func _ensure_content() -> void:
	if _rows_box != null:
		return
	if not has_node("Panel/Main"):
		_setup_base_panel()
	var main := get_node("Panel/Main") as VBoxContainer
	if main.get_node_or_null("IgnoreRows") == null:
		_build_ui(main)
	else:
		_title_label = main.get_node_or_null("Title") as Label
		_rows_box = main.get_node_or_null("IgnoreRows") as VBoxContainer
		_name_input = main.get_node_or_null("AddRow/NameInput") as LineEdit
		_hint_label = main.get_node_or_null("Hint") as Label

func _build_ui(shell: VBoxContainer) -> void:
	_title_label = Label.new()
	_title_label.name = "Title"
	_title_label.text = "Ignore Book"
	shell.add_child(_title_label)

	_rows_box = VBoxContainer.new()
	_rows_box.name = "IgnoreRows"
	shell.add_child(_rows_box)

	var add_row := HBoxContainer.new()
	add_row.name = "AddRow"
	shell.add_child(add_row)

	_name_input = LineEdit.new()
	_name_input.name = "NameInput"
	_name_input.placeholder_text = "Player name..."
	add_row.add_child(_name_input)

	var add_btn := Button.new()
	add_btn.name = "AddButton"
	add_btn.text = "Ignore"
	add_btn.pressed.connect(_on_add_pressed)
	add_row.add_child(add_btn)

	_hint_label = Label.new()
	_hint_label.name = "Hint"
	_hint_label.text = "Ignored players' chat lines stay hidden. /unignore <name> works in chat too."
	add_row.add_child(_hint_label)

func _on_open() -> void:
	_ensure_content()
	_refresh()

func is_showing() -> bool:
	return visible

## Is this panel handling that name right now (receipt convenience)?
func shows_entry(target: String) -> bool:
	if _rows_box == null:
		return false
	for child in _rows_box.get_children():
		if child is Label and str(child.name) == "RowName" and str(child.text) == target:
			return true
		if child is HBoxContainer:
			for entry in child.get_children():
				if entry is Label and str(entry.name) == "RowName" and str(entry.text) == target:
					return true
	return false

func _refresh() -> void:
	if _rows_box == null:
		return
	for child in _rows_box.get_children():
		child.queue_free()

	# IMPORTANT: queue_free is deferred; freed-on-dequeue children
	# linger for this frame, so new rows pair with a fresh wrapper
	# (the receipt reads truth through rows, not child counts).
	var ignored: Array = _chat_ignored_list()
	if ignored.is_empty():
		var empty := Label.new()
		empty.name = "EmptyLabel"
		empty.text = "(not ignoring anyone)"
		_rows_box.add_child(empty)
		return
	for target in ignored:
		_add_row(str(target))

func _add_row(target: String) -> void:
	var row := HBoxContainer.new()
	row.name = "Row_%s" % target
	_rows_box.add_child(row)

	var name_label := Label.new()
	name_label.name = "RowName"
	name_label.text = target
	row.add_child(name_label)

	var unignore_btn := Button.new()
	unignore_btn.name = "RowButton"
	unignore_btn.text = "Unignore"
	unignore_btn.pressed.connect(_on_unignore_pressed.bind(target))
	row.add_child(unignore_btn)

func _chat_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("ChatService")) if tree and tree.root else null

func _local_player_id() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	var mgr: Node = tree.root.get_node_or_null(NodePath("PlayerManager")) if tree and tree.root else null
	if mgr == null:
		return ""
	var lp: Variant = mgr.get("local_player")
	if lp != null and is_instance_valid(lp):
		return str(lp.get("entity_id"))
	if mgr.has_method("get_local_player_id"):
		return str(mgr.call("get_local_player_id"))
	return ""

func _chat_ignored_list() -> Array:
	var svc := _chat_svc()
	if svc == null or not svc.has_method("get_ignored_players"):
		return []
	return svc.get_ignored_players(_local_player_id())

func _on_add_pressed() -> void:
	var svc := _chat_svc()
	if svc == null or not svc.has_method("ignore_player"):
		return
	var target := str(_name_input.text).strip_edges()
	if target.is_empty():
		return
	_name_input.clear()
	var result: Dictionary = svc.ignore_player(_local_player_id(), target)
	_refresh()
	book_changed.emit()
	# The service's own notify pipeline answers the common failures
	# (self-ignore, duplicates); the command half mirrors them.

func _on_unignore_pressed(target: String) -> void:
	var svc := _chat_svc()
	if svc == null or not svc.has_method("unignore_player"):
		return
	svc.unignore_player(_local_player_id(), target)
	_refresh()
	book_changed.emit()
