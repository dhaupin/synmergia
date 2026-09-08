extends SceneTree

# Loads each named autoload/UI file and reports whether it parses.
# Run: godot --headless --path . --script res://tests/test_parse_check.gd
#
# This is the definitive check for the "autoload parse errors blocking
# --script mode" follow-up. A file that fails to load() here is a real
# parse error in 4.7.2, not a heuristic guess.

const TARGETS := [
	"res://core/autoload/game_manager.gd",
	"res://core/autoload/network_manager.gd",
	"res://core/services/player_lock_service.gd",
	"res://core/services/achievement_service.gd",
	"res://ui/components/blacksmith_ui.gd",
	"res://ui/components/skill_academy_ui.gd",
	"res://ui/components/ui_panel.gd",
	"res://core/autoload/player_manager.gd",
	"res://core/utils/app_firewall.gd",
	"res://core/autoload/logger.gd",
	"res://core/autoload/game_config.gd",
]

var _ok := 0
var _fail := 0

func _init() -> void:
	print("--- PARSE CHECK (Godot 4.7.2) ---")
	for path in TARGETS:
		var script = load(path)
		if script == null:
			print("  [FAIL] %s : load() returned null" % path)
			_fail += 1
		else:
			# load() succeeded. Try instantiating to catch runtime-class
			# errors that don't show at parse time (e.g. extends a type
			# that exists but whose base is broken).
			print("  [PASS] %s : loaded (%s)" % [path, script.get_path()])
			_ok += 1
	print("--- RESULTS: %d passed, %d failed ---" % [_ok, _fail])
	quit(0 if _fail == 0 else 1)
