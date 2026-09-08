## GameLog - Simple logging utility
## Provides colored console output and optional file logging
## Registered as the `GameLog` autoload.
extends Node

func _esc(text: String) -> String:
	return text.replace('[', '［').replace(']', '］')

enum Level {
	DEBUG,
	INFO,
	WARN,
	ERROR
}

var _log_level: Level = Level.DEBUG
var _log_to_file: bool = false
var _log_file_path: String = "user://logs/game.log"

var level_names: Array[String] = ["DEBUG", "INFO", "WARN", "ERROR"]
var level_colors: Array[Color] = [
	Color.CORNFLOWER_BLUE,
	Color.GREEN,
	Color.YELLOW,
	Color.RED
]

func _ready() -> void:
	if _log_to_file:
		_init_log_file()

func _init_log_file() -> void:
	var log_dir := _log_file_path.get_base_dir()
	var dir := DirAccess.open(log_dir)
	if dir == null:
		DirAccess.make_dir_recursive_absolute(log_dir)

func _format_message(level: Level, message: String) -> String:
	var timestamp := Time.get_datetime_string_from_system()
	var level_str: String = level_names[level]
	return "[%s] [%s] %s" % [timestamp, level_str, message]

func log_message(level: Level, message: String) -> void:
	if level < _log_level:
		return
	
	var formatted := _format_message(level, message)
	var color: Color = level_colors[level]
	
	# Print to console with color
	if OS.is_debug_build():
		print_rich("[color=#%s]%s[/color]" % [color.to_html(), _esc(formatted)])
	else:
		print(formatted)
	
	# Write to file if enabled
	if _log_to_file:
		_write_to_file(formatted)

func debug(message: String) -> void:
	log_message(Level.DEBUG, message)

func info(message: String) -> void:
	log_message(Level.INFO, message)

func warn(message: String) -> void:
	log_message(Level.WARN, message)

func error(message: String) -> void:
	log_message(Level.ERROR, message)

func _write_to_file(message: String) -> void:
	var file := FileAccess.open(_log_file_path, FileAccess.READ_WRITE)
	if file:
		file.store_line(message)
		file.close()

func set_log_level(level: Level) -> void:
	_log_level = level

func set_log_file(enabled: bool, path: String = "user://logs/game.log") -> void:
	_log_to_file = enabled
	_log_file_path = path
	if enabled:
		_init_log_file()
