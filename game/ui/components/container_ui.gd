## ContainerUI - the container_opened consumer (MenuManager panel)
## SlotService's container_opened signal sat DEAD for the scaffolding
## era: the file it lives in was flat/unparseable (see slot_service.gd
## history note) and no endpoint ever emitted it. Both halves are live
## now: SlotService.open_container emits, and THIS panel consumes.
## MenuManager mounts it as the "container" registry row; any storage
## surface opened through the service (vault doors, dwelling chests,
## mount packs, loot bags) feeds a real UI instead of a silent emit.
## Read-only this round: render the store, one row per item -- the
## move/swap wiring is the next consumer round. Shell law: the panel
## builds inside UIPanel's standard "Panel/Main" content box via
## _setup_content() (the nine-subclass no-Panel sweep documenting
## how invisible panels were born from hand-rolled shells).

extends "res://ui/components/ui_panel.gd"

class_name ContainerUI

## Fires whenever show_container() lays out a store (HUD logging).
signal container_shown(key: String)

## The store this panel is currently rendering, as a SlotService key.
var _container_key: String = ""

## Build-once content refs (inside the base Panel/Main shell).
var _title_label: Label
var _rows_box: VBoxContainer

func _setup_content() -> void:
	# Deliberate no-op: content builds LAZILY in _ensure_content().
	# The base's _setup_content call is DEFERRED behind _ready, but
	# show_container() used to hit a half-built shell when called
	# synchronously right after add_child (the test receipt caught
	# it). Idempotent one-shot build on first use, base shell or not.
	pass

## Idempotent synchronous content build (on the standard Panel/Main
## shell when present). The fallback constructs the base's own
## canonical shell synchronously (the deferred _ready second pass is
## idempotent) so the node path always matches -- the old literal
## fallback left the store rows on an anonymous node and the standard
## header built a SECOND shell later on top.
func _ensure_content() -> void:
	if _rows_box != null:
		return
	if not has_node("Panel/Main"):
		_setup_base_panel()
	var main := get_node("Panel/Main") as VBoxContainer
	if main.get_node_or_null("Rows") == null:
		_build_ui(main)
	else:
		_title_label = main.get_node_or_null("Title") as Label
		_rows_box = main.get_node_or_null("Rows") as VBoxContainer

## Build the content into the given VBox (base "Main" or the fallback).
func _build_ui(shell: VBoxContainer) -> void:
	_title_label = Label.new()
	_title_label.name = "Title"
	_title_label.text = "Container"
	shell.add_child(_title_label)

	_rows_box = VBoxContainer.new()
	_rows_box.name = "Rows"
	shell.add_child(_rows_box)

## UIPanel open path (menu_manager's _open_panel calls open(pid)).
func _on_open() -> void:
	_ensure_content()
	_refresh()

## Enter the panel with a key directly (the hud slot-open path).
## Does NOT open the panel by itself: hud_integrator routes through
## the MenuManager funnel so the back stack stays consistent.
func show_container(key: String, container_type: int = -1) -> void:
	_ensure_content()
	_unused(container_type)
	_container_key = key
	if _title_label:
		_title_label.text = _friendly_title(key)
	_refresh()
	container_shown.emit(key)

## The container_type arg is reserved for the move/swap round.
func _unused(_type: int) -> void:
	pass

## Is this panel currently rendering that key? (hud close routing.)
func is_showing(key: String) -> bool:
	return _container_key == key and visible

func _friendly_title(key: String) -> String:
	var parts := key.split(":")
	var ct := parts[1] if parts.size() > 1 else ""
	if ct == "":
		return "Container"
	var nice: String = ct.to_lower().capitalize()
	if parts.size() > 2 and parts[2] != "":
		nice += " (%s)" % parts[2]
	return nice

## Pull the service's store truth and lay it out. Runtime resolution:
## the bare class_name dies in headless script probes (the parse-law
## AGENTS.md documents), so SlotService loads over the wire here.
func _refresh() -> void:
	if _rows_box == null:
		return
	for child in _rows_box.get_children():
		child.queue_free()
	if _container_key == "":
		return
	var slot_script: GDScript = load("res://core/services/slot_service.gd")
	if slot_script == null or not slot_script.can_instantiate():
		_add_row_label("(store service unavailable)")
		return
	var svc = slot_script.singleton()
	if svc.get_container_size(_container_key) <= 0 and svc.get_all_items(_container_key).is_empty():
		_add_row_label("(empty store)")
		return
	var items: Array = svc.get_all_items(_container_key)
	if items.is_empty():
		_add_row_label("(empty store)")
		return
	for item in items:
		if item == null:
			continue
		var qty := int(item.stack_size) if "stack_size" in item else 1
		var item_name: String = str(item.display_name) if "display_name" in item else str(item.id)
		_add_row_label("%s x%d" % [item_name, maxi(qty, 1)])

func _add_row_label(text: String) -> void:
	var row := Label.new()
	row.text = text
	_rows_box.add_child(row)
