## WorkbenchUI - the crafting recipe table (S16.9, prd-crafting.md).
## Station-aware recipe browser: lists the CraftingService catalog,
## shows the bill (inputs the checker will demand), the outputs, and
## the failure posture, and executes every craft through the ONE gate
## ( CraftingService.craft -- no side-door crafting exists in the UI
## any more than in the service ).
##
## Opening context:
##   open_for_player(pid, station)      -- a workbench surface (the
##      station filters which recipes the bench even lists).
##   set_inventory(inventory)           -- the purse the craft's
##      affordability counts ride on (mirrors BlacksmithUI's seam).
##
extends "res://ui/components/ui_panel.gd"

class_name WorkbenchUI

const UIPanel = preload("res://ui/components/ui_panel.gd")
const RecipeData = preload("res://core/schemas/recipe_data.gd")
const InventoryComponent = preload("res://core/components/inventory_component.gd")

const CraftingService = preload("res://core/services/crafting_service.gd")

const REASON_TEXT: Dictionary = {
	"unknown_recipe": "That recipe is not taught here.",
	"missing_inputs": "You lack the bill for that craft.",
	"recipe_data_defect": "That recipe's data is broken (the service refuses).",
	"no_inventory": "You have no purse to craft with.",
	"forge_ate_it": "The forge ate it — but the byproducts keep the loop fed.",
	# The gate emits two more reachable reasons (empty crafter id, and
	# the QoS cadence limit when a craft bot spams the bench). Every
	# reason the gate CAN speak must be mapped here -- a raw key on the
	# status line would be the UI inventing a message the gate didn't.
	"no_crafter": "No crafter stood at this bench.",
	"rate_limited": "Catch your breath between crafts.",
}

const STATION_NAMES: Dictionary = {
	RecipeData.Station.NONE: "Hand craft (anywhere)",
	RecipeData.Station.FORGE: "The Forge",
	RecipeData.Station.WORKBENCH: "The Workbench",
	RecipeData.Station.ALCHEMY: "The Cauldron",
}

var inventory: InventoryComponent = null
var station: RecipeData.Station = RecipeData.Station.NONE

var _recipe_list: VBoxContainer
var _gold_label: Label
var _status_label: Label


func open_for_player(player_id: String, at_station: int = RecipeData.Station.NONE) -> void:
	station = at_station
	if not _is_open:
		open(player_id)
	else:
		# Already-open re-offer (the bench handed to the NEXT crafter
		# without a close in between): rebind the crafter id, or the
		# craft press still bills the PREVIOUS crafter's purse (the
		# probe pinned exactly that with two owners on one bench).
		_player_id = player_id
		refresh_purse()
		_refresh_recipes()


func set_inventory(inventory_component: InventoryComponent) -> void:
	inventory = inventory_component
	refresh_purse()


func _setup_panel() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(460, 560)
	panel.add_theme_stylebox_override("panel", UIStyles.create_panel_style(
		UIStyles.COLORS.background_dark,
		UIStyles.COLORS.border, 2, 12
	))
	panel.name = "Panel"
	add_child(panel)

	var main := VBoxContainer.new()
	main.name = "Main"
	panel.add_child(main)


func _ready() -> void:
	super._ready()


func _setup_header() -> void:
	var panel := get_panel()
	if not panel:
		return
	var main := panel.get_node_or_null("Main") as VBoxContainer
	if not main:
		return
	var header := HBoxContainer.new()
	header.name = "Header"
	main.add_child(header)
	main.move_child(header, 0)

	var title := Label.new()
	title.text = "The Workbench"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	header.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.pressed.connect(close)
	header.add_child(close_btn)


func _setup_content() -> void:
	var panel := get_panel()
	if not panel:
		return
	var main: VBoxContainer = panel.get_node_or_null("Main") as VBoxContainer
	if not main:
		return

	# Purse row -- the craft bill lives against the inventory.
	var purse_row := HBoxContainer.new()
	purse_row.custom_minimum_size.y = 32
	main.add_child(purse_row)

	var purse_title := Label.new()
	purse_title.text = "Your Gold: "
	purse_title.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	purse_row.add_child(purse_title)

	_gold_label = Label.new()
	_gold_label.text = "0"
	_gold_label.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	purse_row.add_child(_gold_label)

	# The recipe table itself.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 380
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main.add_child(scroll)

	_recipe_list = VBoxContainer.new()
	_recipe_list.custom_minimum_size.y = 360
	scroll.add_child(_recipe_list)

	# Status / gate-refusal line -- crafting refusals speak HERE.
	_status_label = Label.new()
	_status_label.custom_minimum_size.y = 44
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	_status_label.add_theme_font_size_override("font_size", 13)
	main.add_child(_status_label)

	var btn_row := HBoxContainer.new()
	btn_row.custom_minimum_size.y = 44
	main.add_child(btn_row)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_btn.pressed.connect(close)
	btn_row.add_child(close_btn)

	if _is_open:
		_refresh_recipes()


func _on_open() -> void:
	_refresh_recipes()


## Count how many of one item id the purse holds (a stack aware count).
func _purse_count_of(item_id: String) -> int:
	if inventory == null:
		return 0
	var total := 0
	for it in inventory.get_all_items():
		if it != null and str(it.id) == item_id:
			total += maxi(1, int(it.current_stack))
	return total


func _refresh_recipes() -> void:
	if not _recipe_list:
		return
	for child in _recipe_list.get_children():
		child.queue_free()

	var cs = get_node_or_null("/root/CraftingService")
	if cs == null or not cs.has_method("get_recipe"):
		var lbl := Label.new()
		lbl.text = "The bench is cold (crafting service absent)."
		lbl.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
		_recipe_list.add_child(lbl)
		return

	# The service owns the catalog law; the bench only filters by
	# which station it IS (a forge lists FORGE+NONE recipes, etc).
	var ds = get_node_or_null("/root/DataService")
	var recipes: Array = []
	var svc_catalog = cs.call("all_recipe_ids") if cs.has_method("all_recipe_ids") else []
	for rid in svc_catalog:
		var recipe = cs.call("get_recipe", rid)
		if recipe == null:
			continue
		# A TYPED Resource's Object.get(property) is 1-arg-only (the
		# two-arg Variant form throws), but the one-arg call returns null
		# for an absent property -- so coalesce the default ourselves
		# (the probe pinned the 2-arg crash on the WORKBENCH branch).
		var station_raw = recipe.get("station")
		var recipe_station := int(station_raw if station_raw != null else RecipeData.Station.NONE)
		# StationNONE (0) recipes list everywhere; others only at home.
		if recipe_station == RecipeData.Station.NONE or recipe_station == station:
			recipes.append(recipe)

	if recipes.is_empty():
		var lbl := Label.new()
		lbl.text = "No recipes taught at this station."
		lbl.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
		_recipe_list.add_child(lbl)
		return

	recipes.sort_custom(Callable(self, "_by_display_name"))
	for recipe in recipes:
		_add_recipe_row(recipe, ds)


## The typed-Resource property read: one-arg get(), null-coalesced to
## the default. Works on typed RecipeData AND dictionary-backed
## entries alike (a two-arg Variant get would throw on the former).
func _prop(thing, property: String, default):
	var value = thing.get(property)
	return default if value == null else value


## Sort helper: the typed-Resource law on both sides of the compare.
func _by_display_name(a, b) -> bool:
	return str(_prop(a, "display_name", "")) < str(_prop(b, "display_name", ""))


func _add_recipe_row(recipe, ds) -> void:		# The typed-Resource get law (see _refresh_recipes): one-arg get
		# + null-coalesce; Dict-typed props tolerate the two-arg form.

	var recipe_id := str(_prop(recipe, "id", ""))
	var recipe_name := str(_prop(recipe, "display_name", recipe_id))
	var recipe_station := int(_prop(recipe, "station", RecipeData.Station.NONE))
	var description := str(_prop(recipe, "description", ""))
	var inputs: Array = _prop(recipe, "inputs", [])
	var output: Dictionary = _prop(recipe, "output", {})
	var by_raw = _prop(recipe, "byproducts", [])
	var byproducts: int = (by_raw as Array).size() if by_raw is Array else 0
	var failure_rate := float(_prop(recipe, "failure_rate", 0.0))

	var row := PanelContainer.new()
	row.custom_minimum_size.y = 96
	row.add_theme_stylebox_override("panel", UIStyles.create_panel_style(
		UIStyles.COLORS.background,
		UIStyles.COLORS.border, 1, 8
	))
	_recipe_list.add_child(row)

	var row_box := HBoxContainer.new()
	row_box.add_theme_constant_override("separation", 10)
	row.add_child(row_box)

	# Left column: name, bill, posture.
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_box.add_child(info)

	var name_row := HBoxContainer.new()
	info.add_child(name_row)

	var name_lbl := Label.new()
	name_lbl.name = "ItemName"
	name_lbl.text = recipe_name
	name_lbl.add_theme_color_override("font_color", UIStyles.COLORS.text_primary)
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_row.add_child(name_lbl)

	var station_badge := Label.new()
	station_badge.name = "Station"
	station_badge.text = str(STATION_NAMES.get(recipe_station, "Anywhere"))
	station_badge.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	station_badge.add_theme_font_size_override("font_size", 11)
	name_row.add_child(station_badge)

	# The bill: one colored line per input (sufficiency coloring).
	for input_dict: Dictionary in inputs:
		var iid := str(input_dict.get("item_id", ""))
		var need := int(input_dict.get("qty", 1))
		var have := _purse_count_of(iid)
		var display := str(iid)
		if ds != null and ds.has_method("get_item"):
			var item = ds.get_item(iid)
			if item != null:
				display = str(item.display_name)
		var enough := have >= need
		var input_lbl := Label.new()
		input_lbl.name = "Bill_%s" % iid
		input_lbl.text = "• %d× %s — have %d" % [need, display, have]
		input_lbl.add_theme_font_size_override("font_size", 12)
		input_lbl.add_theme_color_override("font_color",
			UIStyles.COLORS.success if enough else UIStyles.COLORS.error)
		info.add_child(input_lbl)

	# Posture line: output + failure honesty.
	var out_id := str(output.get("item_id", ""))
	var out_qty := int(output.get("qty", 1))
	var out_name := out_id
	if ds != null and ds.has_method("get_item"):
		var out_item = ds.get_item(out_id)
		if out_item != null:
			out_name = str(out_item.display_name)
	var posture := "Makes %d× %s" % [out_qty, out_name]
	if failure_rate > 0.0:
		posture += " — fails %d%% (byproducts: %d)" % [int(failure_rate * 100.0), byproducts]
	elif byproducts > 0:
		posture += " — slag: %d" % byproducts
	var posture_lbl := Label.new()
	posture_lbl.name = "Posture"
	posture_lbl.text = posture
	posture_lbl.add_theme_font_size_override("font_size", 12)
	posture_lbl.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	info.add_child(posture_lbl)

	if not description.is_empty():
		var desc_lbl := Label.new()
		desc_lbl.text = description
		desc_lbl.add_theme_font_size_override("font_size", 11)
		desc_lbl.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.custom_minimum_size.x = 300
		info.add_child(desc_lbl)

	# Right column: the craft button + per-craft status.
	var action_col := VBoxContainer.new()
	action_col.custom_minimum_size.x = 150
	row_box.add_child(action_col)

	var craft_btn := Button.new()
	craft_btn.name = "Craft"
	craft_btn.text = "Craft"
	craft_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	craft_btn.pressed.connect(_on_craft_pressed.bind(recipe_id))
	action_col.add_child(craft_btn)


func _on_craft_pressed(recipe_id: String) -> void:
	if not _player_id:
		return
	var cs = get_node_or_null("/root/CraftingService")
	if cs == null or not cs.has_method("craft"):
		_set_status("The workbench is cold (crafting service absent).", false)
		return
	var result: Dictionary = cs.craft(_player_id, recipe_id)
	if bool(result.get("ok", false)):
		var results: Array = result.get("results", [])
		var out := ""
		if not results.is_empty():
			out = str(results[0].get("item_id", ""))
		_set_status("Crafted %s." % out, true)
	else:
		# The gate's own reason is the UI's law: speak it verbatim.
		# The answer shape keeps a BATCH-level refusal reason at top
		# level (unknown_recipe, recipe_data_defect, no_inventory,
		# no_crafter); the per-craft refusal (missing_inputs,
		# rate_limited, forge_ate_it) opens the door in results[0]
		# with the top-level key ABSENT. Prefer the per-attempt
		# reason, fall back to the batch reason, and only then the
		# neutral fallback (previously every refusal rendered as the
		# raw string "refused" -- the player never saw WHY).
		var reason := ""
		var per_attempt: Array = result.get("results", [])
		if not per_attempt.is_empty():
			reason = str(per_attempt[0].get("reason", ""))
		if reason.is_empty():
			reason = str(result.get("reason", "refused"))
		var human: String = REASON_TEXT.get(reason, reason)
		_set_status(human, false)
	_refresh_recipes()


func refresh_purse() -> void:
	if _gold_label and inventory and inventory.has_method("get_gold"):
		_gold_label.text = str(inventory.get_gold())


func _set_status(msg: String, ok: bool) -> void:
	if _status_label and is_instance_valid(_status_label):
		_status_label.text = msg
		# COLORS.danger does not exist (the stylesheet's key is "error");
		# an absent-key read throws and the refusal never renders. Use
		# the dict's OWN error red, like every other UI does.
		_status_label.add_theme_color_override("font_color",
			UIStyles.COLORS.success if ok else UIStyles.COLORS.error)
