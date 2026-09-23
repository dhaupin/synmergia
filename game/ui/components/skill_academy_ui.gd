## SkillAcademyUI - Skill book upgrades and Skill Academy NPC panel
##
## 5 tabs:
##   1. Skills     -- all upgradable skills, current level, available upgrades
##   2. Books     -- books in inventory, grouped by tier
##   3. Upgrade   -- select a skill + consume 4 books to upgrade
##   4. Signature -- choose 1 of 3 class signatures (level 10+)
##   5. Respec    -- reset all upgrades (books NOT returned)

extends "res://ui/components/ui_panel.gd"
class_name SkillAcademyUI

const CharacterData = preload("res://core/schemas/character_data.gd")
const SkillBook = preload("res://core/schemas/skill_book.gd")
const SkillSchema = preload("res://core/schemas/skill.gd")
const Item = preload("res://core/schemas/item.gd")
const InventoryComponent = preload("res://core/components/inventory_component.gd")
# SkillAcademyService and InventoryService are autoloads, accessed by bare identifier

## Stub methods mirroring UIPanel -- real wiring via .tscn scene setup

func open(player_id: String) -> void:
	_player_id = player_id
	_is_open = true
	visible = true
	panel_opened.emit()

func close() -> void:
	_is_open = false
	visible = false
	panel_closed.emit()

func toggle(player_id: String) -> void:
	# Override: the base UIPanel toggle is a stub in this class hierarchy
	# (the old no-op left the panel stuck invisible on the K hotkey).
	if visible:
		close()
	else:
		open(player_id)

func is_open() -> bool:
	return _is_open and visible

func get_panel() -> PanelContainer:
	return null

func get_content() -> VBoxContainer:
	return null

func set_title(title: String) -> void:
	pass

func set_panel_size(size: Vector2) -> void:
	pass

func show_notification(msg: String, success: bool = true) -> void:
	pass


enum Tab { SKILLS, BOOKS, UPGRADE, SIGNATURE, STATS, RESPEC }

const HEADER_HEIGHT: int = 50
const TAB_BAR_HEIGHT: int = 44
const FOOTER_HEIGHT: int = 50
const SLOT_SIZE: int = 50

var _tab_buttons: Array[Button] = []
var _tab_contents: Array[Control] = []
var _active_tab: Tab = Tab.SKILLS

# Skill tab
var _skill_list: VBoxContainer
var _skill_buttons: Array[Button] = []
var _selected_skill_id: String = ""

# Books tab
var _books_list: VBoxContainer

# Upgrade tab
var _upgrade_skill_label: Label
var _upgrade_preview_label: Label
var _upgrade_button: Button

# Stats tab
var _stat_rows: Dictionary = {}  # stat_name -> {container, value_label, plus_btn, minus_btn}
var _stat_points_label: Label
var _stat_respec_button: Button
var _stat_warnings_label: Label

const _TIER_THRESHOLDS := {"rare": 30, "epic": 60, "legendary": 90, "mythic": 120}

# Respec tab
var _respec_label: Label
var _respec_button: Button
var _respec_cost_label: Label

var _skill_data: CharacterData = null
var _inventory_books: Array = []

var _npc_position: Vector3 = Vector3.ZERO
var _proximity_enabled: bool = false

var _buy_skill_picker: OptionButton
var _buy_button: Button
var _buy_result_label: Label


func _ready() -> void:
	# MUST call super: UIPanel._ready sets visible = false and builds the
	# overlay/panel chrome. Without it this panel boots VISIBLE with an
	# empty tracker state, which poisons the K toggle (first press sees
	# visible -> closes; second press re-opens) and leaves a stale
	# _open_panels entry that breaks ESC stack handling.
	super._ready()
	_setup_accessibility()
	_bind_service_signals()


func _setup_accessibility() -> void:
	pass

func update_accessibility_settings(high_contrast: bool, text_scale: float, reduce_motion: bool) -> void:
	pass


func _bind_service_signals() -> void:
	var svc = SkillAcademyService
	if not svc:
		return
	if svc.has_signal("upgrade_applied"):
		if not svc.upgrade_applied.is_connected(_on_upgrade_applied):
			svc.upgrade_applied.connect(_on_upgrade_applied)
	if svc.has_signal("respec_completed"):
		if not svc.respec_completed.is_connected(_on_respec_completed):
			svc.respec_completed.connect(_on_respec_completed)
	if svc.has_signal("signature_selected"):
		if not svc.signature_selected.is_connected(_on_signature_selected):
			svc.signature_selected.connect(_on_signature_selected)


func _on_upgrade_applied(_player_id: String, skill_id: String, _new_level: int) -> void:
	if is_open():
		_refresh_active_tab()


func _on_respec_completed(_player_id: String, points_refunded: int) -> void:
	if is_open():
		_refresh_active_tab()

func _setup_panel() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(640, 580)
	panel.add_theme_stylebox_override("panel", UIStyles.create_panel_style())
	panel.name = "Panel"
	add_child(panel)

	var main := VBoxContainer.new()
	main.name = "Main"
	panel.add_child(main)

	# Header
	var header := _build_header()
	main.add_child(header)

	# Tab bar
	var tab_bar := _build_tab_bar()
	main.add_child(tab_bar)

	# Content (4 tabs stacked, show only active)
	var content_stack := _build_tab_contents()
	main.add_child(content_stack)

	# Footer with points summary
	var footer := _build_footer()
	main.add_child(footer)

func _build_header() -> Control:
	var h := HBoxContainer.new()
	h.custom_minimum_size.y = HEADER_HEIGHT
	h.name = "Header"

	var title := Label.new()
	title.text = "Skill Academy"
	title.add_theme_font_size_override("font_size", 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	h.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(36, 36)
	close_btn.pressed.connect(close)
	h.add_child(close_btn)

	return h

func _build_tab_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.custom_minimum_size.y = TAB_BAR_HEIGHT
	bar.name = "TabBar"

	var tabs := ["Skills", "Books", "Upgrade", "Signature", "Stats", "Respec"]
	for i in tabs.size():
		var btn := Button.new()
		btn.text = tabs[i]
		btn.custom_minimum_size.y = TAB_BAR_HEIGHT
		btn.pressed.connect(func(): _switch_tab(i as Tab))
		bar.add_child(btn)
		_tab_buttons.append(btn)

	return bar

func _build_tab_contents() -> Control:
	var stack := VBoxContainer.new()
	stack.name = "ContentStack"
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_tab_contents.resize(Tab.RESPEC + 1)
	_tab_contents[Tab.SKILLS] = _build_skills_tab()
	_tab_contents[Tab.BOOKS] = _build_books_tab()
	_tab_contents[Tab.UPGRADE] = _build_upgrade_tab()
	_tab_contents[Tab.SIGNATURE] = _build_signature_tab()
	_tab_contents[Tab.STATS] = _build_stats_tab()
	_tab_contents[Tab.RESPEC] = _build_respec_tab()

	for i in _tab_contents.size():
		var c: Control = _tab_contents[i]
		c.visible = (i == _active_tab)
		stack.add_child(c)

	return stack

func _build_skills_tab() -> Control:
	var sc := ScrollContainer.new()
	sc.name = "SkillsTab"
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var wrapper := VBoxContainer.new()
	wrapper.name = "Wrapper"
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(wrapper)

	var header_row := HBoxContainer.new()
	header_row.custom_minimum_size.y = 30
	var name_h := Label.new(); name_h.text = "Skill"; name_h.size_flags_horizontal = Control.SIZE_EXPAND_FILL; header_row.add_child(name_h)
	var level_h := Label.new(); level_h.text = "Level"; level_h.custom_minimum_size.x = 80; header_row.add_child(level_h)
	var tier_h := Label.new(); tier_h.text = "Next Tier"; tier_h.custom_minimum_size.x = 100; header_row.add_child(tier_h)
	wrapper.add_child(header_row)

	_skill_list = VBoxContainer.new()
	_skill_list.name = "SkillList"
	_skill_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrapper.add_child(_skill_list)

	return sc

func _build_books_tab() -> Control:
	var sc := ScrollContainer.new()
	sc.name = "BooksTab"
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var wrapper := VBoxContainer.new()
	wrapper.name = "Wrapper"
	sc.add_child(wrapper)

	var info := Label.new()
	info.name = "Info"
	info.text = "Skill books in your inventory. Higher tier books drop from bosses and rare spawns."
	wrapper.add_child(info)

	_books_list = VBoxContainer.new()
	_books_list.name = "BooksList"
	_books_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrapper.add_child(_books_list)

	var divider := HSeparator.new()
	divider.name = "Divider"
	wrapper.add_child(divider)

	var buy_label := Label.new()
	buy_label.name = "BuyLabel"
	buy_label.text = "Buy Common Skill Book (%d gold)" % SkillAcademyService.COMMON_BOOK_PRICE
	wrapper.add_child(buy_label)

	var buy_row := HBoxContainer.new()
	buy_row.name = "BuyRow"
	wrapper.add_child(buy_row)

	_buy_skill_picker = OptionButton.new()
	_buy_skill_picker.name = "BuySkillPicker"
	_buy_skill_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buy_row.add_child(_buy_skill_picker)

	_buy_button = Button.new()
	_buy_button.name = "BuyButton"
	_buy_button.text = "Buy"
	_buy_button.pressed.connect(_on_buy_book_pressed)
	buy_row.add_child(_buy_button)

	_buy_result_label = Label.new()
	_buy_result_label.name = "BuyResult"
	_buy_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	wrapper.add_child(_buy_result_label)

	return sc

func _build_upgrade_tab() -> Control:
	var root := VBoxContainer.new()
	root.name = "UpgradeTab"
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var info := Label.new()
	info.name = "Info"
	info.text = "Select a skill from the Skills tab, then upgrade here using 4 matching-tier books."
	info.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(info)

	var divider := HSeparator.new()
	divider.name = "Divider"
	root.add_child(divider)

	var selected_box := VBoxContainer.new()
	selected_box.name = "SelectedBox"
	root.add_child(selected_box)

	var skill_lbl := Label.new()
	skill_lbl.name = "SkillLabel"
	skill_lbl.text = "No skill selected -- go to the Skills tab and click one."
	selected_box.add_child(skill_lbl)
	_upgrade_skill_label = skill_lbl

	var preview_lbl := Label.new()
	preview_lbl.name = "PreviewLabel"
	preview_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	preview_lbl.text = ""
	selected_box.add_child(preview_lbl)
	_upgrade_preview_label = preview_lbl

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(spacer)

	var btn := Button.new()
	btn.name = "UpgradeButton"
	btn.text = "Upgrade (requires 4 books + 1 skill point)"
	btn.pressed.connect(_on_upgrade_pressed)
	btn.disabled = true
	root.add_child(btn)
	_upgrade_button = btn

	return root

func _build_signature_tab() -> Control:
	var root := VBoxContainer.new()
	root.name = "SignatureTab"

	var header := Label.new()
	header.name = "Header"
	header.text = "Choose Your Signature"
	header.add_theme_font_size_override("font_size", 18)
	root.add_child(header)

	var info := Label.new()
	info.name = "Info"
	info.autowrap_mode = TextServer.AUTOWRAP_WORD
	info.text = "Your signature is a defining ability unique to your class. Choose one of three variants at level 10. The first selection is FREE. Subsequent changes cost %d gold." % CharacterData.new().signature_change_cost
	root.add_child(info)

	var divider := HSeparator.new()
	divider.name = "Divider"
	root.add_child(divider)

	var sig_list := VBoxContainer.new()
	sig_list.name = "SignatureList"
	sig_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(sig_list)

	return root

func _build_stats_tab() -> Control:
	var root := VBoxContainer.new()
	root.name = "StatsTab"

	# Points available header
	var header := HBoxContainer.new()
	header.name = "Header"

	var pts_lbl := Label.new()
	pts_lbl.name = "PointsLabel"
	pts_lbl.text = "Available Points: --"
	pts_lbl.add_theme_color_override("font_color", UIStyles.SKILL_COLORS.available_points)
	header.add_child(pts_lbl)
	_stat_points_label = pts_lbl

	var focal_lbl := Label.new()
	focal_lbl.name = "FocalLabel"
	focal_lbl.text = ""
	focal_lbl.add_theme_color_override("font_color", UIStyles.SKILL_COLORS.focal)
	header.add_child(focal_lbl)

	root.add_child(header)

	# Stats list
	var stats_scroll := ScrollContainer.new()
	stats_scroll.name = "StatsScroll"
	stats_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(stats_scroll)

	var stats_list := VBoxContainer.new()
	stats_list.name = "StatsList"
	stats_scroll.add_child(stats_list)

	var stats := ["strength", "agility", "intelligence", "vitality", "endurance", "wisdom"]
	for stat in stats:
		var row := _build_stat_row(stat)
		stats_list.add_child(row)

	# Warnings section
	_stat_warnings_label = Label.new()
	_stat_warnings_label.name = "Warnings"
	_stat_warnings_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.2))
	_stat_warnings_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(_stat_warnings_label)

	# Respec button
	var respec_box := HBoxContainer.new()
	respec_box.name = "RespecBox"
	respec_box.alignment = BoxContainer.ALIGNMENT_END

	var respec_lbl := Label.new()
	respec_lbl.text = "Reset all points: "
	respec_box.add_child(respec_lbl)

	_stat_respec_button = Button.new()
	_stat_respec_button.name = "StatRespecButton"
	_stat_respec_button.text = "Respec Stats (-- gold)"
	_stat_respec_button.pressed.connect(_on_stat_respec_pressed)
	respec_box.add_child(_stat_respec_button)

	root.add_child(respec_box)

	return root

func _build_stat_row(stat_name: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = stat_name.capitalize() + "Row"
	row.custom_minimum_size.y = 36

	# Stat name
	var name_lbl := Label.new()
	name_lbl.name = "Name"
	name_lbl.text = stat_name.capitalize()
	name_lbl.custom_minimum_size.x = 100
	row.add_child(name_lbl)

	# Value display
	var value_lbl := Label.new()
	value_lbl.name = "Value"
	value_lbl.text = "--"
	value_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_lbl.custom_minimum_size.x = 60
	row.add_child(value_lbl)

	# Minus button
	var minus_btn := Button.new()
	minus_btn.name = "Minus"
	minus_btn.text = "-"
	minus_btn.custom_minimum_size.x = 36
	minus_btn.pressed.connect(func(): _on_stat_minus(stat_name))
	row.add_child(minus_btn)

	# Plus button
	var plus_btn := Button.new()
	plus_btn.name = "Plus"
	plus_btn.text = "+"
	plus_btn.custom_minimum_size.x = 36
	plus_btn.pressed.connect(func(): _on_stat_plus(stat_name))
	row.add_child(plus_btn)

	# Tier indicator
	var tier_lbl := Label.new()
	tier_lbl.name = "TierIndicator"
	tier_lbl.text = "[C]"
	tier_lbl.add_theme_color_override("font_color", UIStyles.SKILL_COLORS.tier_label)
	tier_lbl.custom_minimum_size.x = 35
	row.add_child(tier_lbl)

	# Focal indicator
	var focal_lbl := Label.new()
	focal_lbl.name = "FocalIndicator"
	focal_lbl.text = ""
	focal_lbl.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	row.add_child(focal_lbl)

	_stat_rows[stat_name] = {
		"container": row,
		"value_label": value_lbl,
		"plus_btn": plus_btn,
		"minus_btn": minus_btn,
		"tier_lbl": tier_lbl,
		"focal_lbl": focal_lbl
	}

	return row

func _refresh_stats_tab() -> void:
	if _skill_data == null:
		return

	var cls := _skill_data.class_data
	var focal1 := cls.focal_stat_1 if cls else ""
	var focal2 := cls.focal_stat_2 if cls else ""

	# Update focal indicator label
	var focal_lbl := self.get_node_or_null("Header/FocalLabel") as Label
	if focal_lbl:
		focal_lbl.text = "Focal: %s + %s" % [focal1.capitalize(), focal2.capitalize()]

	# Update available points
	var available := _skill_data.get_available_stat_points()
	_stat_points_label.text = "Available Points: %d" % available

	# Update each stat row
	var all_stats := _skill_data.get_all_stats_with_allocated()
	for stat_name in _stat_rows.keys():
		var row_data: Dictionary = _stat_rows[stat_name]
		var total: int = all_stats.get(stat_name, 0)
		var allocated: int = _skill_data.get_allocated_points(stat_name)
		var base: int = total - allocated

		row_data["value_label"].text = "%d (+%d)" % [total, allocated]

		# Update tier indicator
		var tier_color: Color
		var tier_text: String
		if total >= _TIER_THRESHOLDS.get("mythic", 120):
			tier_color = UIStyles.SKILL_COLORS.tier_mythic
			tier_text = "[M]"
		elif total >= _TIER_THRESHOLDS.get("legendary", 90):
			tier_color = UIStyles.SKILL_COLORS.tier_legendary
			tier_text = "[L]"
		elif total >= _TIER_THRESHOLDS.get("epic", 60):
			tier_color = UIStyles.SKILL_COLORS.tier_epic
			tier_text = "[E]"
		elif total >= _TIER_THRESHOLDS.get("rare", 30):
			tier_color = UIStyles.SKILL_COLORS.tier_rare
			tier_text = "[R]"
		else:
			tier_color = UIStyles.SKILL_COLORS.tier_common
			tier_text = "[C]"
		row_data["tier_lbl"].text = tier_text
		row_data["tier_lbl"].add_theme_color_override("font_color", tier_color)

		# Highlight focal stats
		var is_focal: bool = stat_name == focal1 or stat_name == focal2
		row_data["focal_lbl"].text = "*" if is_focal else ""

		# Enable/disable buttons
		row_data["plus_btn"].disabled = available <= 0
		row_data["minus_btn"].disabled = allocated <= 0

	# Update respec cost
	var total_allocated := _skill_data.get_total_allocated_points()
	var respec_cost := SkillAcademyService.get_stat_respec_cost(total_allocated)
	_stat_respec_button.text = "Respec Stats (%d gold)" % respec_cost
	_stat_respec_button.disabled = total_allocated <= 0

func _on_stat_plus(stat_name: String) -> void:
	if _skill_data == null:
		return

	if _skill_data.allocate_stat_point(stat_name):
		_refresh_stats_tab()
		_notify_stat_changed()

func _on_stat_minus(stat_name: String) -> void:
	if _skill_data == null:
		return

	if _skill_data.deallocate_stat_point(stat_name):
		_refresh_stats_tab()
		_notify_stat_changed()

func _on_stat_respec_pressed() -> void:
	if _skill_data == null:
		return

	var preview: Dictionary = SkillAcademyService.preview_stat_respec(_skill_data)
	var downgrades: Array = preview.get("affected_skills", [])

	if not downgrades.is_empty():
		var msg := "WARNING: The following skills will be DOWNGRADED:\n"
		for d in downgrades:
			msg += "- %s (Lvl %d -> Lvl %d)\n" % [d.get("display_name", ""), d.get("current_level", 0), d.get("downgrade_to", 0)]
		msg += "\nContinue?"
		_stat_warnings_label.text = msg
	else:
		_stat_warnings_label.text = ""

func _notify_stat_changed() -> void:
	# Notify GameManager that player stats changed (for derived stat recalculation)
	if GameManager and _player_id != "":
		var entity = EntityService.get_entity(_player_id)
		if entity and entity.has_method("on_stats_changed"):
			entity.on_stats_changed()

func _build_respec_tab() -> Control:
	var root := VBoxContainer.new()
	root.name = "RespecTab"

	var warning := Label.new()
	warning.name = "Warning"
	warning.add_theme_color_override("font_color", Color(1.0, 0.5, 0.2))
	warning.text = "WARNING: Respeccing will RESET ALL skill upgrades.\nYour consumed books will NOT be returned.\nYou will get all spent skill points back."
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(warning)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(spacer)

	var confirm_box := VBoxContainer.new()
	confirm_box.name = "ConfirmBox"
	root.add_child(confirm_box)

	_respec_label = Label.new()
	_respec_label.name = "RespecLabel"
	confirm_box.add_child(_respec_label)

	_respec_cost_label = Label.new()
	_respec_cost_label.name = "RespecCostLabel"
	_respec_cost_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	confirm_box.add_child(_respec_cost_label)

	_respec_button = Button.new()
	_respec_button.name = "RespecButton"
	_respec_button.text = "Confirm Respec"
	_respec_button.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	_respec_button.pressed.connect(_on_respec_pressed)
	confirm_box.add_child(_respec_button)

	return root

func _build_footer() -> Control:
	var f := HBoxContainer.new()
	f.custom_minimum_size.y = FOOTER_HEIGHT
	f.name = "Footer"

	var pts_lbl := Label.new()
	pts_lbl.name = "PointsLabel"
	pts_lbl.text = "Skill Points: --"
	f.add_child(pts_lbl)

	return f

func _switch_tab(tab: Tab) -> void:
	if tab == _active_tab:
		return
	_tab_contents[_active_tab].visible = false
	_tab_buttons[_active_tab].remove_theme_stylebox_override("normal")

	_active_tab = tab
	_tab_contents[tab].visible = true
	_tab_buttons[tab].add_theme_stylebox_override("normal", UIStyles.create_button_style()["normal"])

	_refresh_active_tab()

func _refresh_active_tab() -> void:
	match _active_tab:
		Tab.SKILLS:
			_refresh_skills_tab()
		Tab.BOOKS:
			_refresh_books_tab()
		Tab.UPGRADE:
			_refresh_upgrade_tab()
		Tab.SIGNATURE:
			_refresh_signature_tab()
		Tab.STATS:
			_refresh_stats_tab()
		Tab.RESPEC:
			_refresh_respec_tab()

func _refresh_skills_tab() -> void:
	for btn in _skill_buttons:
		if is_instance_valid(btn):
			btn.queue_free()
	_skill_buttons.clear()

	if not is_instance_valid(_skill_data):
		return

	var catalog_ids: Array = SkillAcademyService.get_catalog_skill_ids()
	for skill_id in catalog_ids:
		var schema: SkillSchema = SkillAcademyService.get_skill_schema(skill_id)
		if schema == null:
			continue

		var current_level: int = _skill_data.get_skill_upgrade_level(skill_id)
		var maxed: bool = current_level >= 5
		var next_tier: String = SkillAcademyService.get_next_tier_name(skill_id, current_level)

		var row := HBoxContainer.new()
		row.custom_minimum_size.y = SLOT_SIZE

		var name_lbl := Label.new()
		name_lbl.text = schema.display_name
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)

		var level_lbl := Label.new()
		level_lbl.text = "%d / 5" % current_level
		level_lbl.custom_minimum_size.x = 80
		row.add_child(level_lbl)

		var tier_lbl := Label.new()
		if maxed:
			tier_lbl.text = "MAX"
			tier_lbl.add_theme_color_override("font_color", Color(1.0, 0.8, 0.0))
		else:
			tier_lbl.text = next_tier.capitalize()
		tier_lbl.custom_minimum_size.x = 100
		row.add_child(tier_lbl)

		var select_btn := Button.new()
		select_btn.text = "Select"
		select_btn.pressed.connect(func(): _select_skill_for_upgrade(skill_id))
		row.add_child(select_btn)
		_skill_buttons.append(select_btn)

		_skill_list.add_child(row)

func _refresh_books_tab() -> void:
	for child in _books_list.get_children():
		child.queue_free()

	# Rebuild buy-picker with current catalog
	if _buy_skill_picker:
		_buy_skill_picker.clear()
		var skill_ids: Array = SkillAcademyService.get_catalog_skill_ids()
		for sid in skill_ids:
			var schema: SkillSchema = SkillAcademyService.get_skill_schema(sid)
			var label: String = schema.display_name if schema else sid
			_buy_skill_picker.add_item(label)

	# Count books by skill_id + tier
	var book_counts: Dictionary = {}
	for book in _inventory_books:
		if book is SkillBook:
			var key: String = "%s:%d" % [book.book_skill_id, book.book_upgrade_level]
			if not book_counts.has(key):
				book_counts[key] = {"count": 0, "book": book}
			book_counts[key]["count"] += 1

	if book_counts.is_empty():
		var empty := Label.new()
		empty.text = "No skill books in inventory."
		_books_list.add_child(empty)
		return

	for key in book_counts:
		var parts: PackedStringArray = key.split(":")
		var skill_id: String = parts[0]
		var level: int = int(parts[1])
		var info: Dictionary = book_counts[key]
		var count: int = info["count"]
		var book: Item = info["book"]
		var tier_names := ["", "Common", "Rare", "Epic", "Legendary", "Mythic"]

		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 30

		var name_lbl := Label.new()
		name_lbl.text = book.display_name
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)

		var tier_lbl := Label.new()
		tier_lbl.text = tier_names[level]
		tier_lbl.add_theme_color_override("font_color", book.get_rarity_color())
		tier_lbl.custom_minimum_size.x = 80
		row.add_child(tier_lbl)

		var count_lbl := Label.new()
		count_lbl.text = "x%d / 4 needed" % count
		count_lbl.custom_minimum_size.x = 120
		row.add_child(count_lbl)

		_books_list.add_child(row)

func _select_skill_for_upgrade(skill_id: String) -> void:
	_selected_skill_id = skill_id
	_switch_tab(Tab.UPGRADE)

func _refresh_upgrade_tab() -> void:
	if _upgrade_skill_label == null:
		return

	if _selected_skill_id == "":
		_upgrade_skill_label.text = "No skill selected -- go to the Skills tab and click one."
		_upgrade_preview_label.text = ""
		_upgrade_button.disabled = true
		return

	var schema: SkillSchema = SkillAcademyService.get_skill_schema(_selected_skill_id)
	if schema == null:
		_upgrade_skill_label.text = "Unknown skill."
		return

	var current_level: int = 0
	if is_instance_valid(_skill_data):
		current_level = _skill_data.get_skill_upgrade_level(_selected_skill_id)

	if current_level >= 5:
		_upgrade_skill_label.text = "%s -- MAX LEVEL (5)" % schema.display_name
		_upgrade_preview_label.text = "This skill is fully upgraded."
		_upgrade_button.disabled = true
		return

	_upgrade_skill_label.text = "%s -- Level %d / 5" % [schema.display_name, current_level]

	var preview: Dictionary = SkillAcademyService.get_upgrade_preview(_selected_skill_id, current_level)
	if preview.is_empty() or preview.get("maxed", false):
		_upgrade_preview_label.text = "No more upgrade tiers."
		_upgrade_button.disabled = true
		return

	var tier: String = preview.get("tier", "").capitalize()
	var books_req: int = preview.get("books_required", 4)
	var cumulative: Dictionary = preview.get("cumulative", {})

	var preview_text := "Next upgrade: %s tier (%d books needed)\\n" % [tier, books_req]
	preview_text += "Effect at level %d:\\n" % preview.get("next_level", 0)
	for key in cumulative:
		var pct: float = (cumulative[key] - 1.0) * 100.0
		var sign: String = "+" if pct >= 0 else ""
		preview_text += "  %s: %s%.1f%%\\n" % [key, sign, pct]
	preview_text += "\\nSkill points available: "
	if is_instance_valid(_skill_data):
		preview_text += "%d" % _skill_data.get_available_skill_points()
	else:
		preview_text += "--"
	_upgrade_preview_label.text = preview_text

	_upgrade_button.disabled = false

func _on_upgrade_pressed() -> void:
	if _selected_skill_id == "" or not is_instance_valid(_skill_data):
		return

	var result: Dictionary = SkillAcademyService.apply_upgrade(
		_player_id, _selected_skill_id, _skill_data, _inventory_books
	)

	if result.get("success", false):
		show_notification("Upgraded %s to level %d!" % [_selected_skill_id, result.get("new_level", "?")])
		_inventory_books = result.get("remaining_books", [])
		_refresh_all()
	else:
		show_notification("Upgrade failed: %s" % result.get("reason", "Unknown error"), false)

func _refresh_signature_tab() -> void:
	if not is_instance_valid(_skill_data):
		return

	var panel: PanelContainer = get_panel()
	if not panel:
		return
	var sig_list: VBoxContainer = panel.get_node_or_null("Main/ContentStack/SignatureTab/SignatureList")
	if not sig_list:
		return

	# Clear existing
	for child in sig_list.get_children():
		sig_list.remove_child(child)
		child.queue_free()

	# Get player level from entity
	var player_level: int = 1
	var player: Node = EntityService.get_entity(_player_id) if EntityService else null
	if player and "level" in player:
		player_level = player.level

	var info: Dictionary = SkillAcademyService.get_signature_info(_skill_data, player_level)

	# Update info text based on state
	var info_lbl: Label = panel.get_node_or_null("Main/ContentStack/SignatureTab/Info")
	if info_lbl:
		if info.get("must_select", false):
			info_lbl.text = "You reached level 10! Choose your signature ability. First selection is FREE."
			info_lbl.add_theme_color_override("font_color", UIStyles.COLORS.success)
		elif info.get("can_change", false):
			var cost: int = info.get("change_cost", 1000)
			var free_text: String = " (FREE)" if info.get("is_free", false) else " (%d gold)" % cost
			info_lbl.text = "Your signature: %s. Click another to change it.%s" % [
				info.get("active_signature", "None"),
				free_text
			]
		else:
			info_lbl.text = "Reach level 10 to unlock signature selection."

	# Populate signature list
	var available_sigs: Array = info.get("available_signatures", [])
	for sig_info in available_sigs:
		var sig_id: String = sig_info.get("skill_id", "")
		var display_name: String = sig_info.get("display_name", sig_id)
		var desc: String = sig_info.get("description", "")
		var is_active: bool = sig_info.get("is_active", false)
		var is_locked: bool = sig_info.get("is_locked", true)

		var card := PanelContainer.new()
		card.custom_minimum_size.y = 80
		card.add_theme_stylebox_override("panel", UIStyles.create_panel_style())
		if is_active:
			card.add_theme_color_override("border_color", UIStyles.COLORS.success)

		var card_inner := VBoxContainer.new()
		card.add_child(card_inner)

		var name_row := HBoxContainer.new()
		card_inner.add_child(name_row)

		var name_lbl := Label.new()
		name_lbl.text = display_name
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if is_active:
			name_lbl.add_theme_color_override("font_color", UIStyles.COLORS.success)
		name_row.add_child(name_lbl)

		if is_active:
			var active_lbl := Label.new()
			active_lbl.text = " [ACTIVE]"
			active_lbl.add_theme_color_override("font_color", UIStyles.COLORS.success)
			name_row.add_child(active_lbl)

		var desc_lbl := Label.new()
		desc_lbl.text = desc
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card_inner.add_child(desc_lbl)

		if is_locked:
			var locked_lbl := Label.new()
			locked_lbl.text = "Unlock at level 10"
			locked_lbl.add_theme_color_override("font_color", UIStyles.COLORS.warning)
			card_inner.add_child(locked_lbl)
		else:
			var select_btn := Button.new()
			if is_active:
				select_btn.text = "Active"
				select_btn.disabled = true
			else:
				select_btn.text = "Select" if info.get("is_free", false) else "Select (1000g)"
			select_btn.pressed.connect(func(): _on_signature_selected(sig_id))
			card_inner.add_child(select_btn)

		sig_list.add_child(card)

func _refresh_respec_tab() -> void:
	if not is_instance_valid(_skill_data):
		_respec_label.text = "Character data unavailable."
		_respec_button.disabled = true
		return

	var total_spent: int = _skill_data.spent_skill_points
	if total_spent == 0:
		_respec_label.text = "No skill points spent. Nothing to reset."
		_respec_button.disabled = true
	else:
		var cost: int = SkillAcademyService.get_respec_cost(total_spent)
		_respec_label.text = "You have spent %d skill points on %d upgrade levels." % [total_spent, _skill_data.get_total_upgrade_levels()]
		_respec_cost_label.text = "Respec cost: %d gold" % cost
		_respec_button.disabled = false

func _on_signature_selected(sig_id: String) -> void:
	if sig_id == "" or not is_instance_valid(_skill_data):
		return

	var player_level: int = 1
	var player: Node = EntityService.get_entity(_player_id) if EntityService else null
	if player and "level" in player:
		player_level = player.level

	var gold: int = 0
	var inventory: Node = null
	if player and player.inventory_component:
		inventory = player.inventory_component
		gold = inventory.get_gold()

	var result: Dictionary = SkillAcademyService.change_signature(
		_player_id, _skill_data, sig_id, player_level, gold, inventory
	)

	if result.get("success", false):
		var msg: String = "Signature set to %s!" % sig_id
		if result.get("cost", 0) > 0:
			msg += " (-%d gold)" % result.get("cost", 0)
		show_notification(msg)
		_refresh_all()
	else:
		show_notification("Failed to change signature: %s" % result.get("reason", "Unknown error"), false)

func _on_respec_pressed() -> void:
	if not is_instance_valid(_skill_data):
		return

	var player: Node = EntityService.get_entity(_player_id)
	if not player or not player.inventory_component:
		return
	var inventory: Node = player.inventory_component
	var gold: int = inventory.get_gold()

	var result: Dictionary = SkillAcademyService.respec(_player_id, _skill_data, gold, player)
	if result.get("success", false):
		show_notification("Respec complete. %d points refunded for %d gold." % [result.get("points_refunded", 0), result.get("cost", 0)])
		_refresh_all()
	else:
		show_notification("Respec failed: %s" % result.get("reason", "Unknown error"), false)

func _on_buy_book_pressed() -> void:
	if not _buy_skill_picker or _buy_skill_picker.selected < 0:
		return

	var skill_ids: Array = SkillAcademyService.get_catalog_skill_ids()
	if _buy_skill_picker.selected >= skill_ids.size():
		return

	var skill_id: String = skill_ids[_buy_skill_picker.selected]
	var player: Node = EntityService.get_entity(_player_id)
	if not player or not player.inventory_component:
		_buy_result_label.text = "Cannot access inventory."
		return

	var inventory: InventoryComponent = player.inventory_component
	var gold: int = inventory.get_gold()

	var result: Dictionary = SkillAcademyService.purchase_book(_player_id, skill_id, gold)
	if result.get("success", false):
		inventory.remove_gold(result.get("cost", 0))
		var book: Item = result.get("book")
		if book and inventory.add_item(book):
			_inventory_books.append(book)
			_buy_result_label.text = "Purchased: %s" % book.display_name
			_buy_result_label.add_theme_color_override("font_color", UIStyles.COLORS.success)
			_refresh_books_tab()
		else:
			_buy_result_label.text = "Purchased but inventory full -- gold refunded."
			_buy_result_label.add_theme_color_override("font_color", UIStyles.COLORS.warning)
			inventory.add_gold(result.get("cost", 0))
	else:
		_buy_result_label.text = result.get("reason", "Purchase failed")
		_buy_result_label.add_theme_color_override("font_color", UIStyles.COLORS.error)

func _refresh_all() -> void:
	_refresh_skills_tab()
	_refresh_books_tab()
	_refresh_upgrade_tab()
	_refresh_signature_tab()
	_refresh_respec_tab()
	_refresh_footer()

func _refresh_footer() -> void:
	var panel: PanelContainer = get_panel()
	if not panel:
		return
	var footer: HBoxContainer = panel.get_node_or_null("Main/Footer")
	if not footer:
		return
	var pts_lbl: Label = footer.get_node_or_null("PointsLabel")
	if pts_lbl and is_instance_valid(_skill_data):
		var earned: int = _skill_data.get_earned_skill_points()
		var spent: int = _skill_data.spent_skill_points
		var available: int = _skill_data.get_available_skill_points()
		pts_lbl.text = "Skill Points: %d earned | %d spent | %d available" % [earned, spent, available]

func _process(_delta: float) -> void:
	if not _proximity_enabled or _npc_position == Vector3.ZERO:
		return
	var player := _get_local_player()
	if player == null:
		return
	if player.global_position.distance_to(_npc_position) > 8.0:
		close()
		if NotificationService:
			var NotifKind = load("res://core/notifications/notification_kind.gd").NotifKind
			NotificationService.notify(NotifKind.CUSTOM, "Moved too far from the trainer.",
				"SkillAcademyUI", "sac_out_of_range", {}, _player_id)


func _get_local_player() -> Node:
	if PlayerManager and PlayerManager.has_method("get_local_player"):
		return PlayerManager.get_local_player()
	return null


func _on_open() -> void:
	_refresh_all()


func set_npc_proximity(pos: Vector3) -> void:
	_npc_position = pos
	_proximity_enabled = true


func open_with_context(player_id: String, skill_data: CharacterData, inventory_books: Array) -> void:
	_skill_data = skill_data
	_inventory_books = inventory_books
	_selected_skill_id = ""
	open(player_id)

## Load skill data and inventory from the current player context.
## Called by player_controller when opening the UI.
func load_player_context(player_id: String) -> void:
	_player_id = player_id
	_skill_data = null
	_inventory_books = []

	if not GameManager:
		return

	var player_entity = EntityService.get_entity(player_id)
	# NOTE: Node has no .has(); use the `in` operator (4.7.2).
	if player_entity != null and "character_data" in player_entity:
		_skill_data = player_entity.character_data

	if InventoryService:
		# get_player_items() never existed; the registered
		# InventoryComponent is the authoritative item store.
		var inv: InventoryComponent = InventoryService.get_inventory(player_id)
		if inv != null:
			var inv_items: Array = inv.get_all_items()
			for item in inv_items:
				if item is SkillBook:
					_inventory_books.append(item)
