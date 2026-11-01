## ChannelSettingsUI - the channel-mute consumer (MenuManager panel)
## The incoming-lines volume knob. Every chat channel can hide its
## live lines in YOUR view only (receive-side; your own sends ride
## the normal pipeline). System stays unmuteable: it is the game's
## error and announcement voice. The panel reads and writes
## ChatService.set_channel_muted/is_channel_muted, the persisted
## settings row (chat:settings:<viewer>) survives reboots, and the
## panel re-renders on the service's own channel_settings_changed
## signal -- the signal's consumer is real, so the emit is too.
##
## Shell law: builds inside UIPanel's standard "Panel/Main" content
## box with an idempotent synchronous build (the ContainerUI lesson),
## the same shell the IgnoreBookUI rides.

extends "res://ui/components/ui_panel.gd"

class_name ChannelSettingsUI

signal settings_changed()

## Build-once content refs (inside the base Panel/Main shell).
var _title_label: Label
var _rows_box: VBoxContainer
var _hint_label: Label

## Guard against double-connections (the shell can re-_ready the
## same instance when the funnel re-opens it).
var _signals_bound: bool = false

func _setup_content() -> void:
	pass

func _ensure_content() -> void:
	if _rows_box != null:
		return
	if not has_node("Panel/Main"):
		_setup_base_panel()
	var main := get_node("Panel/Main") as VBoxContainer
	if main.get_node_or_null("ChannelRows") == null:
		_build_ui(main)
	else:
		_title_label = main.get_node_or_null("Title") as Label
		_rows_box = main.get_node_or_null("ChannelRows") as VBoxContainer
		_hint_label = main.get_node_or_null("Hint") as Label
	_bind_service_signals()

func _build_ui(shell: VBoxContainer) -> void:
	_title_label = Label.new()
	_title_label.name = "Title"
	_title_label.text = "Channel Settings"
	shell.add_child(_title_label)

	_rows_box = VBoxContainer.new()
	_rows_box.name = "ChannelRows"
	shell.add_child(_rows_box)

	_hint_label = Label.new()
	_hint_label.name = "Hint"
	_hint_label.text = "Muting hides a channel's incoming lines in your view only. /mute <channel> works in chat too."
	shell.add_child(_hint_label)

func _bind_service_signals() -> void:
	if _signals_bound:
		return
	var svc := _chat_svc()
	if svc != null and svc.has_user_signal("channel_settings_changed"):
		svc.channel_settings_changed.connect(_on_service_settings_changed)
		_signals_bound = true

## The service's own signal drives this panel's refresh -- not a
## private re-read, the exact loop the no-void law asks for.
func _on_service_settings_changed(_viewer_id: String, _channel: int) -> void:
	_refresh()
	settings_changed.emit()

func _on_open() -> void:
	_ensure_content()
	_refresh()

func is_showing() -> bool:
	return visible

## Is this panel presenting a mute row for that channel label right
## now (receipt convenience)?
func shows_channel(channel_label: String) -> bool:
	if _rows_box == null:
		return false
	for child in _rows_box.get_children():
		if child is HBoxContainer:
			for entry in child.get_children():
				if entry is Label and str(entry.name) == "RowName" and str(entry.text) == channel_label:
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
	for channel in _channel_catalog():
		_add_row(channel)

## The channels this panel offers one row each: every current chat
## channel except System, which is appended last, protected, with the
## reason on the label. The enum is the service's own truth (read
## through the instance so the panel never re-derives channel ids).
func _channel_catalog() -> Array:
	var svc := _chat_svc()
	var catalog: Array = []
	if svc == null or not svc.has_method("get_channel_name"):
		return catalog
	var ch_enum: Dictionary = svc.Channel
	for channel in ch_enum.values():
		if channel == ch_enum.SYSTEM:
			continue
		catalog.append({"channel": channel, "label": str(svc.get_channel_name(channel))})
	catalog.append({"channel": ch_enum.SYSTEM, "label": "System (always shown)"})
	return catalog

func _add_row(entry: Dictionary) -> void:
	var channel: int = entry.get("channel", 0)
	var label := str(entry.get("label", ""))
	var row := HBoxContainer.new()
	row.name = "Row_%s" % label
	_rows_box.add_child(row)

	var name_label := Label.new()
	name_label.name = "RowName"
	name_label.text = label
	row.add_child(name_label)

	var svc := _chat_svc()
	if svc == null or not svc.has_method("is_channel_muted"):
		return
	if channel == svc.Channel.SYSTEM:
		var state := Label.new()
		state.name = "RowState"
		state.text = "protected"
		row.add_child(state)
		return

	var muted: bool = svc.is_channel_muted(_local_player_id(), channel)
	var state := Label.new()
	state.name = "RowState"
	state.text = "hidden" if muted else "shown"
	row.add_child(state)

	var toggle_btn := Button.new()
	toggle_btn.name = "RowButton"
	toggle_btn.text = "Unmute" if muted else "Mute"
	toggle_btn.pressed.connect(_on_toggle_pressed.bind(channel, not muted))
	row.add_child(toggle_btn)

func _on_toggle_pressed(channel: int, muted: bool) -> void:
	var svc := _chat_svc()
	if svc == null or not svc.has_method("set_channel_muted"):
		return
	svc.set_channel_muted(_local_player_id(), channel, muted)
	_refresh()
	settings_changed.emit()

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
