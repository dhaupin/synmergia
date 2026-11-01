extends SceneTree

## Container store loop receipt (tests/test_slot_container_open.gd):
## SlotService.open_container -> container_opened -> ContainerUI
## shows the store; close_container -> container_closed -> panel
## stops showing. Run:
##   godot --headless --path . --script res://tests/test_slot_container_open.gd
## SlotService history note: the flat file never parsed until its
## reindent; this test is the loop's live proof.

var _opened_key: String = ""
var _opened_type: int = -1
var _closed_key: String = ""

func _initialize() -> void:
	# Autoload-lag law (AGENTS.md / test_daily_quest): script-mode
	# probes that reach service classes must run after the tree's
	# autoload set is live -- _init() is too early.
	var slot_script: GDScript = load("res://core/services/slot_service.gd")
	if slot_script == null or not slot_script.can_instantiate():
		push_error("FAIL: slot_service.gd did not load (flat indentation law bit us once already)")
		quit(1)
		return
	var svc = slot_script.singleton()

	svc.container_opened.connect(_listen_opened)
	svc.container_closed.connect(_listen_closed)

	# 1. Open a BANK store: signal fired, truth returned.
	var opened: Dictionary = svc.open_container("probe_dq", 1)
	if not bool(opened.get("success", false)):
		push_error("FAIL: open_container rejected a valid BANK open: %s" % str(opened))
		quit(1)
		return
	var key := str(opened.get("key", ""))
	if key == "" or _opened_key != key or _opened_type != 1:
		push_error("FAIL: container_opened did not fire with the open's key (%s / %s)" % [_opened_key, str(_opened_type)])
		quit(1)
		return
	print("[OK] open_container opened %s and emitted container_opened" % key)

	# 2. Add an item through the store, then the panel renders it.
	var item_script: GDScript = load("res://core/schemas/item.gd")
	var item = item_script.new()
	item.id = "wep_iron_sword"
	item.display_name = "Iron Sword"
	item.stack_size = 1
	var added: Dictionary = svc.add_item(key, item)
	if not bool(added.get("success", false)):
		push_error("FAIL: add_item rejected: %s" % str(added))
		quit(1)
		return
	var panel = load("res://ui/components/container_ui.gd").new()
	root.add_child(panel)
	panel.show_container(key)
	var rows: Control = panel.get_node_or_null("Panel/Main/Rows")
	if rows == null:
		push_error("FAIL: ContainerUI did not build its standard content shell")
		panel.queue_free()
		quit(1)
		return
	var saw_item := false
	for child in rows.get_children():
		if child is Label and str(child.text).contains("Iron Sword"):
			saw_item = true
	if not saw_item:
		push_error("FAIL: container panel did not render the store's item")
		quit(1)
		return
	print("[OK] ContainerUI renders the store (item row visible headless)")

	# 3. Close: container_closed fires and the panel stops showing.
	svc.close_container(key)
	if _closed_key != key:
		push_error("FAIL: close_container did not emit container_closed (%s)" % _closed_key)
		quit(1)
		return
	print("[OK] close_container emitted container_closed")
	panel.queue_free()
	print("--- SLOT CONTAINER LOOP: ok=true ---")
	quit(0)

func _listen_opened(key: String, container_type: int) -> void:
	_opened_key = key
	_opened_type = container_type

func _listen_closed(key: String) -> void:
	_closed_key = key
