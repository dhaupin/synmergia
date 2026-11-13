## AdminCatalog - In-game catalog for spawning/managing entities.
## Browses the REAL loaded data (DataService) and spawns through the REAL
## services (SpawnService / inventory / ZoneManager / QuestService /
## SkillAcademyService). It is a MOD-facing panel, mounted as a tab in
## AdminDashboard.
##
## The original file shipped as a mock: a hardcoded list of invented ids
## (eny_goblin, zn_tutorial, ...) that resolve to nothing, and spawn legs
## that only emitted an event. This rebuild reads the live catalog and
## routes every action through the authority that owns it.
extends Control
class_name AdminCatalog

signal entity_spawned(entity_id: String, success: bool)
signal item_spawned(item_id: String, success: bool)

## Catalog categories
enum Category {
	ALL,
	ENEMIES,
	NPCS,
	ITEMS,
	ZONES,
	QUESTS,
	SKILLS,
}

## UI elements
var _category_tabs: HBoxContainer
var _search_input: LineEdit
var _item_list: ItemList
var _spawn_button: Button
var _quantity_spin: SpinBox

## Current state
var _current_category: Category = Category.ALL
var _search_filter: String = ""
var _catalog_entries: Array[Dictionary] = []


## Runtime autoload lookup (script-mode-safe; the bare identifiers are not
## guaranteed outside the autoload tree -- AGENTS.md convention).
func _svc(node_name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath(node_name)) if tree and tree.root else null


func _ready() -> void:
	_initialize_catalog()
	_setup_ui()


## Build the catalog from the live data loader. Every entry is a real
## resource id that a spawn leg can resolve; the receipt pins this.
func _initialize_catalog() -> void:
	_catalog_entries = []
	var ds := _svc("DataService")
	if ds == null:
		return
	_append_entries(ds, "get_all_enemies", "ENEMY")
	_append_entries(ds, "get_all_npcs", "NPC")
	_append_entries(ds, "get_all_items", "ITEM")
	_append_entries(ds, "get_all_zones", "ZONE")
	_append_entries(ds, "get_all_quests", "QUEST")
	_append_entries(ds, "get_all_skills", "SKILL")


func _append_entries(ds: Node, getter: String, type_str: String) -> void:
	if not ds.has_method(getter):
		return
	for res in ds.call(getter):
		if res == null:
			continue
		var entry_id: String = str(res.get("id")) if ("id" in res) else ""
		if entry_id == "":
			continue
		var name: String = str(res.get("display_name")) if ("display_name" in res) else entry_id
		var lvl: int = int(res.get("level")) if ("level" in res) else 1
		_catalog_entries.append({"id": entry_id, "name": name, "type": type_str, "level": lvl})


func _setup_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(vbox)

	var title := Label.new()
	title.text = "Admin Catalog"
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)

	_search_input = LineEdit.new()
	_search_input.placeholder_text = "Search by ID or name..."
	_search_input.text_submitted.connect(_on_search_changed)
	vbox.add_child(_search_input)

	_category_tabs = HBoxContainer.new()
	var categories := ["All", "Enemies", "NPCs", "Items", "Zones", "Quests", "Skills"]
	for i in range(categories.size()):
		var btn := Button.new()
		btn.text = categories[i]
		btn.pressed.connect(_on_category_selected.bind(i))
		_category_tabs.add_child(btn)
	vbox.add_child(_category_tabs)

	_item_list = ItemList.new()
	_item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_item_list)

	var bottom_hbox := HBoxContainer.new()

	_quantity_spin = SpinBox.new()
	_quantity_spin.min_value = 1
	_quantity_spin.max_value = 100
	_quantity_spin.value = 1
	_quantity_spin.prefix = "Qty: "
	bottom_hbox.add_child(_quantity_spin)

	_spawn_button = Button.new()
	_spawn_button.text = "Spawn"
	_spawn_button.pressed.connect(_on_spawn_pressed)
	bottom_hbox.add_child(_spawn_button)

	var refresh_btn := Button.new()
	refresh_btn.text = "Refresh"
	refresh_btn.pressed.connect(_refresh_list)
	bottom_hbox.add_child(refresh_btn)

	vbox.add_child(bottom_hbox)

	_refresh_list()


func _refresh_list() -> void:
	if _item_list == null:
		return
	_item_list.clear()
	for entry in _catalog_entries:
		if _current_category != Category.ALL:
			var type_filter := _get_category_type(_current_category)
			if entry.type != type_filter:
				continue
		if _search_filter != "":
			var search := _search_filter.to_lower()
			var matches_name: bool = str(entry.name).to_lower().contains(search)
			var matches_id: bool = str(entry.id).to_lower().contains(search)
			if not matches_name and not matches_id:
				continue
		_item_list.add_item("%s [%s]" % [entry.name, entry.id])


func _get_category_type(category: Category) -> String:
	match category:
		Category.ENEMIES: return "ENEMY"
		Category.NPCS: return "NPC"
		Category.ITEMS: return "ITEM"
		Category.ZONES: return "ZONE"
		Category.QUESTS: return "QUEST"
		Category.SKILLS: return "SKILL"
	return ""


func _on_category_selected(category: int) -> void:
	_current_category = category as Category
	_refresh_list()


func _on_search_changed(text: String) -> void:
	_search_filter = text
	_refresh_list()


func _on_spawn_pressed() -> void:
	var selected := _item_list.get_selected_items()
	if selected.is_empty():
		GameLog.warn("AdminCatalog: No item selected")
		return
	var item_text := _item_list.get_item_text(selected[0])
	var id_match := RegEx.new()
	id_match.compile("\\[([^\\]]+)\\]")
	var result := id_match.search(item_text)
	if result == null:
		return
	var template_id: String = result.get_string(1)
	var quantity: int = int(_quantity_spin.value)
	if _spawn_by_id(template_id, quantity):
		GameLog.info("AdminCatalog: Spawned %d x %s" % [quantity, template_id])
	else:
		GameLog.error("AdminCatalog: Failed to spawn %s" % template_id)


## The single dispatch: resolve the id against the live data and route the
## action to the service that owns it.
func _spawn_by_id(template_id: String, quantity: int = 1) -> bool:
	var ds := _svc("DataService")
	if ds == null:
		return false
	if ds.has_method("get_enemy") and ds.get_enemy(template_id) != null:
		return _spawn_enemy(template_id, quantity)
	if ds.has_method("get_npc") and ds.get_npc(template_id) != null:
		return _spawn_npc(template_id)
	if ds.has_method("get_item") and ds.get_item(template_id) != null:
		return _spawn_item(template_id, quantity)
	if ds.has_method("get_zone") and ds.get_zone(template_id) != null:
		return _teleport_to_zone(template_id)
	if ds.has_method("get_quest") and ds.get_quest(template_id) != null:
		return _give_quest(template_id)
	if ds.has_method("get_skill") and ds.get_skill(template_id) != null:
		return _teach_skill(template_id)
	GameLog.error("AdminCatalog: Unknown catalog id: %s" % template_id)
	return false


## The local player body (PlayerManager.local_player), or null.
func _local_player() -> Node:
	var pm := _svc("PlayerManager")
	if pm != null and pm.get("local_player") != null:
		return pm.local_player
	return null


## The zone the local player is standing in, or "".
func _local_zone_id() -> String:
	var player := _local_player()
	var zm := _svc("ZoneManager")
	if player != null and zm != null and zm.has_method("get_entity_zone_id"):
		return str(zm.get_entity_zone_id(player))
	return ""


func _spawn_enemy(template_id: String, quantity: int) -> bool:
	var spawn := _svc("SpawnService")
	if spawn == null or not spawn.has_method("spawn_enemy_direct"):
		return false
	var player := _local_player()
	var base: Vector3 = player.global_position if player != null else Vector3.ZERO
	var zone_id := _local_zone_id()
	var any := false
	for i in range(max(1, quantity)):
		var pos := base + Vector3(randf_range(-5, 5), 0, randf_range(-5, 5))
		if spawn.spawn_enemy_direct(template_id, pos, zone_id) != null:
			any = true
	if any:
		entity_spawned.emit(template_id, true)
	return any


func _spawn_npc(template_id: String) -> bool:
	var spawn := _svc("SpawnService")
	var ds := _svc("DataService")
	if spawn == null or ds == null or not spawn.has_method("spawn_npc_entity"):
		return false
	var npc_data = ds.get_npc(template_id)
	if npc_data == null:
		return false
	var player := _local_player()
	var base: Vector3 = player.global_position if player != null else Vector3.ZERO
	var npc = spawn.spawn_npc_entity(_local_zone_id(), base + Vector3(2, 0, 0), npc_data)
	if npc != null:
		entity_spawned.emit(template_id, true)
	return npc != null


func _spawn_item(template_id: String, quantity: int) -> bool:
	var ds := _svc("DataService")
	var player := _local_player()
	if ds == null or player == null or not ("inventory_component" in player):
		return false
	var comp = player.get("inventory_component")
	if comp == null or not comp.has_method("add_item"):
		return false
	var item = ds.get_item(template_id)
	if item == null:
		return false
	var ok: bool = comp.add_item(item, max(1, quantity))
	if ok:
		item_spawned.emit(template_id, true)
	return ok


func _teleport_to_zone(zone_id: String) -> bool:
	var zm := _svc("ZoneManager")
	var ds := _svc("DataService")
	var player := _local_player()
	if zm == null or ds == null or player == null:
		return false
	var zone = ds.get_zone(zone_id)
	if zone == null:
		return false
	return zm.entity_enter_zone(player, zone)


func _give_quest(quest_id: String) -> bool:
	var qs := _svc("QuestService")
	var player := _local_player()
	if qs == null or player == null or not qs.has_method("accept_quest"):
		return false
	return qs.accept_quest(str(player.get("entity_id")), quest_id)


## Grant a common-tier skill book (the academy's own real item path).
func _teach_skill(skill_id: String) -> bool:
	var sa := _svc("SkillAcademyService")
	var player := _local_player()
	if sa == null or player == null or not sa.has_method("create_book"):
		return false
	var book = sa.create_book(skill_id, "common")
	if book == null:
		return false
	if not ("inventory_component" in player):
		return false
	var comp = player.get("inventory_component")
	if comp == null or not comp.has_method("add_item"):
		return false
	return comp.add_item(book, 1)


## Get catalog entry by ID
func get_entry_by_id(id: String) -> Dictionary:
	for entry in _catalog_entries:
		if entry.id == id:
			return entry
	return {}


## Get all entries filtered by type
func get_entries_by_type(type_filter: String) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for entry in _catalog_entries:
		if entry.type == type_filter:
			results.append(entry)
	return results


## Add a new entry to the catalog (for runtime registration)
func register_entry(id: String, name: String, type_str: String, level: int = 1) -> void:
	_catalog_entries.append({
		"id": id,
		"name": name,
		"type": type_str.to_upper(),
		"level": level
	})
	_refresh_list()
