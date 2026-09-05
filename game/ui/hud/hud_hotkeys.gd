## HudHotkeys - Single authority for all HUD panel keybinds.
##
## All HUD keypresses are handled here and routed to MenuManager.
## No InputManager dependency — listens to raw key events directly.
## Esc closes the topmost panel. Other keys toggle specific panels.
##
## Keymap:
##   ESC  → close topmost panel
##   I    → inventory
##   C    → character panel
##   P    → party
##   G    → guild
##   F    → friends
##   Q    → quests
##   B    → bank/vault
##   K    → skill academy
##   H    → blacksmith
##   M    → world map
##   O    → settings/options
##   J    → jump (reserved for future)
##   ENTER → focus chat input (MenuManager handles this)
extends Node

var _hud: CanvasLayer
var _mm: Node
var _admin_toolbar: Node
var _world_map: Node
var _chat: Node


func bind(hud: CanvasLayer) -> void:
	_hud = hud
	_mm = hud.get_node_or_null("MenuManager")
	_admin_toolbar = hud.get_node_or_null("AdminToolbar")
	_world_map = hud.get_node_or_null("WorldMap")
	_chat = hud.get_node_or_null("ChatUI")
	set_process_unhandled_input(true)


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var k: InputEventKey = event
	if not k.pressed or k.echo:
		return
	var keycode: int = k.physical_keycode
	if keycode == 0:
		keycode = k.keycode

	match keycode:
		KEY_ESCAPE:
			_handle_escape()
			get_viewport().set_input_as_handled()
		KEY_I:
			_toggle_panel("inventory")
			get_viewport().set_input_as_handled()
		KEY_C:
			_toggle_panel("character")
			get_viewport().set_input_as_handled()
		KEY_P:
			_toggle_panel("party")
			get_viewport().set_input_as_handled()
		KEY_G:
			_toggle_panel("guild")
			get_viewport().set_input_as_handled()
		KEY_F:
			_toggle_panel("friends")
			get_viewport().set_input_as_handled()
		KEY_Q:
			_toggle_panel("quests")
			get_viewport().set_input_as_handled()
		KEY_B:
			_toggle_panel("bank")
			get_viewport().set_input_as_handled()
		KEY_K:
			_toggle_panel("skill_academy")
			get_viewport().set_input_as_handled()
		KEY_H:
			_toggle_panel("blacksmith")
			get_viewport().set_input_as_handled()
		KEY_M:
			_toggle_world_map()
			get_viewport().set_input_as_handled()
		KEY_O:
			_toggle_settings()
			get_viewport().set_input_as_handled()
		KEY_TAB:
			_handle_tab_cycling(k.shift_pressed)
			get_viewport().set_input_as_handled()


func _handle_tab_cycling(shift: bool) -> void:
	# If any panel is open, delegate Tab to the panel for focus cycling
	if _mm and _mm.has_method("get_open_panels"):
		var open_panels: Array = _mm.get_open_panels()
		if not open_panels.is_empty():
			var top: String = open_panels[-1]
			var panel_node: Node = _mm.get_panel_node(top)
			if panel_node and panel_node.has_method("_on_tab_pressed"):
				panel_node._on_tab_pressed(shift)
			return
	# No panel open → cycle targets
	if TargetingManager and TargetingManager.has_method("cycle_target"):
		TargetingManager.cycle_target(shift)


func _handle_escape() -> void:
	if not _mm:
		return
	if _mm.has_method("close_top_menu"):
		_mm.close_top_menu()
	elif _mm.has_method("close_all_menus"):
		_mm.close_all_menus()


func _toggle_panel(panel_id: String) -> void:
	if not _mm:
		return
	if _mm.has_method("toggle_menu"):
		_mm.toggle_menu(panel_id)
	elif _mm.has_method("open_menu") and _mm.has_method("close_menu"):
		# Manual toggle if toggle_menu not available
		if _mm.has_method("get_instance"):
			var inst = _mm.get_instance()
			if inst and inst.has_method("is_panel_open"):
				if inst.is_panel_open(panel_id):
					_mm.close_menu(panel_id)
				else:
					_mm.open_menu(panel_id)
		else:
			_mm.open_menu(panel_id)


func _toggle_world_map() -> void:
	if _world_map and _world_map.has_method("toggle"):
		_world_map.toggle()
	elif _mm and _mm.has_method("toggle_menu"):
		_mm.toggle_menu("world_map")


func _toggle_settings() -> void:
	if _hud:
		var panel: Node = _hud.get_node_or_null("SettingsPanel")
		if panel and panel.has_method("toggle"):
			panel.toggle()
		elif panel and panel.has_method("open"):
			panel.open()
		elif panel:
			panel.visible = not panel.visible
