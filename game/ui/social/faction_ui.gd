## FactionUI - Faction reputation and war status display
## Shows player's faction standings, reputation, and war declarations
extends "res://ui/components/ui_panel.gd"
class_name FactionUI
var _factions: Array = []
var _selected_faction: Dictionary = {}

func _ready() -> void:
	super._ready()
	set_title("Factions")
	set_panel_size(Vector2(500, 400))
	_setup_ui()

func _setup_ui() -> void:
	var panel := get_panel()
	if not panel:
		return

	var main: VBoxContainer = panel.get_node_or_null("Main")
	if not main:
		return

	# Faction list (scrollable)
	var scroll := ScrollContainer.new()
	scroll.name = "FactionScroll"
	scroll.custom_minimum_size.y = 300
	main.add_child(scroll)

	var list := VBoxContainer.new()
	list.name = "FactionList"
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

func _on_open() -> void:
	_refresh_factions()

func _refresh_factions() -> void:
	if not FactionManager:
		return

	var list: VBoxContainer = get_node_or_null("Panel/Main/FactionScroll/FactionList")
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

	# Faction name. The Faction schema field is display_name (reading
	# "name" rendered a column of "?" -- round-12 screenshot). Fall
	# back hard so a row can never be anonymous again.
	var name_lbl := Label.new()
	var faction_name: String = _field(faction, "display_name", "")
	if faction_name == "":
		faction_name = _field(faction, "name", "")
	if faction_name == "":
		faction_name = _field(faction, "id", "Unknown faction")
	name_lbl.text = faction_name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(name_lbl)

	# Reputation badge
	var rep_lbl := Label.new()
	var player_rep: int = 0
	if _player_id != "" and FactionManager:
		player_rep = FactionManager.get_reputation(_player_id, _field(faction, "id", ""))
	rep_lbl.text = "Rep: %d" % player_rep
	rep_lbl.add_theme_color_override("font_color", _get_rep_color(player_rep))
	hbox.add_child(rep_lbl)

	# War indicator
	if FactionManager and FactionManager.get_faction_wars(_field(faction, "id", "")).size() > 0:
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

## Resource.get(key, default) lost its default arg in 4.7.2; factions may
## arrive as Dictionary or Resource, so read defensively through either.
func _field(obj, key: String, default_val) -> Variant:
	if obj is Dictionary:
		return obj.get(key, default_val)
	if obj != null and key in obj:
		var v = obj.get(key)
		if v != null:
			return v
	return default_val
