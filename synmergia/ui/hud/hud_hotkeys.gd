## HudHotkeys - Translates raw keypresses to UI panel toggles.
##
## Hooks InputManager via _unhandled_input. Keys are defined by the
## InputManager keybindings dictionary, but we only consume the
## "open_*" actions so movement/ability bindings stay in the
## InputManager.
##
## Esc closes any open panel (delegated to MenuManager if available).
extends Node

## Map of action -> panel id (matches MenuManager._get_panel IDs).
const _ACTION_TO_PANEL: Dictionary = {
	"open_inventory": "inventory",
	"open_character": "character",
	"open_quests": "quests",
	"open_chat": "chat",
	"open_friends": "friends",
	"open_party": "party",
	"open_guild": "guild",
	"open_admin": "admin_dashboard",
}

var _hud: CanvasLayer
var _mm: Node
var _admin_toolbar: Node
var _world_map: Node
var _chat: Node

## Track which panel IDs are currently open (per-panel).
var _open_panels: Dictionary = {}

## Action IDs we've already consumed this frame (debounce).
var _pressed_this_frame: Dictionary = {}


func bind(hud: CanvasLayer) -> void:
	_hud = hud
	_mm = hud.get_node_or_null("MenuManager")
	_admin_toolbar = hud.get_node_or_null("AdminToolbar")
	_world_map = hud.get_node_or_null("WorldMap")
	_chat = hud.get_node_or_null("ChatUI")
	# Hook InputManager's player_input signal so we react to canonical
	# action names (not raw key codes). This means the same handler
	# works for keyboard, controller, and touch rebinds.
	if InputManager and InputManager.has_signal("player_input"):
		InputManager.player_input.connect(_on_player_input)
	# Esc isn't in the keybindings map, so we keep _unhandled_input for it.
	set_process_unhandled_input(true)


func _on_player_input(action: String, pressed: bool) -> void:
	# InputManager emits on both press and release; we only want press.
	if not pressed:
		return
	if not _ACTION_TO_PANEL.has(action):
		return
	_handle_action(action, _ACTION_TO_PANEL[action])


func _unhandled_input(event: InputEvent) -> void:
	# Esc closes the most recently opened panel.
	if not event is InputEventKey:
		return
	var k: InputEventKey = event
	if not k.pressed or k.echo:
		return
	var keycode: int = k.physical_keycode
	if keycode == 0:
		keycode = k.keycode
	if keycode == KEY_ESCAPE:
		_handle_escape()
		get_viewport().set_input_as_handled()


func _handle_action(action: String, panel_id: String) -> void:
	match action:
		"open_map":
			_toggle_world_map()
		"open_chat":
			_focus_chat()
		"open_admin":
			_toggle_admin_dashboard()
		_:
			_toggle_panel(panel_id)


func _handle_escape() -> void:
	# Close the topmost panel if any.
	if not _mm:
		return
	if not _mm.has_method("close_top_menu"):
		# Fallback: just clear all panels.
		if _mm.has_method("close_all_menus"):
			_mm.close_all_menus()
		return
	_mm.close_top_menu()


func _toggle_panel(panel_id: String) -> void:
	if not _mm or not _mm.has_method("open_menu"):
		return
	if _open_panels.get(panel_id, false):
		if _mm.has_method("close_menu"):
			_mm.close_menu(panel_id)
		_open_panels[panel_id] = false
	else:
		_mm.open_menu(panel_id)
		_open_panels[panel_id] = true


func _toggle_world_map() -> void:
	if _world_map and _world_map.has_method("toggle"):
		_world_map.toggle()
	elif _mm and _mm.has_method("open_menu"):
		if _open_panels.get("world_map", false):
			if _mm.has_method("close_menu"):
				_mm.close_menu("world_map")
			_open_panels["world_map"] = false
		else:
			_mm.open_menu("world_map")
			_open_panels["world_map"] = true


func _focus_chat() -> void:
	# Open chat panel and focus the input.
	if _mm and _mm.has_method("open_menu"):
		_mm.open_menu("chat")
		_open_panels["chat"] = true
	if _chat:
		# Look for the LineEdit and grab focus.
		var le: Node = _chat.find_child("ChatInput", true, false)
		if le and le is LineEdit:
			le.grab_focus()


func _toggle_admin_dashboard() -> void:
	if _admin_toolbar and _admin_toolbar.has_method("_toggle_dashboard"):
		_admin_toolbar._toggle_dashboard()
