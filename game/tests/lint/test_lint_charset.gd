extends SceneTree

# Charset linter: catches non-ASCII characters that cause Godot
# parse / display / editor issues.
#
# Per AGENTS.md "Code Standards":
#   "No UTF-8 special characters in the codebase - they cause
#    Godot import issues"
#
# We flag:
#   1. Any byte > 0x7F in a .gd file
#   2. Specific "named" culprits with replacement suggestions
#      (em-dash, smart quotes, NBSP, ellipsis, etc.)
#   3. Tabs inside string literals (often unintended)
#
# We allow:
#   - .uid files (binary content)
#   - addons/ (third-party)
#
# Run with:
#   godot --headless --path . --script res://tests/lint/test_lint_charset.gd

const Helpers := preload("res://tests/lint/lint_helpers.gd")

# Specific offenders worth calling out by name, mapped to the
# ASCII replacement we suggest. Key is the unicode codepoint in hex,
# value is [name, replacement].
const NAMED_OFFENDERS := {
	"2014": ["em-dash U+2014", "--"],
	"2013": ["en-dash U+2013", "-"],
	"2018": ["left single quote U+2018", "'"],
	"2019": ["right single quote U+2019", "'"],
	"201c": ["left double quote U+201C", "\""],
	"201d": ["right double quote U+201D", "\""],
	"2026": ["ellipsis U+2026", "..."],
	"00a0": ["non-breaking space U+00A0", " "],
	"200b": ["zero-width space U+200B", ""],
	"200c": ["zero-width non-joiner U+200C", ""],
	"200d": ["zero-width joiner U+200D", ""],
	"feff": ["zero-width no-break space U+FEFF", ""],
	"00b7": ["middle dot U+00B7", "*"],
	"00d7": ["multiplication sign U+00D7", "x"],
	"00f7": ["division sign U+00F7", "/"],
	"00b0": ["degree sign U+00B0", "deg"],
	"00b1": ["plus-minus U+00B1", "+/-"],
	"2264": ["less-than-or-equal U+2264", "<="],
	"2265": ["greater-than-or-equal U+2265", ">="],
	"2260": ["not-equal U+2260", "!="],
	"2192": ["rightwards arrow U+2192", "->"],
	"21d2": ["rightwards double arrow U+21D2", "=>"],
	"00a9": ["copyright sign U+00A9", "[c]"],
	"00ae": ["registered sign U+00AE", "[r]"],
	"2122": ["trademark sign U+2122", "[tm]"],
}

var _passed: int = 0
var _failed: int = 0


func _ok(label: String) -> void:
	_passed += 1
	print("  PASS: ", label)


func _fail(label: String, detail: String = "") -> void:
	_failed += 1
	printerr("  FAIL: ", label, " ", detail)


func _init() -> void:
	print("--- LINT: charset (non-ASCII / UTF-8) ---")

	_check_nonascii_bytes()
	_check_named_offenders()
	_check_tab_in_string()

	_finish()


func _check_nonascii_bytes() -> void:
	var dirty_files: Array = []
	for path in Helpers.list_gd_files():
		if path.begins_with("res://addons/"):
			continue
		var bytes := Helpers.read_bytes(path)
		if bytes.size() == 0:
			continue
		var dirty := PackedInt32Array()
		for i in bytes.size():
			if bytes[i] > 0x7F:
				dirty.append(i)
		if dirty.size() > 0:
			dirty_files.append(path)
			Helpers.report_issue(path, 0, "error",
					str(dirty.size()) + " non-ASCII byte(s); "
					+ "first 5 offsets: " + str(dirty.slice(0, min(5, dirty.size()))))
	if dirty_files.is_empty():
		_ok("no non-ASCII bytes in .gd files")
	else:
		_fail("non-ASCII bytes in .gd files",
				str(dirty_files.size()) + " files; see ERROR lines above")


func _check_named_offenders() -> void:
	var offenders: Array = []
	for path in Helpers.list_gd_files():
		if path.begins_with("res://addons/"):
			continue
		var text := Helpers.read_text(path)
		for hex_code in NAMED_OFFENDERS:
			var pair: Array = NAMED_OFFENDERS[hex_code]
			var needle := _decode_unicode(hex_code)
			if needle == "":
				continue
			var idx := text.find(needle)
			if idx < 0:
				continue
			# Compute line number for the first hit.
			var line_num := text.count("\n", 0, idx) + 1
			offenders.append(path)
			Helpers.report_issue(path, line_num, "error",
					"contains " + str(pair[0]) + "; replace with '"
					+ str(pair[1]) + "'")
			# Only one report per file to keep the noise down.
			break
	if offenders.is_empty():
		_ok("no named non-ASCII offenders (em-dash, smart quotes, etc.)")
	else:
		_fail("named non-ASCII offenders found",
				str(offenders.size()) + " files; see ERROR lines above")


# Decodes a hex codepoint (e.g., "2014") into the actual character.
# Returns "" if the input is malformed.
func _decode_unicode(hex: String) -> String:
	if hex.length() < 1 or hex.length() > 6:
		return ""
	var v := 0
	for c in hex:
		v = v * 16
		match c:
			"0", "1", "2", "3", "4", "5", "6", "7", "8", "9":
				v += int(c)
			"a", "b", "c", "d", "e", "f":
				v += 10 + (ord(c) - ord("a"))
			"A", "B", "C", "D", "E", "F":
				v += 10 + (ord(c) - ord("A"))
			_:
				return ""
	return String.chr(v)


func _check_tab_in_string() -> void:
	# Tabs inside double-quoted strings are usually fine for runtime
	# but very often a sign the author pasted from a doc / chat
	# window and intended ASCII space-separated output. Report as
	# warning (info level).
	var warned_files: Array = []
	for path in Helpers.list_gd_files():
		if path.begins_with("res://addons/"):
			continue
		var text := Helpers.read_text(path)
		var line_num := 0
		for raw in text.split("\n"):
			line_num += 1
			if raw.find("\"") < 0:
				continue
			# Count tabs that appear between an unescaped " and the
			# next unescaped ". Crude but useful.
			var in_str := false
			var prev := ""
			for c in raw:
				if c == "\"" and prev != "\\":
					in_str = not in_str
				elif in_str and c == "\t":
					Helpers.report_issue(path, line_num, "info",
							"tab character inside string literal")
					warned_files.append(path)
					break
				prev = c
	if warned_files.is_empty():
		_ok("no tab characters inside string literals")
	else:
		_ok(str(warned_files.size()) + " files have tabs in strings (info)")


func _finish() -> void:
	print("--- RESULTS: ", _passed, " passed, ", _failed, " failed ---")
	if _failed > 0:
		quit(1)
	else:
		quit(0)
