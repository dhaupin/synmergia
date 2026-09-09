## PlayerConfig - Per-account and per-character settings management
##
## Manages player-specific settings including:
## - UI preferences (keybinds, graphics, audio)
## - Privacy settings
## - Gameplay preferences
## - Account-wide and character-specific settings
##
## Settings are persisted to disk using ConfigFile
extends Node

const DictStore = preload("res://adapters/persistence/dict_store.gd")

## Player setting categories
enum SettingCategory {
	GENERAL,
	GRAPHICS,
	AUDIO,
	CONTROLS,
	GAMEPLAY,
	PRIVACY,
	KEYBINDINGS
}

## Storage keys for different setting types
const ACCOUNT_SETTINGS_FILE = "user://account_settings.cfg"
const CHARACTER_SETTINGS_FILE = "user://settings/char_%s.cfg"
const GLOBAL_SETTINGS_FILE = "user://global_settings.cfg"

## Default settings that apply to all new accounts
const DEFAULT_ACCOUNT_SETTINGS: Dictionary = {
	# General
	"show_tutorial_tooltips": true,
	"showtutorial": true,
	"auto_accept_party_invites": false,
	"auto_accept_guild_invites": false,
	"friend_on_whisper": false,

	# Graphics
	"graphics_quality": 2,  # 0=Low, 1=Medium, 2=High, 3=Ultra
	"vsync_enabled": true,
	"max_fps": 60,
	"show_fps_counter": false,
	"particle_effects": true,
	"show_other_players": true,
	"player_nameplates": true,
	"show_damage_numbers": true,
	"show_health_bars": true,
	"ui_scale": 1.0,
	"ambient_occlusion": true,
	"shadow_quality": 2,

	# Audio
	"master_volume": 1.0,
	"music_volume": 0.8,
	"sfx_volume": 1.0,
	"voice_volume": 1.0,
	"ambient_volume": 0.7,
	"ui_sounds": true,
	"enable_music": true,
	"enable_voice_chat": false,

	# Gameplay
	"auto_loot": false,
	"auto_attack": false,
	"show_minimap": true,
	"camera_distance": 10.0,
	"camera_rotation_speed": 1.0,
	"camera_smoothing": true,
	"invert_y_axis": false,
	"invert_x_axis": false,
	"enable_subtitles": true,
	"language": "en",

	# Privacy
	"show_online_status": true,
	"allow_friend_requests": true,
	"allow_guild_invites": true,
	"receive_whispers": true,
	"receive_party_invites": true,
	"show_location_to_friends": true,
	"block_trade_requests": false,
	"profile_visibility": 0,  # 0=Public, 1=Friends Only, 2=Hidden

	# Chat
	"chat_font_size": 14,
	"chat_opacity": 0.9,
	"chat_timestamps": true,
	"chat_sounds": true,
	"show_chat_filters": true,
	"profanity_filter": true,
	"channel_toggles": {
		"global": true,
		"zone": true,
		"party": true,
		"guild": true,
		"whisper": true,
		"trade": true,
		"system": true
	}
}

## Character-specific default settings
const DEFAULT_CHARACTER_SETTINGS: Dictionary = {
	"last_zone_id": "",
	"last_position": Vector3.ZERO,
	"ui_layout": {},
	"quick_slots": [],
	"favorite_items": [],
	"macro_setups": {}
}

# Active settings
var _account_settings: Dictionary = {}
var _character_settings: Dictionary = {}
var _global_settings: Dictionary = {}

# Config file handles
var _account_config: ConfigFile
var _character_config: ConfigFile
var _global_config: ConfigFile

# Current character ID (set when loading character)
var _current_character_id: String = ""

signal setting_changed(category: SettingCategory, key: String, value: Variant)
signal settings_loaded()
signal settings_saved()

func _ready() -> void:
	GameLog.info("PlayerConfig: Ready")
	_init_defaults()
	_load_global_settings()

func _load_global_settings() -> void:
	load_global_settings()

## Initialize with default values
func _init_defaults() -> void:
	_account_settings = DEFAULT_ACCOUNT_SETTINGS.duplicate(true)
	_character_settings = DEFAULT_CHARACTER_SETTINGS.duplicate(true)
	_global_config = ConfigFile.new()

## Load global settings (applies to all accounts on this device)
func load_global_settings() -> bool:
	_global_settings = _load_settings("global", _global_settings)
	return not _global_settings.is_empty()

## Save global settings
func save_global_settings() -> bool:
	return _save_settings("global", _global_settings)

## Load account settings
func load_account_settings(account_id: String) -> bool:
	_account_settings = _load_settings("account", DEFAULT_ACCOUNT_SETTINGS)
	if not _account_settings.is_empty():
		settings_loaded.emit()
		GameLog.info("PlayerConfig: Account settings loaded")
		return true
	return false

## Save account settings
func save_account_settings() -> bool:
	var ok := _save_settings("account", _account_settings)
	if ok:
		settings_saved.emit()
		GameLog.info("PlayerConfig: Account settings saved")
	return ok

## Load character-specific settings
func load_character_settings(character_id: String) -> bool:
	_current_character_id = character_id
	_character_settings = _load_settings("char:%s" % character_id, DEFAULT_CHARACTER_SETTINGS)
	if not _character_settings.is_empty():
		settings_loaded.emit()
		GameLog.info("PlayerConfig: Character settings loaded for %s" % character_id)
		return true
	return false

## Save character settings
func save_character_settings() -> bool:
	if _current_character_id.is_empty():
		GameLog.warn("PlayerConfig: No character ID set, cannot save")
		return false
	var ok := _save_settings("char:%s" % _current_character_id, _character_settings)
	if ok:
		settings_saved.emit()
		GameLog.info("PlayerConfig: Character settings saved")
	return ok

## Get account setting
func get_account_setting(key: String, default: Variant = null) -> Variant:
	if _account_settings.has(key):
		return _account_settings[key]
	return default if default != null else DEFAULT_ACCOUNT_SETTINGS.get(key)

## Set account setting
func set_account_setting(key: String, value: Variant, save: bool = true) -> void:
	var old_value = _account_settings.get(key)
	_account_settings[key] = value

	if old_value != value:
		setting_changed.emit(SettingCategory.GENERAL, key, value)

	if save:
		save_account_settings()

## Get character setting
func get_character_setting(key: String, default: Variant = null) -> Variant:
	if _character_settings.has(key):
		return _character_settings[key]
	return default if default != null else DEFAULT_CHARACTER_SETTINGS.get(key)

## Set character setting
func set_character_setting(key: String, value: Variant, save: bool = true) -> void:
	var old_value = _character_settings.get(key)
	_character_settings[key] = value

	if old_value != value:
		setting_changed.emit(SettingCategory.GENERAL, key, value)

	if save:
		save_character_settings()

## Get global setting
func get_global_setting(key: String, default: Variant = null) -> Variant:
	return _global_settings.get(key, default)

## Set global setting
func set_global_setting(key: String, value: Variant, save: bool = true) -> void:
	_global_settings[key] = value
	if save:
		save_global_settings()

## Reset account settings to defaults
func reset_account_settings() -> void:
	_account_settings = DEFAULT_ACCOUNT_SETTINGS.duplicate(true)
	save_account_settings()
	setting_changed.emit(SettingCategory.GENERAL, "reset", true)

## Reset character settings to defaults
func reset_character_settings() -> void:
	_character_settings = DEFAULT_CHARACTER_SETTINGS.duplicate(true)
	save_character_settings()
	setting_changed.emit(SettingCategory.GENERAL, "reset", true)

## Export settings for UI
func export_all_settings() -> Dictionary:
	return {
		"account": _account_settings.duplicate(true),
		"character": _character_settings.duplicate(true),
		"global": _global_settings.duplicate(true)
	}

## Import settings from dictionary
func import_settings(data: Dictionary) -> void:
	if data.has("account"):
		for key in data["account"]:
			set_account_setting(key, data["account"][key], false)
		save_account_settings()

	if data.has("character"):
		for key in data["character"]:
			set_character_setting(key, data["character"][key], false)
		save_character_settings()

	settings_loaded.emit()

## Get setting metadata (for UI generation)
func get_setting_metadata(key: String) -> Dictionary:
	var metadata: Dictionary = {
		"type": typeof(_account_settings.get(key, null)),
		"category": _get_setting_category(key)
	}

	# Add type-specific metadata
	match key:
		"graphics_quality":
			metadata["options"] = ["Low", "Medium", "High", "Ultra"]
			metadata["type"] = TYPE_INT
		"ui_scale":
			metadata["min"] = 0.5
			metadata["max"] = 2.0
			metadata["step"] = 0.1
		"master_volume", "music_volume", "sfx_volume", "voice_volume", "ambient_volume":
			metadata["min"] = 0.0
			metadata["max"] = 1.0
			metadata["step"] = 0.05
		"max_fps":
			metadata["min"] = 30
			metadata["max"] = 240
			metadata["step"] = 30
		"camera_distance":
			metadata["min"] = 5.0
			metadata["max"] = 30.0
			metadata["step"] = 1.0
		"chat_font_size":
			metadata["min"] = 10
			metadata["max"] = 24
			metadata["step"] = 1
		"chat_opacity":
			metadata["min"] = 0.3
			metadata["max"] = 1.0
			metadata["step"] = 0.1

	return metadata

func _get_setting_category(key: String) -> SettingCategory:
	if key in ["show_tutorial_tooltips", "showtutorial", "auto_accept_party_invites",
			"auto_accept_guild_invites", "friend_on_whisper"]:
		return SettingCategory.GENERAL
	elif key in ["graphics_quality", "vsync_enabled", "max_fps", "show_fps_counter",
			"particle_effects", "show_other_players", "player_nameplates", "show_damage_numbers",
			"show_health_bars", "ui_scale", "ambient_occlusion", "shadow_quality"]:
		return SettingCategory.GRAPHICS
	elif key in ["master_volume", "music_volume", "sfx_volume", "voice_volume",
			"ambient_volume", "ui_sounds", "enable_music", "enable_voice_chat"]:
		return SettingCategory.AUDIO
	elif key in ["auto_loot", "auto_attack", "show_minimap", "camera_distance",
			"camera_rotation_speed", "camera_smoothing", "invert_y_axis", "invert_x_axis",
			"enable_subtitles", "language"]:
		return SettingCategory.GAMEPLAY
	elif key in ["show_online_status", "allow_friend_requests", "allow_guild_invites",
			"receive_whispers", "receive_party_invites", "show_location_to_friends",
			"block_trade_requests", "profile_visibility"]:
		return SettingCategory.PRIVACY
	return SettingCategory.GENERAL

func _load_settings(scope: String, defaults: Dictionary) -> Dictionary:
	var store := DictStore.new()
	if not store.has("player:" + scope):
		return defaults.duplicate(true)
	var data: Dictionary = store.get("player:" + scope)
	if data.is_empty():
		return defaults.duplicate(true)
	var merged: Dictionary = defaults.duplicate(true)
	for key in data.keys():
		merged[key] = data[key]
	return merged

func _save_settings(scope: String, source: Dictionary) -> bool:
	var store := DictStore.new()
	store.set("player:" + scope, source)
	return true
