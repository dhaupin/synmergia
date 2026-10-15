


extends "res://ui/components/ui_panel.gd"
class_name TitleUI
const TitleData = preload("res://core/schemas/title_data.gd")

## Runtime autoload lookups (script-mode-safe; the bare identifiers
## fail compile when autoloads are absent -- test_islands).
func _titleservice() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("TitleService")) if tree and tree.root else null

## TitleUI - Title management panel
## Allows players to view unlocked titles and equip/unequip prefix/suffix titles

## Title color options (excluding gold - reserved for GM)
const TITLE_COLORS: Array[Color] = [
	Color(0.65, 0.65, 0.65),   # gray (common)
	Color(0.75, 0.60, 0.40),   # bronze (uncommon)
	Color(0.65, 0.70, 0.80),   # silver (rare)
	Color(0.60, 0.50, 0.75),   # purple (epic)
	Color(0.45, 0.65, 0.70),   # teal (legendary)
	Color(1.0, 0.8, 0.8),      # light pink
	Color(0.8, 1.0, 0.8),      # light green
	Color(0.8, 0.8, 1.0),      # light blue
]

## State (inherits _player_id from UIPanel)
var _unlocked_titles: Array[TitleData] = []
var _selected_color: Color = TITLE_COLORS[0]

## UI Components
var _equipped_prefix_label: Label
var _equipped_suffix_label: Label
var _prefix_color_btn: Button
var _suffix_color_btn: Button
var _titles_list: ItemList
var _preview_label: Label

func _ready() -> void:
	super._ready()
	set_title("Titles")
	set_panel_size(Vector2(500, 450))
	_setup_ui()
	_refresh()

func _setup_ui() -> void:
	var panel := get_panel()
	if not panel:
		return

	var main: VBoxContainer = panel.get_node_or_null("Main")
	if not main:
		return

	# Preview section
	var preview_section := _create_preview_section()
	main.add_child(preview_section)

	# Equipped titles section
	var equipped_section := _create_equipped_section()
	main.add_child(equipped_section)

	# Separator
	var sep := HSeparator.new()
	sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_child(sep)

	# Unlocked titles list
	var list_section := _create_titles_list_section()
	main.add_child(list_section)

func _create_preview_section() -> VBoxContainer:
	var section := VBoxContainer.new()
	section.name = "PreviewSection"

	var title := Label.new()
	title.text = "Preview"
	title.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	section.add_child(title)

	_preview_label = Label.new()
	_preview_label.name = "PreviewLabel"
	_preview_label.text = "YourName"
	_preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_label.add_theme_font_size_override("font_size", 16)
	section.add_child(_preview_label)

	return section

func _create_equipped_section() -> HBoxContainer:
	var section := HBoxContainer.new()
	section.name = "EquippedSection"

	# Prefix slot
	var prefix_box := VBoxContainer.new()
	prefix_box.name = "PrefixBox"
	var prefix_title := Label.new()
	prefix_title.text = "Prefix"
	prefix_title.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	prefix_box.add_child(prefix_title)

	_equipped_prefix_label = Label.new()
	_equipped_prefix_label.name = "PrefixLabel"
	_equipped_prefix_label.text = "[None]"
	_equipped_prefix_label.add_theme_color_override("font_color", UIStyles.COLORS.text_disabled)
	prefix_box.add_child(_equipped_prefix_label)

	_prefix_color_btn = Button.new()
	_prefix_color_btn.text = "Color"
	_prefix_color_btn.pressed.connect(_on_prefix_color_clicked)
	prefix_box.add_child(_prefix_color_btn)

	var prefix_unequip := Button.new()
	prefix_unequip.text = "Unequip"
	prefix_unequip.pressed.connect(_on_unequip_prefix)
	prefix_box.add_child(prefix_unequip)

	section.add_child(prefix_box)

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_child(spacer)

	# Suffix slot
	var suffix_box := VBoxContainer.new()
	suffix_box.name = "SuffixBox"
	var suffix_title := Label.new()
	suffix_title.text = "Suffix"
	suffix_title.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	suffix_box.add_child(suffix_title)

	_equipped_suffix_label = Label.new()
	_equipped_suffix_label.name = "SuffixLabel"
	_equipped_suffix_label.text = "[None]"
	_equipped_suffix_label.add_theme_color_override("font_color", UIStyles.COLORS.text_disabled)
	suffix_box.add_child(_equipped_suffix_label)

	_suffix_color_btn = Button.new()
	_suffix_color_btn.text = "Color"
	_suffix_color_btn.pressed.connect(_on_suffix_color_clicked)
	suffix_box.add_child(_suffix_color_btn)

	var suffix_unequip := Button.new()
	suffix_unequip.text = "Unequip"
	suffix_unequip.pressed.connect(_on_unequip_suffix)
	suffix_box.add_child(suffix_unequip)

	section.add_child(suffix_box)

	return section

func _create_titles_list_section() -> VBoxContainer:
	var section := VBoxContainer.new()
	section.name = "TitlesListSection"
	section.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var list_title := Label.new()
	list_title.text = "Unlocked Titles"
	list_title.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	section.add_child(list_title)

	var scroll := preload("res://ui/components/drag_scroll.gd").new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	section.add_child(scroll)

	_titles_list = ItemList.new()
	_titles_list.name = "TitlesList"
	_titles_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_titles_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_titles_list.item_selected.connect(_on_title_selected)
	scroll.add_child(_titles_list)

	return section

## ============================================================================
## PUBLIC API
## ============================================================================

func set_player(player_id: String) -> void:
	_player_id = player_id
	_refresh()

## ============================================================================
## REFRESH
## ============================================================================

func _on_open() -> void:
	_refresh()

func _refresh() -> void:
	if _player_id.is_empty():
		_player_id = _titleservice().get_local_player_id()

	if _player_id.is_empty():
		return
	# _setup_ui bails early when the panel is not ready yet; the refresh
	# helpers below dereference its nodes, so they must be guarded too.
	if _titles_list == null or _preview_label == null:
		return

	# Load unlocked titles
	_unlocked_titles = _titleservice().get_unlocked_titles(_player_id)

	# Update UI
	_update_equipped_display()
	_update_titles_list()
	_update_preview()

func _update_equipped_display() -> void:
	# Labels are built lazily; this can run before they exist.
	if _equipped_prefix_label == null or _equipped_suffix_label == null:
		return
	var prefix: TitleData = _titleservice().get_equipped_prefix(_player_id)
	var suffix: TitleData = _titleservice().get_equipped_suffix(_player_id)

	if prefix != null:
		_equipped_prefix_label.text = "[%s]" % prefix.prefix_form
		_equipped_prefix_label.add_theme_color_override("font_color", _selected_color)
	else:
		_equipped_prefix_label.text = "[None]"
		_equipped_prefix_label.add_theme_color_override("font_color", UIStyles.COLORS.text_disabled)

	if suffix != null:
		_equipped_suffix_label.text = suffix.suffix_form
		_equipped_suffix_label.add_theme_color_override("font_color", _selected_color)
	else:
		_equipped_suffix_label.text = "[None]"
		_equipped_suffix_label.add_theme_color_override("font_color", UIStyles.COLORS.text_disabled)

func _update_titles_list() -> void:
	_titles_list.clear()

	for title: TitleData in _unlocked_titles:
		var display := title.display_name
		if title.has_prefix():
			display += " (Prefix)"
		if title.has_suffix():
			display += " (Suffix)"
		_titles_list.add_item(display)

func _update_preview() -> void:
	var base_name := "PlayerName"
	var prefix: TitleData = _titleservice().get_equipped_prefix(_player_id)
	var suffix: TitleData = _titleservice().get_equipped_suffix(_player_id)

	var full_name := base_name
	if prefix != null:
		full_name = "[%s] %s" % [prefix.prefix_form, full_name]
	if suffix != null:
		full_name = "%s, %s" % [full_name, suffix.suffix_form]

	_preview_label.text = full_name
	_preview_label.add_theme_color_override("font_color", _selected_color)

## ============================================================================
## EVENT HANDLERS
## ============================================================================

func _on_title_selected(index: int) -> void:
	if index < 0 or index >= _unlocked_titles.size():
		return

	var title: TitleData = _unlocked_titles[index]
	_show_equip_dialog(title)

func _show_equip_dialog(title: TitleData) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = title.display_name
	dialog.ok_button_text = "Close"
	add_child(dialog)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(250, 100)
	dialog.add_child(vbox)

	var desc := Label.new()
	desc.text = title.description
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(desc)

	# Equip buttons
	var equip_hbox := HBoxContainer.new()
	vbox.add_child(equip_hbox)

	if title.has_prefix():
		var prefix_btn := Button.new()
		prefix_btn.text = "Equip as Prefix"
		prefix_btn.pressed.connect(func() -> void:
			_equip_title(title.id, "prefix")
			dialog.queue_free()
		)
		equip_hbox.add_child(prefix_btn)

	if title.has_suffix():
		var suffix_btn := Button.new()
		suffix_btn.text = "Equip as Suffix"
		suffix_btn.pressed.connect(func() -> void:
			_equip_title(title.id, "suffix")
			dialog.queue_free()
		)
		equip_hbox.add_child(suffix_btn)

	dialog.confirmed.connect(func() -> void: dialog.queue_free())
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	dialog.popup_centered(Vector2(300, 150))

func _equip_title(title_id: String, slot: String) -> void:
	if _titleservice().equip(_player_id, title_id, slot):
		show_notification("Title equipped!")
		_refresh()
	else:
		show_notification("Failed to equip title", false)

func _on_unequip_prefix() -> void:
	_titleservice().unequip(_player_id, "prefix")
	show_notification("Prefix title unequipped")
	_refresh()

func _on_unequip_suffix() -> void:
	_titleservice().unequip(_player_id, "suffix")
	show_notification("Suffix title unequipped")
	_refresh()

func _on_prefix_color_clicked() -> void:
	_show_color_picker("prefix")

func _on_suffix_color_clicked() -> void:
	_show_color_picker("suffix")


func _show_color_picker(slot: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Select Color"
	dialog.ok_button_text = "Close"
	add_child(dialog)

	var vbox := VBoxContainer.new()
	dialog.add_child(vbox)

	var grid := GridContainer.new()
	grid.columns = 4
	vbox.add_child(grid)

	for color: Color in TITLE_COLORS:
		var color_btn := ColorPickerButton.new()
		color_btn.color = color
		color_btn.custom_minimum_size = Vector2(40, 40)
		color_btn.color_changed.connect(func(c: Color) -> void:
			_selected_color = c
			_update_equipped_display()
			_update_preview()
		)
		grid.add_child(color_btn)

	dialog.confirmed.connect(func() -> void: dialog.queue_free())
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	dialog.popup_centered(Vector2(200, 150))
