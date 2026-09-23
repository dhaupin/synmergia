## HudLayer - Top-level CanvasLayer that hosts every in-world HUD widget.
## Instantiated as a child of the playable world scene.
##
## Composition (all created at runtime; no manual scene editing required):
##   - MenuManager (CanvasLayer; owns all panels + slot rows)
##   - ActionBar, QuickAccessBar, BuffBar (HUD widgets)
##   - CombatLog (right side, scrollable)
##   - TargetFrame, BossHealthBar (combat feedback)
##   - Minimap + WorldMap (top-right corner; click expands)
##   - DialogUI (NPC dialog)
##   - SettingsPanel (Esc; toggled by MenuManager)
##   - AdminToolbar (F3; visible to admins only)
##
## All children are added under a single CanvasLayer so they render above
## the 3D world and below any full-screen menu.
extends CanvasLayer
class_name HudLayer

const CharacterData := preload("res://core/schemas/character_data.gd")

const LAYER_HUD: int = 10

static var instance: CanvasLayer = null

## All widget children are optional; missing widgets just disable their
## own panel. We look them up by name and skip wiring if absent.
@onready var _menu_manager: Node = _find("MenuManager")
@onready var _action_bar: Node = _find("ActionBar")
@onready var _quick_access_bar: Node = _find("QuickAccessBar")
@onready var _buff_bar: Node = _find("BuffBar")
@onready var _combat_log: Node = _find("CombatLog")
@onready var _target_frame: Node = _find("TargetFrame")
@onready var _boss_health_bar: Node = _find("BossHealthBar")
@onready var _minimap: Node = _find("Minimap")
@onready var _world_map: Node = _find("WorldMap")
@onready var _dialog_ui: Node = _find("DialogUI")
@onready var _settings_panel: Node = _find("SettingsPanel")
@onready var _admin_toolbar: Node = _find("AdminToolbar")
@onready var _faction_ui: Node = _find("FactionUI")
@onready var _achievement_ui: Node = _find("AchievementUI")
@onready var _shop_ui: Node = _find("ShopUI")
@onready var _main_menu_bar: Node = _find("MainMenuBar")


func _ready() -> void:
	if instance == null:
		instance = self
	else:
		queue_free()
		return
	
	layer = LAYER_HUD
	_setup_accessibility()
	_wire_widgets()
	_bind_to_world()
	_install_horde_bar()
	_install_integrator()
	_setup_main_menu_bar()

func _setup_accessibility() -> void:
	# CanvasLayer doesn't have accessibility properties; skip
	# Connect to accessibility setting changes from SettingsPanel
	if EventHub:
		EventHub.connect("accessibility_text_scale_changed", _on_text_scale_changed)
		EventHub.connect("accessibility_reduce_motion_changed", _on_reduce_motion_changed)
		EventHub.connect("accessibility_high_contrast_changed", _on_high_contrast_changed)

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


## Installs the HordeBar widget (horde/wave encounter display). Lives
## outside the .tscn so the widget is optional at runtime.
func _install_horde_bar() -> void:
	var HordeBarScript := load("res://ui/components/horde_bar.gd")
	if not HordeBarScript:
		return
	var horde_bar: Control = HordeBarScript.new()
	horde_bar.name = "HordeBar"
	add_child(horde_bar)


func _install_integrator() -> void:
	var IntegratorScript := load("res://ui/hud/hud_integrator.gd")
	if not IntegratorScript:
		return
	var integrator: Node = IntegratorScript.new()
	integrator.name = "HudIntegrator"
	add_child(integrator)
	integrator.bind(self)
	_install_respawn_ui()
	_install_services()


func _install_respawn_ui() -> void:
	var RespawnScript := load("res://ui/respawn/respawn_ui_manager.gd")
	if not RespawnScript:
		return
	var respawn_ui: Node = RespawnScript.new()
	respawn_ui.name = "RespawnUIManager"
	add_child(respawn_ui)


func _install_services() -> void:
	var ServicesScript := load("res://ui/hud/hud_services.gd")
	if not ServicesScript:
		return
	var services: Node = ServicesScript.new()
	services.name = "HudServices"
	add_child(services)
	services.bind(self)
	_install_hotkeys()


func _install_hotkeys() -> void:
	var HotkeyScript := load("res://ui/hud/hud_hotkeys.gd")
	if not HotkeyScript:
		return
	var hotkeys: Node = HotkeyScript.new()
	hotkeys.name = "HudHotkeys"
	add_child(hotkeys)
	hotkeys.bind(self)


func _find(node_name: String) -> Node:
	return get_node_or_null(NodePath(node_name))


func _wire_widgets() -> void:
	if _combat_log and _combat_log.has_method("clear"):
		_combat_log.clear()
	if _settings_panel:
		_settings_panel.visible = false
	if _dialog_ui:
		_dialog_ui.visible = false
		if _dialog_ui.has_signal("dialog_finished"):
			_dialog_ui.dialog_finished.connect(func(_id): _dialog_ui.visible = false)
	if _boss_health_bar:
		_boss_health_bar.visible = false
	if _admin_toolbar:
		_admin_toolbar.visible = _is_admin()
	if _faction_ui:
		_faction_ui.visible = false
		if _faction_ui.has_signal("panel_closed"):
			_faction_ui.panel_closed.connect(_on_panel_closed)
	if _achievement_ui:
		_achievement_ui.visible = false
		if _achievement_ui.has_signal("panel_closed"):
			_achievement_ui.panel_closed.connect(_on_panel_closed)
	if _shop_ui:
		_shop_ui.visible = false
		if _shop_ui.has_signal("panel_closed"):
			_shop_ui.panel_closed.connect(_on_panel_closed)
	if _world_map and _minimap:
		if _minimap.has_signal("map_button_pressed"):
			_minimap.map_button_pressed.connect(_toggle_world_map)

	# Connect to PermissionManager for admin/debug visibility updates
	if PermissionManager:
		PermissionManager.admin_action.connect(_on_admin_action)

func _on_admin_action(entry) -> void:
	# Update admin/debug visibility in main menu bar when permissions change
	if _main_menu_bar and _main_menu_bar.has_method("update_admin_debug_visibility"):
		var is_admin_or_mod := _is_moderator_or_admin()
		var is_dev_mode := _is_admin() or (GameConfig and GameConfig.Debug.ALLOW_CHEATS)
		_main_menu_bar.update_admin_debug_visibility(is_admin_or_mod, is_dev_mode)

func _is_moderator_or_admin() -> bool:
	if not PermissionManager:
		return false
	var player_id: String = "local"
	if PlayerManager and "character_name" in PlayerManager:
		player_id = PlayerManager.character_name
	if GameManager and GameManager.selected_character_data:
		player_id = GameManager.selected_character_data.id
	return PermissionManager.has_permission(player_id, PermissionManager.Level.MOD)

func _on_panel_closed() -> void:
	# Handle panel close - could update some state if needed
	pass


func _bind_to_world() -> void:
	if GameManager:
		GameManager.game_state_changed.connect(_on_state_changed)
		visible = GameManager.is_gameplay_active()
		_push_character_to_widgets()


func _push_character_to_widgets() -> void:
	var data: Resource = GameManager.selected_character_data
	if not (data is CharacterData):
		return
	if _action_bar and _action_bar.has_method("set_player_name"):
		_action_bar.set_player_name(data.display_name)


func _on_state_changed(_state: int) -> void:
	var st := GameManager.get_state()
	visible = st == GameManager.GameState.PLAYING or st == GameManager.GameState.PAUSED


func _setup_main_menu_bar() -> void:
	if _main_menu_bar and _main_menu_bar.has_method("bind"):
		_main_menu_bar.bind(self, _menu_manager)
	
	# Update character info when available
	if GameManager and GameManager.selected_character_data:
		_push_character_to_main_menu()


func _push_character_to_main_menu() -> void:
	if not _main_menu_bar or not _main_menu_bar.has_method("update_character_info"):
		return
	var data: Resource = GameManager.selected_character_data
	if not (data is CharacterData):
		return
	
	# Get class icon from CharacterClass data
	var class_icon := "Sword"  # Default fallback
	if DataService:
		var class_data := DataService.get_character_class(data.class_id)
		if class_data and class_data.icon_path and not class_data.icon_path.is_empty():
			class_icon = class_data.icon_path
	
	_main_menu_bar.update_character_info(data.display_name, data.level, class_icon)


func _toggle_world_map() -> void:
	if instance and instance.has_node("WorldMap"):
		var world_map: Node = instance.get_node("WorldMap")
		if world_map and world_map.has_method("toggle"):
			world_map.toggle()


func _is_admin() -> bool:
	if not PermissionManager:
		return false
	# In single-player / dev mode the local player IS the admin.
	var player_id: String = "local"
	if PlayerManager and "character_name" in PlayerManager:
		player_id = PlayerManager.character_name
	return PermissionManager.has_permission(player_id, GameConfig.Security.ADMIN_LEVEL) if GameConfig else false


func open_settings() -> void:
	if instance and instance.has_node("SettingsPanel"):
		var panel: Node = instance.get_node("SettingsPanel")
		if panel:
			panel.visible = true


func close_settings() -> void:
	if instance and instance.has_node("SettingsPanel"):
		var panel: Node = instance.get_node("SettingsPanel")
		if panel:
			panel.visible = false


func show_dialog(dialogue_id: String, npc_id: String = "") -> void:
	if instance and instance.has_node("DialogUI"):
		var dialog_ui: Node = instance.get_node("DialogUI")
		if dialog_ui:
			dialog_ui.visible = true
			if dialog_ui.has_method("show_dialog"):
				dialog_ui.show_dialog(npc_id, dialogue_id)
			elif dialog_ui.has_method("start_dialogue"):
				dialog_ui.start_dialogue(dialogue_id, npc_id)


func show_faction_ui() -> void:
	if instance and instance.has_node("FactionUI"):
		var ui: Node = instance.get_node("FactionUI")
		if ui:
			if ui.has_method("open"):
				ui.open()
			else:
				ui.visible = true


func show_achievement_ui() -> void:
	if instance and instance.has_node("AchievementUI"):
		var ui: Node = instance.get_node("AchievementUI")
		if ui:
			if ui.has_method("open"):
				ui.open()
			else:
				ui.visible = true


func show_shop_ui() -> void:
	if instance and instance.has_node("ShopUI"):
		var ui: Node = instance.get_node("ShopUI")
		if ui:
			if ui.has_method("open"):
				ui.open()
			else:
				ui.visible = true
