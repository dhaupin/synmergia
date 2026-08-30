## SkillAcademyUI - Skill book upgrades and Skill Academy NPC panel
##
## 4 tabs:
##   1. Skills  — all upgradable skills, current level, available upgrades
##   2. Books   — books in inventory, grouped by tier
##   3. Upgrade — select a skill + consume 4 books to upgrade
##   4. Respec  — reset all upgrades (books NOT returned)
class_name SkillAcademyUI
extends UIPanel

enum Tab { SKILLS, BOOKS, UPGRADE, RESPEC }

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

# Respec tab
var _respec_label: Label
var _respec_button: Button
var _respec_cost_label: Label

var _skill_data: CharacterData = null
var _inventory_books: Array = []

var _buy_skill_picker: OptionButton
var _buy_button: Button
var _buy_result_label: Label

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

	var tabs := ["Skills", "Books", "Upgrade", "Respec"]
	for i in tabs.size():
		var btn := Button.new()
		btn.text = tabs[i]
		btn.custom_minimum_size.y = TAB_BAR_HEIGHT
		btn.pressed.connect(func(): _switch_tab(i as Tab))
		bar.add_child(btn)
		_tab_buttons.append(btn)

	return bar

func _build_tab_contents() -> Control:
	var stack := StackContainer.new()
	stack.name = "ContentStack"
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_tab_contents.resize(Tab.RESPEC + 1)
	_tab_contents[Tab.SKILLS] = _build_skills_tab()
	_tab_contents[Tab.BOOKS] = _build_books_tab()
	_tab_contents[Tab.UPGRADE] = _build_upgrade_tab()
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
	skill_lbl.text = "No skill selected — go to the Skills tab and click one."
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
	_tab_buttons[tab].add_theme_stylebox_override("normal", UIStyles.create_button_style_active())

	_refresh_active_tab()

func _refresh_active_tab() -> void:
	match _active_tab:
		Tab.SKILLS:
			_refresh_skills_tab()
		Tab.BOOKS:
			_refresh_books_tab()
		Tab.UPGRADE:
			_refresh_upgrade_tab()
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
			var label := schema.display_name if schema else sid
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
		var book: SkillBook = info["book"]
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
		_upgrade_skill_label.text = "No skill selected — go to the Skills tab and click one."
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
		_upgrade_skill_label.text = "%s — MAX LEVEL (5)" % schema.display_name
		_upgrade_preview_label.text = "This skill is fully upgraded."
		_upgrade_button.disabled = true
		return

	_upgrade_skill_label.text = "%s — Level %d / 5" % [schema.display_name, current_level]

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
		NotificationService.send_to_player(
			_player_id,
			"Upgraded %s to level %d!" % [_selected_skill_id, result.get("new_level", "?")],
			NotificationService.NotificationType.SUCCESS
		)
			_inventory_books = result.get("remaining_books", [])
		_refresh_all()
	else:
		NotificationService.send_to_player(
			_player_id,
			"Upgrade failed: %s" % result.get("reason", "Unknown error"),
			NotificationService.NotificationType.WARNING
		)

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
		_respec_label.text = "You have spent %d skill points on %d upgrade levels." % (
			total_spent, _skill_data.get_total_upgrade_levels())
		_respec_cost_label.text = "Respec cost: %d gold" % cost
		_respec_button.disabled = false

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
		NotificationService.send_to_player(
			_player_id,
			"Respec complete. %d points refunded for %d gold." % [result.get("points_refunded", 0), result.get("cost", 0)],
			NotificationService.NotificationType.WARNING
		)
		_refresh_all()
	else:
		NotificationService.send_to_player(
			_player_id,
			"Respec failed: %s" % result.get("reason", "Unknown error"),
			NotificationService.NotificationType.WARNING
		)

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
		var book: SkillBook = result.get("book")
		if book and inventory.add_item(book):
			_inventory_books.append(book)
			_buy_result_label.text = "Purchased: %s" % book.display_name
			_buy_result_label.add_theme_color_override("font_color", UIStyles.COLORS.success)
			_refresh_books_tab()
		else:
			_buy_result_label.text = "Purchased but inventory full — gold refunded."
			_buy_result_label.add_theme_color_override("font_color", UIStyles.COLORS.warning)
			inventory.add_gold(result.get("cost", 0))
	else:
		_buy_result_label.text = result.get("reason", "Purchase failed")
		_buy_result_label.add_theme_color_override("font_color", UIStyles.COLORS.error)

func _refresh_all() -> void:
	_refresh_skills_tab()
	_refresh_books_tab()
	_refresh_upgrade_tab()
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

func _on_open() -> void:
	_refresh_all()

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

	var player_entity = GameManager.get_player_entity(player_id)
	if player_entity and player_entity.has("character_data"):
		_skill_data = player_entity.character_data

	if InventoryService:
		var inv_items: Array = InventoryService.get_player_items(player_id)
		for item in inv_items:
			if item is SkillBook:
				_inventory_books.append(item)
