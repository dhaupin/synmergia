## LobbyUI - Per-account character list and selection
##
## Shown after a successful login. Lists characters linked to the
## current account (via AccountService), with Play / Create / Delete
## / Logout actions. Backed by AdapterRegistry (characters store).
extends Control
const UIStyles = preload("res://ui/components/ui_styles.gd")
const PersistenceStore = preload("res://adapters/persistence/persistence_store.gd")


const CharacterData := preload("res://core/schemas/character_data.gd")

@onready var _account_label: Label = $Center/Panel/VBox/Header/AccountLabel
@onready var _char_list: ItemList = $Center/Panel/VBox/CharList
@onready var _play_btn: Button = $Center/Panel/VBox/Buttons/PlayButton
@onready var _create_btn: Button = $Center/Panel/VBox/Buttons/CreateButton
@onready var _delete_btn: Button = $Center/Panel/VBox/Buttons/DeleteButton
@onready var _logout_btn: Button = $Center/Panel/VBox/Buttons/LogoutButton
@onready var _empty_label: Label = $Center/Panel/VBox/EmptyLabel
@onready var _info_label: Label = $Center/Panel/VBox/InfoLabel

var _characters: Array = []   # Array of CharacterData
var _selected_index: int = -1

func _ready() -> void:
	_apply_styles()
	if not LoginService or not LoginService.is_logged_in():
		if GameManager:
			GameManager.change_state(GameManager.GameState.LOGIN)
		return

	_play_btn.pressed.connect(_on_play_pressed)
	_create_btn.pressed.connect(_on_create_pressed)
	_delete_btn.pressed.connect(_on_delete_pressed)
	_logout_btn.pressed.connect(_on_logout_pressed)
	_char_list.item_selected.connect(_on_item_selected)
	_char_list.item_activated.connect(_on_item_activated)
	if LoginService:
		LoginService.logged_out.connect(_on_logged_out)

	_refresh_account_header()
	_refresh_character_list()

	# Auto-play a freshly created character -- the character_select scene stores
	# the id in GameManager meta before returning here so the signal is lost.
	var last_id: String = GameManager.get_meta("last_character_id", "") if GameManager else ""
	if last_id != "":
		GameManager.set_meta("last_character_id", "")
		for i in range(_characters.size()):
			if _characters[i].character_id == last_id:
				_char_list.select(i)
				_on_item_selected(i)
				await get_tree().process_frame
				_on_play_pressed()
				break

func _apply_styles() -> void:
	if not UIStyles:
		return
	var bs := UIStyles.create_button_style()
	for b in [_play_btn, _create_btn, _delete_btn, _logout_btn]:
		UIStyles.apply_button_styles(b, bs)

func _refresh_account_header() -> void:
	if not LoginService or not _account_label:
		return
	var acc := LoginService.get_current_account_id()
	var label := "Account: %s" % acc
	if LoginService.is_guest():
		label += "  (Guest)"
	_account_label.text = label

func _refresh_character_list() -> void:
	_characters.clear()
	_char_list.clear()
	_selected_index = -1
	_update_button_states()
	_info_label.text = ""

	if not LoginService:
		_empty_label.text = "LoginService unavailable"
		_empty_label.visible = true
		return

	var acc_id := LoginService.get_current_account_id()
	# Load any saved character blobs for this account
	var saved := _load_saved_characters(acc_id)
	for blob in saved:
		var cd := _blob_to_character_data(blob)
		if cd:
			_characters.append(cd)
			var label := "%s  *  Lv %d  %s  %s" % [
				cd.display_name, cd.level, cd.species_id, cd.class_id
			]
			_char_list.add_item(label)

	if _characters.is_empty():
		_empty_label.text = "No characters yet. Click \"Create New\" to begin."
		_empty_label.visible = true
	else:
		_empty_label.visible = false
		_char_list.select(0)
		_on_item_selected(0)

func _update_button_states() -> void:
	var has_selection := _selected_index >= 0 and _selected_index < _characters.size()
	_play_btn.disabled = not has_selection
	_delete_btn.disabled = not has_selection

func _on_item_selected(idx: int) -> void:
	_selected_index = idx
	_update_button_states()
	if idx >= 0 and idx < _characters.size():
		var cd: CharacterData = _characters[idx]
		_info_label.text = "%s * %s %s * Zone: %s" % [
			cd.display_name, cd.species_id, cd.class_id, cd.zone_id
		]

func _on_item_activated(idx: int) -> void:
	_selected_index = idx
	_on_play_pressed()

func _on_play_pressed() -> void:
	if _selected_index < 0 or _selected_index >= _characters.size():
		return
	var cd: CharacterData = _characters[_selected_index]
	GameManager.selected_character_data = cd
	GameManager.change_state(GameManager.GameState.PLAYING)

func _on_create_pressed() -> void:
	# Mark that we're coming from lobby so CharacterSelect links the
	# created character to the current account.
	GameManager.set_meta("creating_for_account", LoginService.get_current_account_id())
	GameManager.change_state(GameManager.GameState.CHARACTER_SELECT)

func _on_delete_pressed() -> void:
	if _selected_index < 0 or _selected_index >= _characters.size():
		return
	var cd: CharacterData = _characters[_selected_index]
	# Soft confirm via notification (pop dialogs are out-of-scope for now)
	if not cd:
		return
	_remove_character_blob(LoginService.get_current_account_id(), cd.character_id)
	if AccountService:
		AccountService.unlink_character(cd.character_id)
	GameLog.info("Lobby: Deleted character %s" % cd.character_id)
	_refresh_character_list()

func _on_logout_pressed() -> void:
	if LoginService:
		LoginService.logout()

# TAB = focus navigation (accessibility). Former F5/F6 debug hotkeys
# removed (see login.gd note); headless tests drive the buttons.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_TAB:
			_cycle_focus([_play_btn, _create_btn, _delete_btn, _logout_btn], event.shift)


func _cycle_focus(buttons: Array, reverse: bool) -> void:
	var current := get_viewport().gui_get_focus_owner()
	var idx := -1
	for i in range(buttons.size()):
		if buttons[i] == current:
			idx = i
			break
	if reverse:
		idx = (idx - 1 + buttons.size()) % buttons.size()
	else:
		idx = (idx + 1) % buttons.size()
	buttons[idx].grab_focus()

func _on_logged_out() -> void:
	if GameManager:
		GameManager.change_state(GameManager.GameState.LOGIN)


# == Persistence ========================================================

func _get_registry() -> Node:
	if get_tree() == null:
		return null
	return get_tree().root.get_node_or_null("AdapterRegistry")

func _get_store() -> PersistenceStore:
	var reg := _get_registry()
	if reg == null:
		GameLog.warn("Lobby: AdapterRegistry not found")
		return null
	var store: PersistenceStore = reg.get_persistence("characters")
	if store == null:
		GameLog.warn("Lobby: characters store not registered")
	return store

func _load_saved_characters(account_id: String) -> Array:
	var store := _get_store()
	if store == null:
		return []
	var key := "account:%s" % account_id
	var rows = store.query("SELECT value FROM kv WHERE key = $1", [key])
	if rows.is_empty():
		return []
	var raw = rows[0].get("value", "")
	if raw == "":
		return []
	var parsed = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		return []
	var by_account: Dictionary = parsed
	return by_account.get(account_id, [])

func _save_all_characters() -> void:
	var store := _get_store()
	if store == null:
		return
	var acc_id := LoginService.get_current_account_id() if LoginService else "default"
	var key := "account:%s" % acc_id
	
	# Load existing to preserve other accounts
	var rows = store.query("SELECT value FROM kv WHERE key = $1", [key])
	var by_account: Dictionary = {}
	if not rows.is_empty():
		var raw = rows[0].get("value", "")
		if raw != "":
			var parsed = JSON.parse_string(raw)
			if parsed is Dictionary:
				by_account = parsed
	
	var serialized: Array = []
	for cd in _characters:
		serialized.append(cd.to_dict())
	by_account[acc_id] = serialized
	
	var json = JSON.stringify(by_account)
	store.execute("DELETE FROM kv WHERE key = $1", [key])
	store.execute("INSERT INTO kv (key, value) VALUES ($1, $2)", [key, json])

func _remove_character_blob(account_id: String, character_id: String) -> void:
	var store := _get_store()
	if store == null:
		return
	var key := "account:%s" % account_id
	
	var rows = store.query("SELECT value FROM kv WHERE key = $1", [key])
	var by_account: Dictionary = {}
	if not rows.is_empty():
		var raw = rows[0].get("value", "")
		if raw != "":
			var parsed = JSON.parse_string(raw)
			if parsed is Dictionary:
				by_account = parsed
	var list: Array = by_account.get(account_id, [])
	list = list.filter(func(blob): return blob.get("character_id", "") != character_id)
	by_account[account_id] = list
	
	var json = JSON.stringify(by_account)
	store.execute("DELETE FROM kv WHERE key = $1", [key])
	store.execute("INSERT INTO kv (key, value) VALUES ($1, $2)", [key, json])

func _blob_to_character_data(blob: Dictionary) -> CharacterData:
	var cd := CharacterData.new(
		blob.get("species_id", "human"),
		blob.get("class_id", "human_warrior"),
		blob.get("display_name", "Hero")
	)
	cd.character_id = blob.get("character_id", "")
	cd.level = int(blob.get("level", 1))
	cd.zone_id = blob.get("zone_id", "zone_starter_plains")
	# Hydrate schema refs like character_select does (lines ~94-95):
	# get_stats() self-heals class_data lazily, but species stat
	# modifiers are skipped when species_data is null, and panels
	# that read class_data directly would see nothing.
	cd.species_data = CharacterData.load_species(cd.species_id)
	cd.class_data = CharacterData.load_class(cd.class_id)
	return cd
