#!/usr/bin/env bash
# test-headless.sh — Run Godot smoke tests in a headless Docker container
#
# This script runs the Godot smoke tests from synmergia/tests/ against
# a Docker container, verifying autoloads, services, and core game logic
# without requiring a GPU or display.
#
# Usage (from repo root):
#   docker build -t synmergia:test -f Dockerfile .
#   ./docker/test-headless.sh
#
# Or mount-only (no rebuild needed):
#   docker run --rm \
#     -v "$(pwd)/synmergia:/workspace/project/synmergia:ro" \
#     synmergia:test \
#     ./docker/test-headless.sh
#
# Exit codes:
#   0   all tests passed
#   1   one or more tests failed
#   2   Godot not found or other error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GODOT="${GODOT:-godot}"

# Colour codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ---------------------------------------------------------------------------
# Detect Godot binary
# ---------------------------------------------------------------------------
if ! command -v "$GODOT" &>/dev/null; then
    echo -e "${RED}Error: '$GODOT' not found. Set GODOT env var or install Godot.${NC}"
    exit 2
fi

echo -e "${GREEN}Using Godot: $(command -v "$GODOT") ($(godot --version 2>/dev/null || echo 'unknown version'))${NC}"
echo ""

# ---------------------------------------------------------------------------
# Tests to run (order matters — auth/registry first, then feature tests)
# ---------------------------------------------------------------------------
TESTS=(
    "res://tests/test_notification_frame.gd"
    "res://tests/test_notification_toast.gd"
    "res://tests/test_auto_response_signals.gd"
    "res://tests/test_hud_integration.gd"
    "res://tests/test_login_flow.gd"
    "res://tests/test_islands.gd"
)

# Filter tests if TEST_FILTER is set (e.g., TEST_FILTER=notification ./test-headless.sh)
if [[ -n "${TEST_FILTER:-}" ]]; then
    TESTS=("${TESTS[@]}" )  # keep all if no filter match — filter below
    echo -e "${YELLOW}Filtering tests by: $TEST_FILTER${NC}"
fi

# ---------------------------------------------------------------------------
# Results tracking
# ---------------------------------------------------------------------------
TOTAL_PASS=0
TOTAL_FAIL=0
FAILED_TESTS=()

# ---------------------------------------------------------------------------
# Run one test
# ---------------------------------------------------------------------------
run_test() {
    local test_path="$1"
    local test_name
    test_name="$(basename "$test_path" .gd)"

    # Apply filter
    if [[ -n "${TEST_FILTER:-}" ]] && ! [[ "$test_name" =~ $TEST_FILTER ]]; then
        echo -e "${YELLOW}[SKIP] $test_name${NC} (filtered out)"
        return 0
    fi

    echo -e "\n${YELLOW}Running: $test_name${NC}"

    local output
    local exit_code=0

    # Capture both stdout and stderr; Godot --script prints to stderr sometimes
    output=$(
        "$GODOT" --headless --path "$PROJECT_ROOT/synmergia" \
            --script "$test_path" 2>&1
    ) || exit_code=$?

    # Print output
    echo "$output" | sed 's/^/  /'

    if echo "$output" | grep -qE '^\[FAIL\]'; then
        echo -e "  ${RED}✗ FAILED: $test_name${NC}"
        ((TOTAL_FAIL++))
        FAILED_TESTS+=("$test_name")
        return 1
    elif echo "$output" | grep -qE '^\s*\[PASS\]'; then
        local passed
        passed=$(echo "$output" | grep -cE '^\s*\[PASS\]' || true)
        echo -e "  ${GREEN}✓ PASSED: $test_name ($passed cases)${NC}"
        ((TOTAL_PASS++))
        return 0
    elif [[ $exit_code -eq 0 ]]; then
        echo -e "  ${GREEN}✓ PASSED: $test_name (exit 0)${NC}"
        ((TOTAL_PASS++))
        return 0
    else
        echo -e "  ${RED}✗ FAILED: $test_name (exit $exit_code)${NC}"
        ((TOTAL_FAIL++))
        FAILED_TESTS+=("$test_name")
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
echo "=============================================="
echo " Synmergia Headless Smoke Tests"
echo "=============================================="
echo " Project:  $PROJECT_ROOT"
echo " Godot:    $(command -v "$GODOT")"
echo " Tests:    ${#TESTS[@]}"
echo " Filter:   ${TEST_FILTER:-none}"
echo "=============================================="
echo ""

# Check test files exist
for test_path in "${TESTS[@]}"; do
    if [[ ! -f "$PROJECT_ROOT/$test_path" ]]; then
        echo -e "${RED}Error: test file not found: $test_path${NC}"
        exit 2
    fi
done

for test_path in "${TESTS[@]}"; do
    run_test "$test_path" || true  # Don't exit on failure — run all tests
done

echo ""
echo "=============================================="
echo " Results"
echo "=============================================="
echo -e "  Passed: ${GREEN}$TOTAL_PASS${NC}"
echo -e "  Failed: ${RED}$TOTAL_FAIL${NC}"
echo ""

if [[ $TOTAL_FAIL -gt 0 ]]; then
    echo -e "${RED}Failed tests:${NC}"
    for t in "${FAILED_TESTS[@]}"; do
        echo -e "  ${RED}✗ $t${NC}"
    done
    echo ""
    echo -e "${RED}SMOKE TESTS FAILED${NC}"
    exit 1
else
    echo -e "${GREEN}ALL SMOKE TESTS PASSED${NC}"
    exit 0
fi
