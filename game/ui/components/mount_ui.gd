## MountUI - the rider's stable panel (R45, labs/prd-mounts.md sec 9).
##
## Mirrors BankUI's island shape (extends UIPanel; content built into
## the panel's Main in the _setup_content override the base _ready
## already calls): a list of the rider's owned mounts with
## Summon/Dismiss buttons. Mount TRUTH comes from RideService's
## ledger (the one book) -- the panel invents nothing: what is owned,
## what is active, what a button does. Every control carries text
## (the a11y layer reads buttons, never icons alone) and every player
## action rides the typed notification pipeline.
extends "res://ui/components/ui_panel.gd"

class_name MountUI

var _list: VBoxContainer
var _active_label: Label
var _empty_label: Label
var _ride_service = null  # RideService autoload (resolved before super._ready)


func _ready() -> void:
	# Resolve BEFORE super._ready(): the base chain calls
	# _setup_content(), which refreshes from the ledger.
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		_ride_service = (ml as SceneTree).root.get_node_or_null("RideService")
	if _ride_service != null:
		if not _ride_service.mount_summoned.is_connected(_on_ride_changed):
			_ride_service.mount_summoned.connect(_on_ride_changed)
		if not _ride_service.mount_dismounted.is_connected(_on_ride_changed):
			_ride_service.mount_dismounted.connect(_on_ride_changed)
	super._ready()
	set_title("Mounts")
	set_panel_size(Vector2(420, 380))


## The stable rides the same wire the body does: a summon or a dismiss
## anywhere in the session refreshes the panel live (active line and
## button labels), no reopen needed. Grants arrive through purchase --
## the buyer has the panel open, so the next refresh picks the row up.
func _on_ride_changed(_player_id: String, _mount_id: String) -> void:
	refresh()


func _setup_content() -> void:
	var panel := get_panel()
	if panel == null:
		return
	var main: VBoxContainer = panel.get_node_or_null("Main")
	if main == null:
		return
	_list = VBoxContainer.new()
	_list.name = "MountList"
	main.add_child(_list)
	_active_label = Label.new()
	_active_label.name = "ActiveMount"
	_active_label.text = "Walking"
	main.add_child(_active_label)
	_empty_label = Label.new()
	_empty_label.name = "NoMounts"
	_empty_label.text = "No mounts yet."
	main.add_child(_empty_label)
	refresh()


## Rebuild the list from the ledger. Idempotent: clear and rebuild, so
## a refresh after grant/purchase/summon never duplicates rows.
func refresh() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		child.queue_free()
	var player_id: String = _local_player_id()
	var owned: Array = _owned_mount_ids(player_id)
	if _empty_label != null:
		_empty_label.visible = owned.is_empty()
	if _active_label != null:
		_active_label.text = _active_line(player_id)
	for mount_id in owned:
		_list.add_child(_make_row(player_id, str(mount_id)))


func _make_row(player_id: String, mount_id: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Row_" + mount_id
	var mount = _mount_data(mount_id)
	var label := Label.new()
	label.text = str(mount.display_name) if mount != null else mount_id
	label.name = "Mount_" + mount_id
	row.add_child(label)
	var btn := Button.new()
	btn.text = "Summon"
	btn.name = "Summon_" + mount_id
	btn.pressed.connect(_on_summon_pressed.bind(player_id, mount_id))
	row.add_child(btn)
	return row


## One button, one meaning: summon an owned mount, or dismiss it if
## this very mount is already active (the row flips to the whistle).
## RideService announces both through the typed pipeline; the panel
## only refreshes truth.
func _on_summon_pressed(player_id: String, mount_id: String) -> void:
	if _ride_service == null:
		return
	if _ride_service.active_mount_id(player_id) == mount_id:
		_ride_service.dismiss(player_id)
	else:
		_ride_service.summon(player_id, mount_id)
	refresh()


func _active_line(player_id: String) -> String:
	if _ride_service == null:
		return "Walking"
	var mount = _ride_service.active_mount(player_id)
	if mount == null:
		return "Walking"
	return "Riding: %s" % str(mount.display_name)


## The rider's book, read-only (the wake-ledger idiom's persisted key;
## keys are mount ids -- a DictStore row is a Dictionary).
func _owned_mount_ids(player_id: String) -> Array:
	if player_id.is_empty():
		return []
	var store = load("res://adapters/persistence/dict_store.gd").new()
	var row = store.get_kv("ride_service/mounts/" + player_id, null)
	if row is Dictionary:
		return row.keys()
	return []


func _mount_data(mount_id: String):
	if DataService != null:
		return DataService.get_mount(mount_id)
	return null


func _local_player_id() -> String:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		var pm = (ml as SceneTree).root.get_node_or_null("PlayerManager")
		if pm != null and pm.has_method("get_local_player_id"):
			return str(pm.get_local_player_id())
	return ""
