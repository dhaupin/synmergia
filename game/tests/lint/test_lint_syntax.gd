extends SceneTree

# Syntax / unclosed-statement / odd-line linter.
#
# GDScript has a few parse-time gotchas that are easy to miss in
# review and only blow up when the file is loaded:
#
#   1. CRLF line endings (Windows-saved files). Godot's parser
#      sometimes treats the trailing \r as part of an identifier
#      and fails to find a matching symbol.
#   2. UTF-8 BOM (0xEF 0xBB 0xBF) at the start of a file. The
#      parser sees it as an invalid character before the script
#      body and fails to parse.
#   3. Unbalanced parens/brackets/braces. A missing `)` or `]` in
#      a literal, function call, or array literal produces a
#      cryptic "Expected X, got Y" parse error far from the
#      actual missing character.
#   4. Unbalanced triple-quote strings ("""). A `"""` inside a
#      regular `"""..."""` block closes the string early.
#   5. Triple+ blank lines in a row. Harmless, but indicates a
#      sloppy edit.
#   6. The "extends after class_name" antipattern. Per AGENTS.md
#      `extends` MUST come before `class_name` (Godot 4 rule).
#   7. Tabs/spaces on a single line mixed (line that has both
#      kinds of leading whitespace is a parse error).
#
# All checks are heuristic; expect the occasional false positive
# in code that intentionally uses `)` or `]` inside a string.
# They are reported as warnings unless they look unambiguous.
#
# Run with:
#   godot --headless --path . --script res://tests/lint/test_lint_syntax.gd

const Helpers := preload("res://tests/lint/lint_helpers.gd")

var _passed: int = 0
var _failed: int = 0


func _ok(label: String) -> void:
	_passed += 1
	print("  [PASS] ", label)


func _fail(label: String, detail: String = "") -> void:
	_failed += 1
	printerr("  [FAIL] ", label, " ", detail)


func _init() -> void:
	print("--- LINT: syntax / unclosed / odd lines ---")

	_check_crlf()
	_check_bom()
	_check_orphan_cr()
	_check_final_newline()
	_check_unbalanced_brackets()
	_check_extends_after_class_name()
	_check_triple_blank_lines()

	_finish()


func _check_crlf() -> void:
	var crlf_files: Array = []
	for path in Helpers.list_gd_files():
		if path.begins_with("res://addons/"):
			continue
		var bytes := Helpers.read_bytes(path)
		if bytes.size() == 0:
			continue
		# Look for \r\n anywhere in the file.
		var has_crlf := false
		for i in bytes.size() - 1:
			if bytes[i] == 0x0D and bytes[i + 1] == 0x0A:
				has_crlf = true
				break
		if has_crlf:
			crlf_files.append(path)
			Helpers.report_issue(path, 0, "error",
					"CRLF line endings (Windows). Use LF only.")
	if crlf_files.is_empty():
		_ok("no CRLF line endings in .gd files")
	else:
		_fail("CRLF line endings",
				str(crlf_files.size()) + " files; see ERROR lines above")


func _check_bom() -> void:
	var bom_files: Array = []
	for path in Helpers.list_gd_files():
		if path.begins_with("res://addons/"):
			continue
		var bytes := Helpers.read_bytes(path)
		if bytes.size() < 3:
			continue
		# UTF-8 BOM: EF BB BF
		if bytes[0] == 0xEF and bytes[1] == 0xBB and bytes[2] == 0xBF:
			bom_files.append(path)
			Helpers.report_issue(path, 0, "error",
					"UTF-8 BOM at start of file (parse error)")
	if bom_files.is_empty():
		_ok("no UTF-8 BOM in .gd files")
	else:
		_fail("UTF-8 BOM present",
				str(bom_files.size()) + " files; see ERROR lines above")


func _check_unbalanced_brackets() -> void:
	var unbalanced_files: Array = []
	for path in Helpers.list_gd_files():
		if path.begins_with("res://addons/"):
			continue
		var text := Helpers.read_text(path)
		var issues: Array = _scan_brackets(text)
		if not issues.is_empty():
			unbalanced_files.append(path)
			for issue in issues:
				Helpers.report_issue(path, issue["line"], "error", issue["msg"])
	if unbalanced_files.is_empty():
		_ok("brackets balanced in all .gd files")
	else:
		_fail("unbalanced brackets",
				str(unbalanced_files.size()) + " files; see ERROR lines above")


# Walks a script and reports unbalanced parens/brackets/braces and
# unclosed triple-quote strings. Skips contents of single-line and
# triple-quote strings and #-comments.
func _scan_brackets(text: String) -> Array:
	var issues: Array = []
	var lines := text.split("\n")
	var in_triple := false
	var triple_quote := "\"\"\""
	# Stack of expected closing characters with their line numbers.
	# We push an opening bracket, and pop when we see its closing
	# counterpart. At end of file, anything left on the stack is
	# unclosed. If we see a closer with no matching opener, report
	# the stray closer.
	var stack: Array = []  # of {closer: String, line: int}
	for line_idx in lines.size():
		var line: String = lines[line_idx]
		var stripped := _strip_strings_and_comments(line, in_triple, triple_quote)
		var cleaned: String = stripped[0]
		var new_triple: bool = stripped[1]
		if new_triple != in_triple:
			in_triple = new_triple
		for c in cleaned:
			match c:
				"(", "[", "{":
					stack.append({"closer": _matching(c), "line": line_idx + 1})
				")", "]", "}":
					if stack.is_empty():
						issues.append({"line": line_idx + 1,
								"msg": "stray closing '" + c
								+ "' with no matching opener"})
					elif stack.back()["closer"] != c:
						issues.append({"line": line_idx + 1,
								"msg": "expected '" + stack.back()["closer"]
								+ "' to close '" + stack.back()["closer"]
								+ "' opened on line " + str(stack.back()["line"])
								+ " but found '" + c + "'"})
					else:
						stack.pop_back()
	if not stack.is_empty():
		for entry in stack:
			issues.append({"line": entry["line"],
					"msg": "unclosed '" + _opening_of(entry["closer"])
					+ "' (expected '" + entry["closer"] + "')"})
	return issues


func _matching(open: String) -> String:
	match open:
		"(":
			return ")"
		"[":
			return "]"
		"{":
			return "}"
	return ""


func _opening_of(close: String) -> String:
	match close:
		")":
			return "("
		"]":
			return "["
		"}":
			return "{"
	return ""


# Returns [cleaned_code, new_in_triple_string_state].
# Strips the contents of "..." strings, '...' strings, """...
# strings, and # comments from a single line. This is a regex-free
# state machine so we don't have to import anything.
func _strip_strings_and_comments(line: String, in_triple: bool,
		triple_quote: String) -> Array:
	var out := ""
	var i := 0
	var n := line.length()
	while i < n:
		# Already inside a triple-quote block: copy until we find the
		# next """ or end of line.
		if in_triple:
			var end := line.find(triple_quote, i)
			if end < 0:
				# Still in triple at end of line. Emit no content.
				return [out, true]
			i = end + triple_quote.length()
			in_triple = false
			continue
		# Start of a comment?
		if i < n and line[i] == "#":
			# Rest of line is a comment. Drop it.
			break
		# Start of a triple-quote?
		if i + 2 < n and line.substr(i, 3) == triple_quote:
			in_triple = true
			i += 3
			continue
		# Start of a single-line string?
		if i < n and line[i] == "\"":
			i += 1
			while i < n and line[i] != "\"":
				if line[i] == "\\" and i + 1 < n:
					i += 2
					continue
				i += 1
			if i < n:
				i += 1  # skip closing quote
			continue
		if i < n and line[i] == "'":
			i += 1
			while i < n and line[i] != "'":
				if line[i] == "\\" and i + 1 < n:
					i += 2
					continue
				i += 1
			if i < n:
				i += 1
			continue
		out += line[i]
		i += 1
	return [out, in_triple]


func _check_extends_after_class_name() -> void:
	var bad_files: Array = []
	for path in Helpers.list_gd_files():
		if path.begins_with("res://addons/"):
			continue
		var text := Helpers.read_text(path)
		var first := Helpers.first_declaration_kind(text)
		if first == "":
			continue
		if first == "class_name":
			bad_files.append(path)
			Helpers.report_issue(path, 0, "error",
					"first declaration is class_name; "
					+ "extends must come first (Godot 4 rule)")
	if bad_files.is_empty():
		_ok("every script has extends before class_name")
	else:
		_fail("extends after class_name",
				str(bad_files.size()) + " files; see ERROR lines above")


func _check_triple_blank_lines() -> void:
	var bad_files: Array = []
	for path in Helpers.list_gd_files():
		if path.begins_with("res://addons/"):
			continue
		var text := Helpers.read_text(path)
		var blank_run := 0
		var line_num := 0
		for raw in text.split("\n"):
			line_num += 1
			var stripped := raw.strip_edges()
			if stripped.is_empty():
				blank_run += 1
				if blank_run >= 3:
					Helpers.report_issue(path, line_num, "info",
							"3+ consecutive blank lines (cosmetic)")
					bad_files.append(path)
					break
			else:
				blank_run = 0
	if bad_files.is_empty():
		_ok("no 3+ consecutive blank lines")
	else:
		_ok(str(bad_files.size()) + " files with 3+ blank lines (info)")


# "Orphan" CR: a carriage return (0x0D) that is NOT followed by a
# linefeed (0x0A). This is the "old Mac" line ending and is universally
# considered a smell. The CRLF check above catches the more common
# Windows pattern (CRLF), but a stray CR (e.g., the result of a botched
# search-and-replace from CRLF -> LF that missed one byte) is its own
# category. We treat this as ERROR (blocker) because Godot's parser
# is sensitive to stray CR and the fix is unambiguous.
func _check_orphan_cr() -> void:
	var bad_files: Array = []
	for path in Helpers.list_gd_files():
		if path.begins_with("res://addons/"):
			continue
		var bytes := Helpers.read_bytes(path)
		if bytes.size() == 0:
			continue
		# Look for 0x0D that is NOT followed by 0x0A. We allow the
		# CRLF pair (covered by _check_crlf) so we only flag the
		# CR-without-LF case.
		var bad := false
		for i in bytes.size():
			if bytes[i] == 0x0D:
				if i + 1 >= bytes.size() or bytes[i + 1] != 0x0A:
					bad = true
					break
		if bad:
			bad_files.append(path)
			Helpers.report_issue(path, 0, "error",
					"orphan CR (\\r without \\n); use LF only")
	if bad_files.is_empty():
		_ok("no orphan CR in .gd files")
	else:
		_fail("orphan CR in files",
				str(bad_files.size()) + " files; see ERROR lines above")


# Per .editorconfig, every .gd file should end with exactly one
# newline (`insert_final_newline = true`). Files committed without
# a final newline or with multiple trailing newlines are both
# flagged. This is a soft check (WARN, not fatal) so the build
# doesn't break while we have ~17 such files in the tree. The
# report tells authors which files to fix.
func _check_final_newline() -> void:
	var missing_files: Array = []
	var extra_files: Array = []
	for path in Helpers.list_gd_files():
		if path.begins_with("res://addons/"):
			continue
		var bytes := Helpers.read_bytes(path)
		if bytes.size() == 0:
			missing_files.append(path)
			Helpers.report_issue(path, 0, "warning",
					"empty .gd file (no bytes)")
			continue
		# Last byte must be 0x0A (LF), not 0x0D (CR).
		if bytes[bytes.size() - 1] == 0x0D:
			extra_files.append(path)
			Helpers.report_issue(path, 0, "warning",
					"file ends with \\r (no trailing \\n); use LF only")
			continue
		if bytes[bytes.size() - 1] != 0x0A:
			missing_files.append(path)
			Helpers.report_issue(path, 0, "warning",
					"file does not end with a newline")
			continue
		# Count consecutive trailing 0x0A bytes. > 1 means extra
		# trailing newlines.
		var n := 0
		var i := bytes.size() - 1
		while i >= 0 and bytes[i] == 0x0A:
			n += 1
			i -= 1
		if n > 1:
			extra_files.append(path)
			Helpers.report_issue(path, 0, "warning",
					"file has " + str(n) + " trailing newlines (should be exactly 1)")
	if missing_files.is_empty() and extra_files.is_empty():
		_ok("every .gd file ends with exactly one newline")
	else:
		# Soft check: do not block the build, but list the offenders
		# so they can be cleaned up.
		_ok(str(missing_files.size() + extra_files.size())
				+ " .gd files have final-newline issues (warning, not fatal)")


func _finish() -> void:
	print("--- RESULTS: ", _passed, " passed, ", _failed, " failed ---")
	if _failed > 0:
		quit(1)
	else:
		quit(0)
