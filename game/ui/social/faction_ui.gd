## FactionUI - Faction reputation and war status display
## Shows player's faction standings, reputation, and war declarations
extends Control
class_name FactionUI

const UIStyles = preload("res://ui/components/ui_styles.gd")
const UIPanel = preload("res://ui/components/ui_panel.gd")

var _player_id: String = ""
var _factions: Array = []
var _selected_faction: Dictionary = {}

signal panel_opened()
signal panel_closed()

func _ready() -> void:
	name = "FactionUI"
	visible = false
	_setup_ui()

func _setup_ui() -> void:
	# Main container
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	add_child(vbox)

	# Header
	var header := Label.new()
	header.text = "Factions"
	header.add_theme_font_size_override("font_size", 18)
	vbox.add_child(header)

	# Faction list (scrollable)
	var scroll := ScrollContainer.new()
	scroll.name = "FactionScroll"
	scroll.custom_minimum_size.y = 300
	vbox.add_child(scroll)

	var list := VBoxContainer.new()
	list.name = "FactionList"
	scroll.add_child(list)

	# Close button
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(close)
	vbox.add_child(close_btn)

func open(panel_id: String = "") -> void:
	visible = true
	panel_opened.emit()
	_refresh_factions()

func close() -> void:
	visible = false
	panel_closed.emit()

func toggle(panel_id: String = "") -> void:
	if visible:
		close()
	else:
		open(panel_id)

func is_open() -> bool:
	return visible

func _refresh_factions() -> void:
	if not FactionManager:
		return
	
	var list: VBoxContainer = get_node_or_null("VBox/FactionScroll/FactionList")
	if not list:
		return
	
	# Clear existing
	for child in list.get_children():
		child.queue_free()
	
	# Load all factions
	_factions = FactionManager.get_all_factions()
	
	for faction in _factions:
		var row := _create_faction_row(faction)
		list.add_child(row)

func _create_faction_row(faction) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = 50
	
	var hbox := HBoxContainer.new()
	panel.add_child(hbox)
	
	# Faction name
	var name_lbl := Label.new()
	name_lbl.text = faction.get("name", "?")
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(name_lbl)
	
	# Reputation badge
	var rep_lbl := Label.new()
	var player_rep: int = 0
	if _player_id != "" and FactionManager:
		player_rep = FactionManager.get_reputation(_player_id, faction.get("id", ""))
	rep_lbl.text = "Rep: %d" % player_rep
	rep_lbl.add_theme_color_override("font_color", _get_rep_color(player_rep))
	hbox.add_child(rep_lbl)
	
	# War indicator
	if FactionManager and FactionManager.get_faction_wars(faction.get("id", "")).size() > 0:
		var war_lbl := Label.new()
		war_lbl.text = " [AT WAR]"
		war_lbl.add_theme_color_override("font_color", Color.RED)
		hbox.add_child(war_lbl)
	
	return panel

func _get_rep_color(rep: int) -> Color:
	if rep >= 10000:
		return Color.GOLD
	elif rep >= 5000:
		return Color.GREEN
	elif rep >= 1000:
		return Color.CYAN
	elif rep >= 0:
		return Color.WHITE
	else:
		return Color.ORANGE

func set_player_id(player_id: String) -> void:
	_player_id = player_id
	if visible:
		_refresh_factions()
