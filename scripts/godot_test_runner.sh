#!/usr/bin/env bash
# Synmergia Godot test runner.
#
# Runs named headless Godot tests (default: the regression set covering
# the data-naming, movement, and 3d-pipeline work streams) and reports
# pass/fail per test. Godot tests exit 0 = pass, non-zero = fail;
# "resources still in use at exit" notes are benign.
#
# Usage:
#   sh ./scripts/godot_test_runner.sh                          # default set
#   sh ./scripts/godot_test_runner.sh test_movement_profiles   # named tests
#   sh ./scripts/godot_test_runner.sh --all                    # every test_*.gd
#
# Dash-safe: uses $0 (not BASH_SOURCE) so `sh ./scripts/...` works.

set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GAME_DIR="${ROOT_DIR}/game"

if ! command -v godot >/dev/null 2>&1; then
	echo "[runner] godot not on PATH. Install it or add it to PATH."
	exit 1
fi

# Default regression set: work streams that must never silently rot.
DEFAULT_SET="
test_data_naming_lint
test_movement_profiles
probe_blacksmith_model
probe_anim_play
probe_blacksmith_scene
"

if [ "${1:-}" = "--all" ]; then
	TESTS=$(cd "${GAME_DIR}/tests" && ls test_*.gd | sed 's/\.gd$//')
else
	TESTS="$*"
	if [ -z "$TESTS" ]; then
		TESTS="${DEFAULT_SET}"
	fi
fi

pass=0
fail=0
failed_names=""
for t in ${TESTS}; do
	if [ ! -f "${GAME_DIR}/tests/${t}.gd" ]; then
		echo "[runner] ?? ${t}: no such test (game/tests/${t}.gd)"
		fail=$((fail + 1))
		failed_names="${failed_names} ${t}"
		continue
	fi
	echo "[runner] == ${t}"
	if (cd "${GAME_DIR}" && timeout 120 godot --headless --path . --script "res://tests/${t}.gd" >"/tmp/syn_${t}.log" 2>&1); then
		echo "[runner]    PASS ${t}"
		pass=$((pass + 1))
	else
		echo "[runner]    FAIL ${t} (log: /tmp/syn_${t}.log)"
		grep -E "FAIL|SCRIPT ERROR|Parse Error" "/tmp/syn_${t}.log" | head -5
		fail=$((fail + 1))
		failed_names="${failed_names} ${t}"
	fi
done

echo "[runner] ${pass} passed, ${fail} failed${failed_names:+ [${failed_names}]}"
[ "${fail}" -eq 0 ]
