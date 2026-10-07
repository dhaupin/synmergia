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
var _shop_list: VBoxContainer
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
	# The stable SELLS (R47): the vendor door needs a shop window.
	# Same truth law as the owned list -- the catalog is RideService's
	# data-truth, prices are the .tres, and a buy is the SAME typed
	# gate chain the headless probe already rode.
	var shop_hint := Label.new()
	shop_hint.name = "ShopHint"
	shop_hint.text = "The stable sells:"
	main.add_child(shop_hint)
	_shop_list = VBoxContainer.new()
	_shop_list.name = "ShopList"
	main.add_child(_shop_list)
	refresh()


## Detach immediately, free deferred: an immediate remove_child frees
## the NAME for reuse (Godot auto-renames a child whose name collides
## with a living sibling -- a queue_free'd row still owns its name, so
## a same-frame refresh burst used to rename the fresh rows to
## @HBoxContainer@N and orphan every lookup), while the deferred free
## keeps a button press that triggers refresh() emission-safe.
func _clear_container(c: Node) -> void:
	for child in c.get_children():
		c.remove_child(child)
		child.call_deferred("free")


## Rebuild the list from the ledger. Idempotent: clear and rebuild, so
## a refresh after grant/purchase/summon never duplicates rows.
func refresh() -> void:
	if _list == null:
		return
	_clear_container(_list)
	var player_id: String = _local_player_id()
	var owned: Array = _owned_mount_ids(player_id)
	if _empty_label != null:
		_empty_label.visible = owned.is_empty()
	if _active_label != null:
		_active_label.text = _active_line(player_id)
	for mount_id in owned:
		_list.add_child(_make_row(player_id, str(mount_id)))
	if _shop_list != null:
		_clear_container(_shop_list)
		for row in _shop_rows(player_id):
			_shop_list.add_child(row)


func _make_row(player_id: String, mount_id: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Row_" + mount_id
	var mount = _mount_data(mount_id)
	var label := Label.new()
	label.text = str(mount.display_name) if mount != null else mount_id
	label.name = "Mount_" + mount_id
	row.add_child(label)
	var btn := Button.new()
	# The verb IS the button: unique labels read one meaning to eyes,
	# screen readers, and agents alike (R47; the Summon_/Dismiss_ node
	# names keep the headless probe's wire contract).
	var active: bool = _ride_service != null \
		and _ride_service.active_mount_id(player_id) == mount_id
	btn.text = "Dismiss %s" % label.text if active else "Ride %s" % label.text
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


## The shop window (R47): one row per vendor-priced mount the rider
## does NOT own -- data truth from get_shop_catalog (gold and
## vendor-currency wallets alike; what the rider already owns is
## not a good). One button, one meaning: "Buy <name> (N gold)".
func _shop_rows(player_id: String) -> Array:
	var rows: Array = []
	if _ride_service == null or DataService == null:
		return rows
	var owned: Dictionary = {}
	for mid in _owned_mount_ids(player_id):
		owned[str(mid)] = true
	for entry in _ride_service.get_shop_catalog():
		var mount_id := str(entry.get("id", ""))
		if mount_id.is_empty() or owned.has(mount_id):
			continue
		var mount = _mount_data(mount_id)
		var display: String = str(mount.display_name) if mount != null else mount_id
		var currency := str(entry.get("currency", ""))
		var cur_name := "gold"
		if currency != "" and DataService.get_currency(currency) != null:
			cur_name = str(DataService.get_currency(currency).display_name)
		var row := HBoxContainer.new()
		row.name = "ShopRow_" + mount_id
		var label := Label.new()
		label.text = "%s -- %d %s" % [display, int(entry.get("price", 0)), cur_name]
		label.name = "ShopLabel_" + mount_id
		row.add_child(label)
		var btn := Button.new()
		btn.text = "Buy %s" % display
		btn.name = "Buy_" + mount_id
		btn.pressed.connect(_on_buy_pressed.bind(player_id, mount_id))
		row.add_child(btn)
		rows.append(row)
	return rows


## The buy press rides the SAME gate chain as every other door: the
## service answers {success, message}, the typed pipeline announces
## (MOUNT_ACQUIRED on success), and the panel refreshes truth. A
## refusal is spoken, never swallowed -- a short purse must say so.
func _on_buy_pressed(player_id: String, mount_id: String) -> void:
	if _ride_service == null:
		return
	var answer: Dictionary = _ride_service.purchase_mount(player_id, mount_id)
	if not bool(answer.get("success", false)):
		# The refusal is spoken, never swallowed -- a short purse must say so.
		GameLog.info("MountUI: buy refused for %s: %s" % [mount_id, str(answer.get("message", "refused"))])
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
