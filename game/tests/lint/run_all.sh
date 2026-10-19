#!/usr/bin/env bash
# Run every lint test in tests/lint/ in order. Prints a summary.
# Exits 0 if all pass, 1 if any fail.
#
# Usage:
#   tests/lint/run_all.sh                 # uses /tmp/Godot_v4.7.2-stable_linux.x86_64
#   tests/lint/run_all.sh /path/to/godot  # uses the provided binary
#   GODOT=/path/to/godot tests/lint/run_all.sh

set -u

GODOT_BIN="${1:-${GODOT:-/tmp/Godot_v4.7.2-stable_linux.x86_64}}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GAME_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

LINT_TESTS=(
	"res://tests/lint/test_lint_autoload.gd"
	"res://tests/lint/test_lint_indentation.gd"
	"res://tests/lint/test_lint_syntax.gd"
	"res://tests/lint/test_lint_charset.gd"
	"res://tests/lint/test_lint_general.gd"
)

total_pass=0
total_fail=0
fails=0

echo "=== LINT SUITE ==="
echo "Godot: $GODOT_BIN"
echo "Project: $GAME_DIR"
echo ""

for t in "${LINT_TESTS[@]}"; do
	echo "--- $t ---"
	out=$("$GODOT_BIN" --headless --path "$GAME_DIR" --script "$t" 2>&1)
	# Parse PASS/FAIL counts from the --- RESULTS --- line.
	results_line=$(echo "$out" | grep -E "^\-\-\- RESULTS:" | tail -1)
	if [ -z "$results_line" ]; then
		echo "  CRASH: no RESULTS line (script failed to run)"
		fails=$((fails + 1))
		continue
	fi
	# Extract integers.
	passes=$(echo "$results_line" | grep -oE "[0-9]+ passed" | head -1 | grep -oE "[0-9]+")
	failures=$(echo "$results_line" | grep -oE "[0-9]+ failed" | head -1 | grep -oE "[0-9]+")
	passes=${passes:-0}
	failures=${failures:-0}
	total_pass=$((total_pass + passes))
	total_fail=$((total_fail + failures))
	if [ "$failures" != "0" ]; then
		fails=$((fails + 1))
	fi
	# Show ERROR/WARN lines from this run.
	echo "$out" | grep -E "  (PASS|FAIL|ERROR|WARN|INFO )" | head -30
	echo ""
done

echo "=== SUMMARY ==="
echo "Total: $total_pass passed, $total_fail failed"
echo "Files with failures: $fails of ${#LINT_TESTS[@]}"
if [ "$fails" != "0" ]; then
	echo "EXIT 1"
	exit 1
fi
echo "EXIT 0"
exit 0
