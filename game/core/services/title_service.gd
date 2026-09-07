## TitleService - Player title management
## Handles title data, unlocking, equipping, and display
extends Node

const TitleData = preload("res://core/schemas/title_data.gd")
const QoSService = preload("res://core/autoload/qos_service.gd")

## Title definitions loaded from data/titles via DataService
var _title_defs: Dictionary = {}

## Player title state: player_id -> {unlocked_titles: [], equipped_prefix: "", equipped_suffix: "", title_color: Color(0,0,0)}
var _player_titles: Dictionary = {}

signal title_unlocked(player_id: String, title_id: String)
signal title_equipped(player_id: String, title_id: String, slot: String)
signal title_unequipped(player_id: String, title_id: String)

func _ready() -> void:
	GameLog.info("TitleService: Initialized")
	_load_title_definitions()

func _load_title_definitions() -> void:
	if DataService:
		if DataService.has_method("load_all_data") and DataService.get_all_titles().is_empty():
			DataService.load_all_data()
		if DataService.has_method("get_all_titles"):
			_title_defs = DataService.get_all_titles()
			GameLog.info("TitleService: Loaded %d titles from DataService" % _title_defs.size())
		else:
			GameLog.warn("TitleService: DataService missing get_all_titles")
	else:
		GameLog.warn("TitleService: DataService not available, titles will not load")

## ============================================================================
## PUBLIC API
## ============================================================================

## Unlock a title for a player
static func unlock(player_id: String, title_id: String) -> bool:
	var inst := singleton()
	if inst == null:
		return false
	return inst._do_unlock(player_id, title_id)

## Equip a title (prefix or suffix slot)
static func equip(player_id: String, title_id: String, slot: String) -> bool:
	var inst := singleton()
	if inst == null:
		return false
	return inst._do_equip(player_id, title_id, slot)

## Unequip a title from the specified slot
static func unequip(player_id: String, slot: String) -> void:
	var inst := singleton()
	if inst == null:
		return
	inst._do_unequip(player_id, slot)

## Check if player has title unlocked
static func is_unlocked(player_id: String, title_id: String) -> bool:
	var inst := singleton()
	if inst == null:
		return false
	return inst._has_title(player_id, title_id)

## Get all unlocked titles for player
static func get_unlocked_titles(player_id: String) -> Array[TitleData]:
	var inst := singleton()
	if inst == null:
		return []
	return inst._do_get_unlocked_titles(player_id)

## Get equipped prefix title
static func get_equipped_prefix(player_id: String) -> TitleData:
	var inst := singleton()
	if inst == null:
		return null
	return inst._do_get_equipped_prefix(player_id)

## Get equipped suffix title
static func get_equipped_suffix(player_id: String) -> TitleData:
	var inst := singleton()
	if inst == null:
		return null
	return inst._do_get_equipped_suffix(player_id)

## Get full display name with titles
## Example: "[The Slayer] dhaupin, the guildmaster"
static func get_display_name(player_id: String, base_name: String) -> String:
	var inst := singleton()
	if inst == null:
		return base_name

	var prefix_title: TitleData = inst._do_get_equipped_prefix(player_id)
	var suffix_title: TitleData = inst._do_get_equipped_suffix(player_id)

	var result := base_name
	if prefix_title != null:
		result = "[%s] %s" % [prefix_title.prefix_form, result]
	if suffix_title != null:
		result = "%s, %s" % [result, suffix_title.suffix_form]

	return result

## Get the player's custom title color (Color(0,0,0) if default)
static func get_title_color(player_id: String) -> Color:
	var inst := singleton()
	if inst == null:
		return Color(0, 0, 0)
	var state: Dictionary = inst._ensure_player_state(player_id)
	return state.get("title_color", Color(0, 0, 0))

## Set the player's custom title color
static func set_title_color(player_id: String, color: Color) -> void:
	var inst := singleton()
	if inst == null:
		return
	var state: Dictionary = inst._ensure_player_state(player_id)
	state["title_color"] = color

static func singleton() -> Node:
	var ml: MainLoop = Engine.get_main_loop()
	if ml == null or not ml is SceneTree:
		return null
	var root: Window = (ml as SceneTree).root
	if root == null:
		return null
	return root.get_node_or_null("TitleService")

## Get the local player's entity_id
static func get_local_player_id() -> String:
	if PlayerManager and PlayerManager.get_local_player():
		var player: Node = PlayerManager.get_local_player()
		if player.has("entity_id"):
			return player.get("entity_id")
	return ""

## Get display name for local player
static func get_local_display_name(base_name: String) -> String:
	return get_display_name(get_local_player_id(), base_name)

## ============================================================================
## TITLE DATA
## ============================================================================

func get_title(id: String) -> TitleData:
	return _title_defs.get(id)

func get_all_titles() -> Dictionary:
	return _title_defs

## ============================================================================
## PLAYER TITLE STATE
## ============================================================================

func _ensure_player_state(player_id: String) -> Dictionary:
	if not _player_titles.has(player_id):
		_player_titles[player_id] = {
			"unlocked_titles": [],
			"equipped_prefix": "",
			"equipped_suffix": "",
			"title_color": Color(0, 0, 0)  # Black = use default
		}
	return _player_titles[player_id]

func _has_title(player_id: String, title_id: String) -> bool:
	var state: Dictionary = _ensure_player_state(player_id)
	return title_id in state["unlocked_titles"]

func _do_unlock(player_id: String, title_id: String) -> bool:
	# QoS: Rate limit title unlocks (prevent exploit)
	if QoSService and not QoSService.rate_limit(player_id, "title_unlock"):
		return false
	
	if not _title_defs.has(title_id):
		GameLog.warn("TitleService: Unknown title %s" % title_id)
		return false

	var state: Dictionary = _ensure_player_state(player_id)
	if title_id in state["unlocked_titles"]:
		return false  # Already unlocked

	state["unlocked_titles"].append(title_id)
	_player_titles[player_id] = state
	title_unlocked.emit(player_id, title_id)
	GameLog.info("TitleService: Player %s unlocked title %s" % [player_id, title_id])
	return true

func _do_equip(player_id: String, title_id: String, slot: String) -> bool:
	# QoS: Rate limit title equips
	if QoSService and not QoSService.rate_limit(player_id, "title_equip"):
		return false
	
	if not _has_title(player_id, title_id):
		GameLog.warn("TitleService: Cannot equip locked title %s" % title_id)
		return false

	var title: TitleData = _title_defs.get(title_id)
	if title == null:
		return false

	# Validate title has the requested form
	if slot == "prefix" and not title.has_prefix():
		GameLog.warn("TitleService: Title %s has no prefix form" % title_id)
		return false
	if slot == "suffix" and not title.has_suffix():
		GameLog.warn("TitleService: Title %s has no suffix form" % title_id)
		return false

	var state: Dictionary = _ensure_player_state(player_id)
	state["equipped_" + slot] = title_id
	_player_titles[player_id] = state
	title_equipped.emit(player_id, title_id, slot)
	GameLog.info("TitleService: Player %s equipped %s to %s slot" % [player_id, title_id, slot])
	return true

func _do_unequip(player_id: String, slot: String) -> void:
	var state: Dictionary = _ensure_player_state(player_id)
	var current: String = state["equipped_" + slot]
	if current == "":
		return

	state["equipped_" + slot] = ""
	_player_titles[player_id] = state
	title_unequipped.emit(player_id, current)
	GameLog.info("TitleService: Player %s unequipped from %s slot" % [player_id, slot])

func _do_get_unlocked_titles(player_id: String) -> Array[TitleData]:
	var state: Dictionary = _ensure_player_state(player_id)
	var result: Array[TitleData] = []
	for title_id in state["unlocked_titles"]:
		if _title_defs.has(title_id):
			result.append(_title_defs[title_id])
	return result

func _do_get_equipped_prefix(player_id: String) -> TitleData:
	var state: Dictionary = _ensure_player_state(player_id)
	var title_id: String = state["equipped_prefix"]
	if title_id == "" or not _title_defs.has(title_id):
		return null
	return _title_defs[title_id]

func _do_get_equipped_suffix(player_id: String) -> TitleData:
	var state: Dictionary = _ensure_player_state(player_id)
	var title_id: String = state["equipped_suffix"]
	if title_id == "" or not _title_defs.has(title_id):
		return null
	return _title_defs[title_id]
