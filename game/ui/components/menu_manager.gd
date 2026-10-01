## MenuManager - Central HUD manager for Synmergia
extends CanvasLayer
class_name MenuManager
const UIStyles = preload("res://ui/components/ui_styles.gd")
const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind
const HudLayerScript = preload("res://ui/hud/hud_layer.gd")


## Singleton
static var instance: MenuManager = null

## UI references
var _action_bar: HBoxContainer
var _quick_access_bar: HBoxContainer
var _buff_bar: HBoxContainer
var _status_bar: HBoxContainer

## Panel references
var _inventory_panel: Control
var _chat_panel: Control
var _character_panel: Control
var _guild_panel: Control
var _party_panel: Control
var _friends_panel: Control
var _quest_panel: Control
var _bank_panel: Control
var _blacksmith_panel: Control
var _skill_academy_panel: Control
var _faction_panel: Control
var _achievement_panel: Control
var _title_panel: Control
var _dialog_panel: Control
var _shop_panel: Control
var _transfer_panel: Control
var _trade_panel: Control
var _admin_panel: Control
var _sky_almanac_panel: Control
var _chronicle_panel: Control
var _lobby_panel: Control
var _debug_panel: Control

## State
var _is_hud_visible: bool = true
var _is_menu_open: bool = false
var _open_panels: Array = []

signal menu_toggled(menu_name: String, is_open: bool)
signal hud_visibility_changed(visible: bool)

func _ready() -> void:
	if instance == null:
		instance = self
	else:
		queue_free()
		return

	_setup_accessibility()
	_setup_hud()
	_initialize_panels()
	_connect_signals()
	_install_web_back_bridge()

func _setup_accessibility() -> void:
	# MenuManager is CanvasLayer, apply accessibility to child containers
	for child in get_children():
		if child is Control:
			pass
func _on_text_scale_changed(scale: float) -> void:
	# Propagate text scale changes to all child widgets
	for child in get_children():
		if child.has_method("update_accessibility_settings"):
			child.update_accessibility_settings()

func _on_reduce_motion_changed(enabled: bool) -> void:
	# Propagate reduce motion changes to all child widgets
	for child in get_children():
		if child.has_method("update_accessibility_settings"):
			child.update_accessibility_settings()

func _on_high_contrast_changed(enabled: bool) -> void:
	# Propagate high contrast changes to all child widgets
	for child in get_children():
		if child.has_method("update_accessibility_settings"):
			child.update_accessibility_settings()

func _setup_hud() -> void:
	# Action bar (bottom center) - skills/actions
	# NOTE: this bar is INVISIBLE but its slot controls still sit at
	# bottom-center with MOUSE_FILTER_STOP, so on touch layouts they ate
	# every press aimed at the touch HUD's CRH/ACT buttons underneath
	# (CanvasLayer 20 > the touch HUD's layer). Made fully inert: the
	# touch HUD owns this screen region when active, and keyboard users
	# cast through keys 1-8, not these placeholder slots.
	_action_bar = HBoxContainer.new()
	_action_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_action_bar.offset_top = -80
	_action_bar.offset_bottom = -10
	_action_bar.custom_minimum_size.y = 60
	_action_bar.z_index = 100
	_action_bar.visible = false
	_action_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_action_bar.focus_mode = Control.FOCUS_ALL
	_action_bar.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
	add_child(_action_bar)

	# Quick access bar (bottom left) - consumables
	_quick_access_bar = HBoxContainer.new()
	_quick_access_bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_quick_access_bar.offset_right = 250
	_quick_access_bar.offset_bottom = 60
	_quick_access_bar.custom_minimum_size.y = 50
	_quick_access_bar.z_index = 100
	_quick_access_bar.focus_mode = Control.FOCUS_ALL
	_quick_access_bar.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
	add_child(_quick_access_bar)

	# Buff bar (top right)
	_buff_bar = HBoxContainer.new()
	_buff_bar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_buff_bar.offset_left = -200
	_buff_bar.offset_top = 50
	_buff_bar.custom_minimum_size.y = 40
	_buff_bar.z_index = 100
	_buff_bar.focus_mode = Control.FOCUS_ALL
	_buff_bar.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
	add_child(_buff_bar)

	# Status bar (top center) - HP, MP, XP
	_status_bar = HBoxContainer.new()
	_status_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_status_bar.offset_top = 10
	_status_bar.z_index = 100
	_status_bar.focus_mode = Control.FOCUS_ALL
	_status_bar.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
	add_child(_status_bar)

	# Add placeholder slots
	_setup_action_slots()
	_setup_quick_slots()
	_setup_status_bar()

func _initialize_panels() -> void:
	# Chat panel - created from script
	_chat_panel = preload("res://ui/components/chat_ui.gd").new()
	_chat_panel.name = "ChatUI"
	# Play-test round 3/4 Z-STACK LAW (the one ordering, all readers):
	#   raw HUD widgets (action bar etc.) z 100
	#   < chat z 300 (persistent, covers HUD, sits under menus)
	#   < expanded MENU z 350 (covers chat -- round 4: "menu still
	#     renders below chat"; the expanded panel lives on MainMenuBar,
	#     also a child of THIS layer, so one ordering governs)
	#   < panels z 500 (full cover)
	#   < loading overlay (CanvasLayer 100, whole other layer)
	_chat_panel.z_index = 300
	add_child(_chat_panel)

	# Inventory panel
	_inventory_panel = load("res://ui/components/inventory_ui.gd").new()
	_inventory_panel.name = "InventoryUI"
	_inventory_panel.z_index = 500
	add_child(_inventory_panel)

	# Character stats panel
	_character_panel = load("res://ui/components/character_panel.gd").new()
	_character_panel.name = "CharacterStatsUI"
	_character_panel.z_index = 500
	add_child(_character_panel)

	# Social panels
	_guild_panel = preload("res://ui/social/guild_ui.gd").new()
	_guild_panel.name = "GuildUI"
	_guild_panel.z_index = 500
	add_child(_guild_panel)

	_party_panel = preload("res://ui/social/party_ui.gd").new()
	_party_panel.name = "PartyUI"
	_party_panel.z_index = 500
	add_child(_party_panel)

	_friends_panel = preload("res://ui/social/friends_list.gd").new()

		# Quest panel
	_quest_panel = preload("res://ui/components/quest_ui.gd").new()
	_quest_panel.name = "QuestUI"
	_quest_panel.z_index = 500
	add_child(_quest_panel)

	# Bank/Vault panel
	_bank_panel = preload("res://ui/components/bank_ui.gd").new()
	_bank_panel.name = "BankUI"
	_bank_panel.z_index = 500
	add_child(_bank_panel)

	# Blacksmith panel
	_blacksmith_panel = preload("res://ui/components/blacksmith_ui.gd").new()
	_blacksmith_panel.name = "BlacksmithUI"
	_blacksmith_panel.z_index = 500
	add_child(_blacksmith_panel)

	# Skill Academy panel
	_skill_academy_panel = preload("res://ui/components/skill_academy_ui.gd").new()
	_skill_academy_panel.name = "SkillAcademyUI"
	_skill_academy_panel.z_index = 500
	add_child(_skill_academy_panel)

	_friends_panel.name = "FriendsUI"
	_friends_panel.z_index = 500
	add_child(_friends_panel)

	# Connect panel_closed signals
	_inventory_panel.panel_closed.connect(_on_panel_closed.bind("inventory"))
	_character_panel.panel_closed.connect(_on_panel_closed.bind("character"))
	_guild_panel.panel_closed.connect(_on_panel_closed.bind("guild"))
	_party_panel.panel_closed.connect(_on_panel_closed.bind("party"))
	_friends_panel.panel_closed.connect(_on_panel_closed.bind("friends"))
	_quest_panel.panel_closed.connect(_on_panel_closed.bind("quests"))
	_bank_panel.panel_closed.connect(_on_panel_closed.bind("bank"))
	_blacksmith_panel.panel_closed.connect(_on_panel_closed.bind("blacksmith"))
	_skill_academy_panel.panel_closed.connect(_on_panel_closed.bind("skill_academy"))

	# Faction panel
	_faction_panel = preload("res://ui/social/faction_ui.gd").new()
	_faction_panel.name = "FactionUI"
	_faction_panel.z_index = 500
	add_child(_faction_panel)
	_faction_panel.panel_closed.connect(_on_panel_closed.bind("faction"))

	# Achievement panel
	_achievement_panel = preload("res://ui/social/achievement_ui.gd").new()
	_achievement_panel.name = "AchievementUI"
	_achievement_panel.z_index = 500
	add_child(_achievement_panel)
	_achievement_panel.panel_closed.connect(_on_panel_closed.bind("achievement"))

	# Transfer panel (character-to-character transfers)
	_transfer_panel = preload("res://ui/social/character_transfer_ui.gd").new()
	_transfer_panel.name = "CharacterTransferUI"
	_transfer_panel.z_index = 500
	add_child(_transfer_panel)
	_transfer_panel.panel_closed.connect(_on_panel_closed.bind("transfer"))

	# Trade panel (player-to-player trading; opens empty, populates when
	# a trade session starts via TradeService signals)
	_trade_panel = preload("res://ui/social/trade_ui.gd").new()
	_trade_panel.name = "TradeUI"
	_trade_panel.z_index = 500
	add_child(_trade_panel)
	_trade_panel.panel_closed.connect(_on_panel_closed.bind("trade"))

	# Sky Almanac panel (Skyward Concord; V key)
	_sky_almanac_panel = load("res://ui/components/sky_almanac_ui.gd").new()
	_sky_almanac_panel.name = "SkyAlmanacUI"
	_sky_almanac_panel.z_index = 500
	add_child(_sky_almanac_panel)
	_sky_almanac_panel.panel_closed.connect(_on_panel_closed.bind("sky_almanac"))

	# Chronicle panel (Concord Chronicle reader; J key)
	_chronicle_panel = load("res://ui/components/chronicle_ui.gd").new()
	_chronicle_panel.name = "ChronicleUI"
	_chronicle_panel.z_index = 500
	add_child(_chronicle_panel)
	_chronicle_panel.panel_closed.connect(_on_panel_closed.bind("chronicle"))

	# Lobby panel (S11: matchmaking + duels + LFG; L key). The lobby is
	# canonical -- parties, bouts, and open-world crew ads all live here.
	_lobby_panel = load("res://ui/components/lobby_ui.gd").new()
	_lobby_panel.name = "LobbyUI"
	_lobby_panel.z_index = 500
	add_child(_lobby_panel)
	_lobby_panel.panel_closed.connect(_on_panel_closed.bind("lobby"))

	# Admin panel (requires MOD+)
	_admin_panel = preload("res://ui/admin/admin_dashboard.gd").new()
	_admin_panel.name = "AdminDashboard"
	_admin_panel.z_index = 600
	_admin_panel.visible = false
	add_child(_admin_panel)
	_admin_panel.panel_closed.connect(_on_panel_closed.bind("admin"))

	# Debug panel (requires ADMIN+ or dev mode)
	_debug_panel = _create_debug_panel()
	_debug_panel.name = "DebugPanel"
	_debug_panel.z_index = 600
	_debug_panel.visible = false
	add_child(_debug_panel)
	_debug_panel.panel_closed.connect(_on_panel_closed.bind("debug"))

	# Dialog panel
	_title_panel = preload("res://ui/components/title_ui.gd").new()
	_title_panel.name = "TitleUI"
	_title_panel.z_index = 500
	add_child(_title_panel)

	_dialog_panel = preload("res://ui/components/dialog_ui.gd").new()
	_dialog_panel.name = "DialogUI"
	_dialog_panel.z_index = 500
	add_child(_dialog_panel)

	# Shop panel
	_shop_panel = preload("res://ui/components/shop_ui.gd").new()
	_shop_panel.name = "ShopUI"
	_shop_panel.z_index = 500
	add_child(_shop_panel)

func _on_panel_closed(panel_name: String) -> void:
	if _open_panels.has(panel_name):
		_open_panels.erase(panel_name)
	# Play-day feedback #7: the panel's own close (X) button routes
	# through panel_closed -- not _close_panel -- so without this the
	# touch HUD stayed disarmed (dead buttons) after closing a panel
	# with the X on mobile. Same re-arm law as _close_panel.
	if _open_panels.is_empty() and _is_menu_open:
		_is_menu_open = false
		var im = get_node_or_null("/root/InputManager")
		if im != null and im.has_method("set_touch_hud_panels_open"):
			im.set_touch_hud_panels_open(false)
	menu_toggled.emit(panel_name, false)

func _setup_action_slots() -> void:
	for i in range(8):
		var slot := _create_action_slot(i)
		_action_bar.add_child(slot)

func _setup_quick_slots() -> void:
	for i in range(4):
		var slot := _create_quick_slot(i)
		_quick_access_bar.add_child(slot)

func _setup_status_bar() -> void:
	# Health bar
	var hp_container := VBoxContainer.new()
	hp_container.custom_minimum_size.x = 150

	var hp_label := Label.new()
	hp_label.text = "HP"
	hp_label.add_theme_font_size_override("font_size", 10)
	hp_label.add_theme_color_override("font_color", UIStyles.COLORS.error)
	hp_container.add_child(hp_label)

	var hp_bar := _create_progress_bar(UIStyles.COLORS.error)
	hp_bar.name = "HPBar"
	hp_container.add_child(hp_bar)

	_status_bar.add_child(hp_container)

	# Mana bar
	var mp_container := VBoxContainer.new()
	mp_container.custom_minimum_size.x = 150

	var mp_label := Label.new()
	mp_label.text = "MP"
	mp_label.add_theme_font_size_override("font_size", 10)
	mp_label.add_theme_color_override("font_color", UIStyles.COLORS.info)
	mp_container.add_child(mp_label)

	var mp_bar := _create_progress_bar(UIStyles.COLORS.info)
	mp_bar.name = "MPBar"
	mp_container.add_child(mp_bar)

	_status_bar.add_child(mp_container)

	# XP bar
	var xp_container := VBoxContainer.new()
	xp_container.custom_minimum_size.x = 150

	var xp_label := Label.new()
	xp_label.text = "XP"
	xp_label.add_theme_font_size_override("font_size", 10)
	xp_label.add_theme_color_override("font_color", UIStyles.COLORS.accent_gold)
	xp_container.add_child(xp_label)

	var xp_bar := _create_progress_bar(UIStyles.COLORS.accent_gold)
	xp_bar.name = "XPBar"
	xp_container.add_child(xp_bar)

	_status_bar.add_child(xp_container)

func _create_action_slot(index: int) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(50, 50)
	slot.name = "ActionSlot%d" % index
	slot.focus_mode = Control.FOCUS_ALL
	slot.add_theme_stylebox_override("focus", UIStyles.create_focus_style())

	var style := StyleBoxFlat.new()
	style.bg_color = UIStyles.COLORS.background_dark
	style.border_color = UIStyles.COLORS.border
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	slot.add_theme_stylebox_override("panel", style)

	# Keybind label
	var keybind := Label.new()
	keybind.text = str(index + 1)
	keybind.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	keybind.add_theme_font_size_override("font_size", 10)
	keybind.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	keybind.offset_left = -15
	keybind.offset_right = -3
	keybind.offset_top = -12
	keybind.offset_bottom = -2
	slot.add_child(keybind)

	return slot

func _create_quick_slot(index: int) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(40, 40)
	slot.name = "QuickSlot%d" % index
	slot.focus_mode = Control.FOCUS_ALL
	slot.add_theme_stylebox_override("focus", UIStyles.create_focus_style())

	var style := StyleBoxFlat.new()
	style.bg_color = UIStyles.COLORS.background_dark
	style.border_color = UIStyles.COLORS.border
	slot.add_theme_stylebox_override("panel", style)

	return slot

func _create_progress_bar(color: Color) -> PanelContainer:
	var bar := PanelContainer.new()
	bar.custom_minimum_size = Vector2(150, 12)

	var style := StyleBoxFlat.new()
	style.bg_color = UIStyles.COLORS.background_dark
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("panel", style)

	# Fill
	var fill := Panel.new()
	fill.custom_minimum_size = Vector2(150, 12)
	fill.name = "Fill"

	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = color
	fill_style.corner_radius_top_left = 2
	fill_style.corner_radius_top_right = 2
	fill_style.corner_radius_bottom_left = 2
	fill_style.corner_radius_bottom_right = 2

	fill.add_theme_stylebox_override("panel", fill_style)
	bar.add_child(fill)

	return bar

func _connect_signals() -> void:
	# ChatService messages
	if ChatService:
		ChatService.message_received.connect(_on_chat_message_received)

## ============================================================================
## PUBLIC API
## ============================================================================

static func singleton() -> MenuManager:
	return instance

static func toggle_menu(menu_name: String) -> void:
	if instance:
		instance._toggle_menu_internal(menu_name)

static func open_menu(menu_name: String) -> void:
	if instance:
		instance._open_menu_internal(menu_name)

static func close_menu(menu_name: String) -> void:
	if instance:
		instance._close_menu_internal(menu_name)

static func get_open_panels() -> Array:
	if instance:
		return instance._open_panels.duplicate()
	return []

static func get_panel_node(panel_name: String) -> Control:
	if instance:
		return instance._get_panel(panel_name)
	return null

static func close_top_menu() -> void:
	if instance:
		instance._close_top_menu_internal()

## The back gesture (play-test round 8, item 13): Android system back,
## the web browser back bridge, and ESC all funnel here. One stack:
## close the top panel, then collapse the expanded menu bar, then ask
## before leaving the world for character select.
static func request_back() -> void:
	if instance:
		instance.request_back_internal()

static func close_all_menus() -> void:
	if instance:
		instance._close_all_menus_internal()

static func set_hud_visible(visible: bool) -> void:
	if instance:
		instance._set_hud_visible_internal(visible)

static func update_hp(current: int, maximum: int) -> void:
	if instance:
		instance._update_hp_internal(current, maximum)

static func update_mp(current: int, maximum: int) -> void:
	if instance:
		instance._update_mp_internal(current, maximum)

static func update_xp(current: int, maximum: int) -> void:
	if instance:
		instance._update_xp_internal(current, maximum)

## ============================================================================
## INTERNAL
## ============================================================================

func _toggle_menu_internal(menu_name: String) -> void:
	var panel := _get_panel(menu_name)
	if not panel:
		return

	if panel.visible:
		_close_panel(menu_name, panel)
	else:
		_open_panel(menu_name, panel)

func _open_menu_internal(menu_name: String) -> void:
	var panel := _get_panel(menu_name)
	if not panel:
		return

	if not _open_panels.has(menu_name):
		_open_panels.append(menu_name)
	_is_menu_open = true
	panel.visible = true
	menu_toggled.emit(menu_name, true)

func _close_menu_internal(menu_name: String) -> void:
	var panel := _get_panel(menu_name)
	if not panel:
		return

	_close_panel(menu_name, panel)

func _close_panel(menu_name: String, panel: Control) -> void:
	if _open_panels.has(menu_name):
		_open_panels.erase(menu_name)
	panel.visible = false
	if _open_panels.is_empty():
		_is_menu_open = false
		# Play-day feedback #3: the touch HUD yields while panels are
		# open; the last panel closing re-arms it.
		var im = get_node_or_null("/root/InputManager")
		if im != null and im.has_method("set_touch_hud_panels_open"):
			im.set_touch_hud_panels_open(false)
	menu_toggled.emit(menu_name, false)

func _open_panel(menu_name: String, panel: Control) -> void:
	if not _open_panels.has(menu_name):
		_open_panels.append(menu_name)
	_is_menu_open = true
	# Play-day feedback #3: the touch HUD must not capture input or
	# draw over panels. One funnel call covers every panel opener.
	var im_open = get_node_or_null("/root/InputManager")
	if im_open != null and im_open.has_method("set_touch_hud_panels_open"):
		im_open.set_touch_hud_panels_open(true)
	# Give UIPanel-derived panels their player context, and ALWAYS route
	# through open(): open() fires _on_open(), which is where most panels
	# refresh their content (faction list, achievement ledger, quest
	# log). The old pid != "" guard skipped open() in the guest/offline
	# flow (no PlayerManager character) -- panels then showed their
	# empty ready-time skeleton (play-day feedback #6). Panels already
	# defend against empty ids.
	var pid := _local_player_id()
	if "open" in panel:
		panel.open(pid)
	# Panels whose data source is the player's InventoryComponent fetch
	# it by id here; BlacksmithUI otherwise renders an empty repair list
	# (its _inventory is only set via the NPC-interaction path).
	if pid != "" and "set_inventory" in panel and panel.get("_inventory") == null:
		var inv_svc = get_node_or_null("/root/InventoryService")
		var comp = inv_svc.get_inventory(pid) if inv_svc and inv_svc.has_method("get_inventory") else null
		if comp:
			panel.set_inventory(comp)
	panel.visible = true
	menu_toggled.emit(menu_name, true)

func _local_player_id() -> String:
	var pm := get_node_or_null("/root/PlayerManager")
	if pm == null:
		return ""
	var local = pm.get("local_player")
	if local == null or not is_instance_valid(local):
		return ""
	var eid = local.get("entity_id")
	return String(eid) if eid != null else ""

func _close_top_menu_internal() -> void:
	if _open_panels.is_empty():
		return
	var top: String = _open_panels[-1]
	var panel: Control = _get_panel(top)
	if panel:
		_close_panel(top, panel)


## ---------- BACK STACK (play-test round 8, item 13) ----------
## One gesture, one law, three entry points: ESC (HudHotkeys), Android
## system back (NOTIFICATION_WM_GO_BACK_REQUEST below), and the web
## browser back bridge (installed in _ready, web builds only).
## Stack: topmost panel -> expanded menu bar -> exit confirm.

## The modal overlay (dim + centered box) while the exit question is
## up. Null when closed.
var _exit_confirm: Control = null
## JS callback object for the web popstate bridge (untyped: the
## JavaScriptObject type does not exist on non-web builds and a typed
## declaration would break desktop parsing).
var _web_back_cb = null

func request_back_internal() -> void:
	# 1) A live exit-confirm swallows the next back (dismiss it).
	if _exit_confirm != null and is_instance_valid(_exit_confirm):
		_hide_exit_confirm()
		return
	# 2) Topmost open panel closes first.
	if not _open_panels.is_empty():
		_close_top_menu_internal()
		return
	# 3) The expanded menu bar collapses before the exit question.
	var bar := _find_menu_bar()
	if bar != null and bar.get("_is_expanded") == true:
		if bar.has_method("hide_expanded"):
			bar.hide_expanded()
		return
	# 4) Nothing left to close: ask before leaving the world.
	_show_exit_confirm()

func _find_menu_bar() -> Node:
	var bar := get_node_or_null("MainMenuBar")
	if bar != null:
		return bar
	return find_child("MainMenuBar", true, false)

func _show_exit_confirm() -> void:
	if _exit_confirm != null and is_instance_valid(_exit_confirm):
		return
	# Modal dim; ColorRect's default mouse filter blocks the game
	# behind it. CenterContainer does the centering (never hand-place a
	# center-anchored box -- the frozen-offsets trap from round 7).
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.grow_horizontal = Control.GROW_DIRECTION_BOTH
	dim.grow_vertical = Control.GROW_DIRECTION_BOTH
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center.grow_vertical = Control.GROW_DIRECTION_BOTH
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(520, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	var title := Label.new()
	title.text = "Leave the world?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	var body := Label.new()
	body.text = "Exit to the character select screen? Your progress stays saved."
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 16)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	var stay := Button.new()
	stay.text = "Keep Playing"
	stay.custom_minimum_size = Vector2(200, 54)
	stay.add_theme_font_size_override("font_size", 19)
	var leave := Button.new()
	leave.text = "Exit"
	leave.custom_minimum_size = Vector2(150, 54)
	leave.add_theme_font_size_override("font_size", 19)
	buttons.add_child(stay)
	buttons.add_child(leave)
	v.add_child(title)
	v.add_child(body)
	v.add_child(buttons)
	margin.add_child(v)
	box.add_child(margin)
	center.add_child(box)
	dim.add_child(center)
	add_child(dim)
	_exit_confirm = dim
	stay.pressed.connect(_hide_exit_confirm)
	leave.pressed.connect(_exit_to_character_select)

func _hide_exit_confirm() -> void:
	if _exit_confirm != null and is_instance_valid(_exit_confirm):
		_exit_confirm.queue_free()
	_exit_confirm = null

func _exit_to_character_select() -> void:
	_hide_exit_confirm()
	var gm = get_node_or_null("/root/GameManager")
	if gm != null and gm.has_method("change_state"):
		gm.change_state(gm.GameState.CHARACTER_SELECT)

func _notification(what: int) -> void:
	# Android system back (native builds): same stack as ESC/web back.
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		request_back_internal()

## Install the web back bridge: browser back pops history and would
## LEAVE the game. Push a sentinel history entry at HUD install; every
## popstate re-pushes it and fires request_back_internal() instead.
## Web-only and defensive: JavaScriptBridge is absent on other builds,
## so this resolves it through Engine (never a bare identifier -- that
## broke script-mode parsing before).
func _install_web_back_bridge() -> void:
	if _web_back_cb != null:
		return
	if not Engine.has_singleton("JavaScriptBridge"):
		return
	var js = Engine.get_singleton("JavaScriptBridge")
	if js == null or not js.has_method("create_callback"):
		return
	_web_back_cb = js.create_callback(_on_web_back)
	var win = js.get_interface("window")
	if win == null:
		_web_back_cb = null
		return
	win.synmergiaBackCallback = _web_back_cb
	js.eval("""
		if (!window.synmergiaBackInstalled) {
			window.synmergiaBackInstalled = true;
			history.pushState({synmergia: 1}, '');
			window.addEventListener('popstate', function () {
				history.pushState({synmergia: 1}, '');
				if (window.synmergiaBackCallback) {
					window.synmergiaBackCallback();
				}
			});
		}
	""", true)

func _on_web_back(_args: Array) -> void:
	request_back_internal()

## ---------- END BACK STACK ----------

func _close_all_menus_internal() -> void:
	for panel_name in _open_panels:
		var panel := _get_panel(panel_name)
		if panel:
			panel.visible = false
		menu_toggled.emit(panel_name, false)
	_open_panels.clear()
	_is_menu_open = false

func _get_panel(menu_name: String) -> Control:
	match menu_name:
		"inventory": return _inventory_panel
		"character": return _character_panel
		"guild": return _guild_panel
		"party": return _party_panel
		"friends": return _friends_panel
		"chat": return _chat_panel
		"quests": return _quest_panel
		"bank": return _bank_panel
		"blacksmith": return _blacksmith_panel
		"skill_academy": return _skill_academy_panel
		"faction": return _faction_panel
		"achievement": return _achievement_panel
		"titles": return _title_panel
		"transfer": return _transfer_panel
		"trade": return _trade_panel
		"sky_almanac": return _sky_almanac_panel
		"chronicle": return _chronicle_panel
		"lobby": return _lobby_panel
		"dialog": return _dialog_panel
		"shop": return _shop_panel
		"admin": return _admin_panel
		"debug": return _debug_panel
	return null

func _set_hud_visible_internal(visible: bool) -> void:
	_is_hud_visible = visible
	_action_bar.visible = visible
	_quick_access_bar.visible = visible
	_buff_bar.visible = visible
	_status_bar.visible = visible
	hud_visibility_changed.emit(visible)

func _update_hp_internal(current: int, maximum: int) -> void:
	_update_bar("HPBar", current, maximum, UIStyles.COLORS.error)

func _update_mp_internal(current: int, maximum: int) -> void:
	_update_bar("MPBar", current, maximum, UIStyles.COLORS.info)

func _update_xp_internal(current: int, maximum: int) -> void:
	_update_bar("XPBar", current, maximum, UIStyles.COLORS.accent_gold)

func _update_bar(bar_name: String, current: int, maximum: int, color: Color) -> void:
	var bar: PanelContainer = _status_bar.get_node_or_null(bar_name)
	if not bar:
		return

	var fill: Panel = bar.get_node_or_null("Fill")
	if not fill:
		return

	var ratio := float(current) / float(maximum) if maximum > 0 else 0.0
	var bar_width := 150.0 * ratio

	fill.custom_minimum_size.x = bar_width

	var style := fill.get_theme_stylebox("panel")
	if style:
		style.bg_color = color

func _on_chat_message_received(sender_id: String, channel: int, message: String, targets: Array) -> void:
	if _chat_panel and _chat_panel.has_method("add_message"):
		_chat_panel.add_message(sender_id, channel, message)

func _on_main_menu_panel_requested(panel_id: String) -> void:
	# Map main menu panel IDs to internal panel names
	var panel_map := {
		"inventory": "inventory",
		"character": "character",
		"skills": "skill_academy",
		"guild": "guild",
		"party": "party",
		"friends": "friends",
		"quests": "quests",
		"bank": "bank",
		"blacksmith": "blacksmith",
		"world_map": "world_map",
		"faction": "faction",
		"achievements": "achievement",
		"titles": "titles",
		"trade": "trade",
		"transfer": "transfer",
		"settings": "settings",
		"admin": "admin",
		"debug": "debug",
	}
	
	var internal_name: String = panel_map.get(panel_id, panel_id)
	
	# Special handling for settings (handled by HudLayer)
	if internal_name == "settings":
		if HudLayerScript.instance and HudLayerScript.instance.has_method("open_settings"):
			HudLayerScript.instance.open_settings()
		return
	
	# Special handling for world_map (handled by HudLayer)
	if internal_name == "world_map":
		if HudLayerScript.instance and HudLayerScript.instance.has_method("_toggle_world_map"):
			HudLayerScript.instance._toggle_world_map()
		return
	
	# Trade panel: the menu-item and R hotkey both route here now. With
	# no active session the panel shows its idle state ("no trade in
	# progress"); HudServices populates it when TradeService starts one.
	# (The old code silently no-oped here.)
	
	# Permission check for admin panel
	if internal_name == "admin":
		if not PermissionManager:
			NotificationService.notify(NotifKind.SECURITY_WARNING, "Admin panel unavailable", "MenuManager", "admin_unavail", {})
			return
		var player_id := ""
		if GameManager and GameManager.selected_character_data:
			player_id = GameManager.selected_character_data.id
		if not PermissionManager.has_permission(player_id, PermissionManager.Level.MOD):
			NotificationService.notify(NotifKind.SECURITY_WARNING, "Insufficient permissions for Admin Panel", "MenuManager", "admin_perm", {}, player_id)
			return
	
	# Permission check for debug panel
	if internal_name == "debug":
		if not PermissionManager:
			NotificationService.notify(NotifKind.SECURITY_WARNING, "Debug panel unavailable", "MenuManager", "debug_unavail", {})
			return
		var player_id := ""
		if GameManager and GameManager.selected_character_data:
			player_id = GameManager.selected_character_data.id
		var is_admin := PermissionManager.has_permission(player_id, PermissionManager.Level.ADMIN)
		var is_dev := GameConfig and GameConfig.Debug.ALLOW_CHEATS
		if not is_admin and not is_dev:
			NotificationService.notify(NotifKind.SECURITY_WARNING, "Insufficient permissions for Debug Panel", "MenuManager", "debug_perm", {}, player_id)
			return
	
	_toggle_menu_internal(internal_name)

func _input(event: InputEvent) -> void:
	# NOTE: Panel hotkeys (I, C, P, G, F, Q, ESC) are handled by HudHotkeys.
	# This only handles chat-specific input.
	if event is InputEventKey and event.pressed and event.keycode == KEY_ENTER:
		if _chat_panel and _chat_panel.has_method("focus_input"):
			_chat_panel.focus_input()

func _create_debug_panel() -> Control:
	"""Create a debug panel with developer tools."""
	var DebugPanelScript := preload("res://ui/components/ui_panel.gd")
	var panel: Control = DebugPanelScript.new()
	panel.set_panel_title("Debug Panel")
	panel.custom_minimum_size = Vector2(600, 400)
	
	# Build the debug UI after the panel is in the scene tree.
	# NOTE: the builder lives on MenuManager and must receive the panel
	# explicitly -- it used to be deferred onto the panel itself, which
	# has no such method ("Error calling deferred method ... Method not
	# found" at full boot).
	call_deferred("_debug_build_panel_ui", panel, self)
	
	return panel

func _debug_build_panel_ui(panel: Control, menu_manager: MenuManager) -> void:
	# The UIPanel creates a "Panel" child in _setup_overlay().
	# Resolve it on the panel, not on self (MenuManager).
	var panel_container: PanelContainer = panel.get_node_or_null("Panel")
	if not panel_container:
		return
	
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 8)
	panel_container.add_child(vbox)
	
	# Tab container for different debug sections
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(tabs)
	
	# System Info tab
	var sys_tab := VBoxContainer.new()
	sys_tab.add_theme_constant_override("separation", 8)
	tabs.add_child(sys_tab)
	tabs.set_tab_title(tabs.get_child_count() - 1, " System")
	
	var sys_info := Label.new()
	sys_info.name = "sys_info_label"
	menu_manager._update_debug_sys_info(sys_info)
	sys_info.add_theme_font_size_override("font_size", 12)
	sys_info.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	sys_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	sys_info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sys_tab.add_child(sys_info)
	
	# Add refresh button for system info
	var refresh_btn := Button.new()
	refresh_btn.text = "Refresh System Info"
	refresh_btn.custom_minimum_size.y = 36
	refresh_btn.pressed.connect(func(): menu_manager._update_debug_sys_info(sys_info))
	refresh_btn.focus_mode = Control.FOCUS_ALL
	refresh_btn.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
	sys_tab.add_child(refresh_btn)
	
	# Network tab
	var net_tab := VBoxContainer.new()
	net_tab.add_theme_constant_override("separation", 8)
	tabs.add_child(net_tab)
	tabs.set_tab_title(tabs.get_child_count() - 1, " Network")
	
	var net_info := Label.new()
	net_info.name = "net_info_label"
	menu_manager._update_debug_net_info(net_info)
	net_info.add_theme_font_size_override("font_size", 12)
	net_info.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	net_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	net_info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	net_tab.add_child(net_info)
	
	var net_refresh_btn := Button.new()
	net_refresh_btn.text = "Refresh Network Info"
	net_refresh_btn.custom_minimum_size.y = 36
	net_refresh_btn.pressed.connect(func(): menu_manager._update_debug_net_info(net_info))
	net_refresh_btn.focus_mode = Control.FOCUS_ALL
	net_refresh_btn.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
	net_tab.add_child(net_refresh_btn)
	
	# Performance tab
	var perf_tab := VBoxContainer.new()
	perf_tab.add_theme_constant_override("separation", 8)
	tabs.add_child(perf_tab)
	tabs.set_tab_title(tabs.get_child_count() - 1, " Performance")
	
	var perf_info := Label.new()
	perf_info.name = "perf_info_label"
	menu_manager._update_debug_perf_info(perf_info)
	perf_info.add_theme_font_size_override("font_size", 12)
	perf_info.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	perf_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	perf_info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	perf_tab.add_child(perf_info)
	
	var perf_refresh_btn := Button.new()
	perf_refresh_btn.text = "Refresh Performance"
	perf_refresh_btn.custom_minimum_size.y = 36
	perf_refresh_btn.pressed.connect(func(): menu_manager._update_debug_perf_info(perf_info))
	perf_refresh_btn.focus_mode = Control.FOCUS_ALL
	perf_refresh_btn.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
	perf_tab.add_child(perf_refresh_btn)
	
	# Entity Debug tab
	var entity_tab := VBoxContainer.new()
	entity_tab.add_theme_constant_override("separation", 8)
	tabs.add_child(entity_tab)
	tabs.set_tab_title(tabs.get_child_count() - 1, " Entities")
	
	var entity_info := Label.new()
	entity_info.name = "entity_info_label"
	menu_manager._update_debug_entity_info(entity_info)
	entity_info.add_theme_font_size_override("font_size", 12)
	entity_info.add_theme_color_override("font_color", UIStyles.COLORS.text_secondary)
	entity_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	entity_info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	entity_tab.add_child(entity_info)
	
	var entity_refresh_btn := Button.new()
	entity_refresh_btn.text = "Refresh Entity Info"
	entity_refresh_btn.custom_minimum_size.y = 36
	entity_refresh_btn.pressed.connect(func(): menu_manager._update_debug_entity_info(entity_info))
	entity_refresh_btn.focus_mode = Control.FOCUS_ALL
	entity_refresh_btn.add_theme_stylebox_override("focus", UIStyles.create_focus_style())
	entity_tab.add_child(entity_refresh_btn)

func _update_debug_sys_info(label: Label) -> void:
	var fps: float = Performance.get_monitor(Performance.TIME_FPS)
	label.text = "Godot Version: %s\nFPS: %d\nFrame Time: %.2f ms\nObjects: %d" % [
		Engine.get_version_info()["string"],
		fps,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Engine.get_physics_frames()
	]

func _update_debug_net_info(label: Label) -> void:
	label.text = "NetworkManager: %s\nQoSService: %s\nPeers: %d" % [
		"Loaded" if NetworkManager else "Not Loaded",
		"Loaded" if get_tree().root.get_node_or_null("QoSService") else "Not Loaded",
		NetworkManager.get_peer_count() if NetworkManager and NetworkManager.has_method("get_peer_count") else 0
	]

func _update_debug_perf_info(label: Label) -> void:
	label.text = "Use Profiler for detailed metrics\n\nFrame Time: %.2f ms\nPhysics Time: %.2f ms\nScript Time: %.2f ms" % [
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	]

func _update_debug_entity_info(label: Label) -> void:
	label.text = "EntityService: %s\nEntities: %d" % [
		"Loaded" if EntityService else "Not Loaded",
		EntityService.get_entity_count() if EntityService and EntityService.has_method("get_entity_count") else 0
	]
