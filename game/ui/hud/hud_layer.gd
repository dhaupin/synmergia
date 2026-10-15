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
## Runtime autoload lookup (script-mode-safe; the bare identifier
## fails compile when autoloads are absent -- test_islands).
func _perm_svc() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("PermissionManager")) if tree and tree.root else null

func _gcfg() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("GameConfig")) if tree and tree.root else null

func _pm() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("PlayerManager")) if tree and tree.root else null

func _gm() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("GameManager")) if tree and tree.root else null


const CharacterData := preload("res://core/schemas/character_data.gd")

const LAYER_HUD: int = 10

static var instance: CanvasLayer = null

## Tree-safe GameLog lookup (script-mode-safe; the bare identifier
## fails compile when autoloads are absent -- test_islands).
static func _glog() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("GameLog")) if tree and tree.root else null

func _event_hub() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(NodePath("EventHub")) if tree and tree.root else null

## THE one playable-HUD init (feedback #5): every playable scene calls
## HudLayer.ensure_installed(scene_root) and gets the same composition
## -- hud_layer.tscn (menus, bars, chat, minimap) plus the touch HUD
## bridged to the player's camera when it exposes orbit_camera. Scenes
## that embed hud_layer.tscn directly (world_playable.tscn) need
## nothing; the touch-HUD half of this contract is the InputManager's
## gameplay-state gate, so menus never show controls. Idempotent.
static func ensure_installed(scene_root: Node) -> void:
	if instance != null and is_instance_valid(instance) and instance.is_inside_tree():
		return
	if scene_root.get_node_or_null("HudLayer") != null:
		return
	var packed: PackedScene = load("res://ui/hud/hud_layer.tscn")
	if packed == null:
		var gl := _glog()
		if gl:
			gl.warn("HudLayer: hud_layer.tscn missing; HUD disabled")
		return
	var hud: CanvasLayer = packed.instantiate()
	hud.name = "HudLayer"
	scene_root.add_child(hud)
	var gl_ok := _glog()
	if gl_ok:
		gl_ok.info("HudLayer: installed on %s (single playable-HUD init)" % scene_root.name)

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
	_install_storm_bar()
	_install_integrator()
	_setup_main_menu_bar()

func _setup_accessibility() -> void:
	# CanvasLayer doesn't have accessibility properties; skip
	# Connect to accessibility setting changes from SettingsPanel
	var hub := _event_hub()
	if hub:
		hub.connect("accessibility_text_scale_changed", _on_text_scale_changed)
		hub.connect("accessibility_reduce_motion_changed", _on_reduce_motion_changed)
		hub.connect("accessibility_high_contrast_changed", _on_high_contrast_changed)

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
	# Sky totem: aurora-window display (weather events). Same optional-
	# at-runtime convention; created right under the horde bar slot.
	var SkyTotemScript := load("res://ui/components/sky_totem.gd")
	if SkyTotemScript:
		var totem: Control = SkyTotemScript.new()
		totem.name = "SkyTotem"
		add_child(totem)


## Installs the StormBar widget (S13 ROYALE fog-wall display), same
## optional-at-runtime convention as HordeBar.
func _install_storm_bar() -> void:
	var StormBarScript := load("res://ui/components/storm_bar.gd")
	if not StormBarScript:
		return
	var storm_bar: Control = StormBarScript.new()
	storm_bar.name = "StormBar"
	add_child(storm_bar)


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

	# Connect to _perm_svc() for admin/debug visibility updates
	if _perm_svc():
		_perm_svc().admin_action.connect(_on_admin_action)

func _on_admin_action(entry) -> void:
	# Update admin/debug visibility in main menu bar when permissions change
	if _main_menu_bar and _main_menu_bar.has_method("update_admin_debug_visibility"):
		var is_admin_or_mod := _is_moderator_or_admin()
		var is_dev_mode: bool = _is_admin() or _gcfg() != null
		_main_menu_bar.update_admin_debug_visibility(is_admin_or_mod, is_dev_mode)

func _is_moderator_or_admin() -> bool:
	if not _perm_svc():
		return false
	var player_id: String = "local"
	if _pm() and "character_name" in _pm():
		player_id = _pm().character_name
	if _gm() and _gm().selected_character_data:
		player_id = _gm().selected_character_data.id
	return _perm_svc().has_permission(player_id, _perm_svc().Level.MOD)

func _on_panel_closed() -> void:
	# Handle panel close - could update some state if needed
	pass


func _bind_to_world() -> void:
	if _gm():
		_gm().game_state_changed.connect(_on_state_changed)
		visible = _gm().is_gameplay_active()
		_push_character_to_widgets()


func _push_character_to_widgets() -> void:
	var data: Resource = _gm().selected_character_data
	if not (data is CharacterData):
		return
	if _action_bar and _action_bar.has_method("set_player_name"):
		_action_bar.set_player_name(data.display_name)


func _on_state_changed(_state: int) -> void:
	var gm_h := _gm()
	if gm_h == null:
		return
	var st: int = gm_h.get_state()
	visible = st == gm_h.GameState.PLAYING or st == gm_h.GameState.PAUSED


func _setup_main_menu_bar() -> void:
	if _main_menu_bar and _main_menu_bar.has_method("bind"):
		_main_menu_bar.bind(self, _menu_manager)

	# Update character info when available
	if _gm() and _gm().selected_character_data:
		_push_character_to_main_menu()


func _push_character_to_main_menu() -> void:
	if not _main_menu_bar or not _main_menu_bar.has_method("update_character_info"):
		return
	var data: Resource = _gm().selected_character_data
	if not (data is CharacterData):
		return

	# Class icon: a SHORT badge glyph, never a res:// path. The raw
	# icon_path used to be passed through and rendered as literal text
	# ("res://ui/icons...") across the HUD's top-left on the web build
	# (feedback #4). Class .tres icon_path values are filesystem paths,
	# so they are deliberately not forwarded.
	var class_icon := "[C]"  # Default fallback

	_main_menu_bar.update_character_info(data.display_name, data.level, class_icon)


func _toggle_world_map() -> void:
	if instance and instance.has_node("WorldMap"):
		var world_map: Node = instance.get_node("WorldMap")
		if world_map and world_map.has_method("toggle"):
			world_map.toggle()


func _is_admin() -> bool:
	if not _perm_svc():
		return false
	# In single-player / dev mode the local player IS the admin.
	var player_id: String = "local"
	if _pm() and "character_name" in _pm():
		player_id = _pm().character_name
	return _perm_svc().has_permission(player_id, _gcfg().Security.ADMIN_LEVEL) if _gcfg() else false


func open_settings() -> void:
	# THE ONE FUNNEL LAW: settings registers with MenuManager's panel
	# registry (back-stack law), so open/close go through open_menu/
	# close_menu -- the registry, the touch-HUD yield, the Back button,
	# and ESC-while-settings-open all stay coherent. Direct fallback
	# kept for the bare position (no MenuManager instance yet).
	var mm = get_node_or_null("/root/MenuManager")
	if mm == null:
		var MenuManagerScript = load("res://ui/components/menu_manager.gd")
		mm = MenuManagerScript.instance if MenuManagerScript != null else null
	if mm != null and mm.has_method("open_menu") and mm.get_panel_node("settings") != null:
		mm.open_menu("settings")
		return
	var panel := _resolve_settings_panel()
	if panel != null:
		# Prefer the UIPanel lifecycle (keeps _is_open in sync so the
		# hotkey toggle and the header X stay coherent) and fall back to
		# a bare visibility flip for non-UIPanel shapes.
		if panel.has_method("open"):
			panel.open("")
		else:
			panel.visible = true


func close_settings() -> void:
	var mm = get_node_or_null("/root/MenuManager")
	if mm == null:
		var MenuManagerScript = load("res://ui/components/menu_manager.gd")
		mm = MenuManagerScript.instance if MenuManagerScript != null else null
	if mm != null and mm.has_method("close_menu") and mm.get_panel_node("settings") != null:
		mm.close_menu("settings")
		return
	var panel := _resolve_settings_panel()
	if panel != null:
		if panel.has_method("close"):
			panel.close()
		else:
			panel.visible = false


## The settings panel re-parents into MenuManager's layer at ready
## (z-stack law: it must render above the touch HUD + menu widgets).
## Resolve by node NAME wherever it now lives: direct HUD child first,
## then through MenuManager's static instance (the post-adoption home).
func _resolve_settings_panel() -> Node:
	if instance == null:
		return null
	if instance.has_node("SettingsPanel"):
		return instance.get_node("SettingsPanel")
	var MenuManagerScript = load("res://ui/components/menu_manager.gd")
	if MenuManagerScript != null and MenuManagerScript.instance != null:
		var found = MenuManagerScript.instance.get_node_or_null("SettingsPanel")
		if found != null:
			return found
	return null


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
