#!/bin/bash
# Synmergia Validation Script
# Runs Godot in headless mode and reports parse errors

set -e

GODOT_BIN="/tmp/Godot_v4.7.2-stable_linux.x86_64"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=========================================="
echo "Synmergia Parse Error Validator"
echo "=========================================="
echo "Project: $PROJECT_DIR"
echo "Godot: $GODOT_BIN"
echo ""

cd "$PROJECT_DIR"

# Run Godot headless and capture output
OUTPUT=$("$GODOT_BIN" --headless --quit 2>&1) || true

# Count parse errors
PARSE_ERRORS=$(echo "$OUTPUT" | grep -c "Parse Error" || echo "0")
TOTAL_ERRORS=$(echo "$OUTPUT" | grep -c "SCRIPT ERROR" || echo "0")

echo "=========================================="
echo "Results:"
echo "  Parse Errors: $PARSE_ERRORS"
echo "  Total Errors: $TOTAL_ERRORS"
echo "=========================================="
echo ""

# Show top files with errors
if [ "$PARSE_ERRORS" -gt 0 ]; then
    echo "Top files with errors:"
    echo "$OUTPUT" | grep -oE "res://[^:]+\.gd" | sort | uniq -c | sort -rn | head -10 | while read count file; do
        echo "  [$count] $file"
    done
    echo ""
    
    # Show first few errors
    echo "Sample errors (first 5):"
    echo "$OUTPUT" | grep "Parse Error" | head -5 | sed 's/^/  /'
fi

echo ""
echo "Done. $(date)"
