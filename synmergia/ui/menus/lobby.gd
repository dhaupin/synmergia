## LobbyUI - Per-account character list and selection
##
## Shown after a successful login. Lists characters linked to the
## current account (via AccountService), with Play / Create / Delete
## / Logout actions. Backed by disk via LoginService.
extends Control

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
		# Defensive: bail to login
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
			var label := "%s  ·  Lv %d  %s  %s" % [
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
		_info_label.text = "%s · %s %s · Zone: %s" % [
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

func _on_logged_out() -> void:
	if GameManager:
		GameManager.change_state(GameManager.GameState.LOGIN)


# ── Persistence ────────────────────────────────────────────────────────

const CHARS_SAVE_PATH := "user://characters.json"

func _load_saved_characters(account_id: String) -> Array:
	if not FileAccess.file_exists(CHARS_SAVE_PATH):
		return []
	var f := FileAccess.open(CHARS_SAVE_PATH, FileAccess.READ)
	if not f:
		return []
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return []
	var by_account: Dictionary = parsed
	var list: Array = by_account.get(account_id, [])
	return list

func _save_all_characters() -> void:
	# Read existing, replace, write. We don't touch other accounts.
	var by_account: Dictionary = {}
	if FileAccess.file_exists(CHARS_SAVE_PATH):
		var rf := FileAccess.open(CHARS_SAVE_PATH, FileAccess.READ)
		if rf:
			var parsed = JSON.parse_string(rf.get_as_text())
			rf.close()
			if parsed is Dictionary:
				by_account = parsed
	var acc_id := LoginService.get_current_account_id() if LoginService else "default"
	var serialized: Array = []
	for cd in _characters:
		serialized.append(cd.to_dict())
	by_account[acc_id] = serialized
	var wf := FileAccess.open(CHARS_SAVE_PATH, FileAccess.WRITE)
	if wf:
		wf.store_string(JSON.stringify(by_account))
		wf.close()

func _remove_character_blob(account_id: String, character_id: String) -> void:
	var by_account: Dictionary = {}
	if FileAccess.file_exists(CHARS_SAVE_PATH):
		var rf := FileAccess.open(CHARS_SAVE_PATH, FileAccess.READ)
		if rf:
			var parsed = JSON.parse_string(rf.get_as_text())
			rf.close()
			if parsed is Dictionary:
				by_account = parsed
	var list: Array = by_account.get(account_id, [])
	list = list.filter(func(blob): return blob.get("character_id", "") != character_id)
	by_account[account_id] = list
	var wf := FileAccess.open(CHARS_SAVE_PATH, FileAccess.WRITE)
	if wf:
		wf.store_string(JSON.stringify(by_account))
		wf.close()

func _blob_to_character_data(blob: Dictionary) -> CharacterData:
	var cd := CharacterData.new(
		blob.get("species_id", "human"),
		blob.get("class_id", "warrior"),
		blob.get("display_name", "Hero")
	)
	cd.character_id = blob.get("character_id", "")
	cd.level = int(blob.get("level", 1))
	cd.zone_id = blob.get("zone_id", "zone_starter_plains")
	return cd
