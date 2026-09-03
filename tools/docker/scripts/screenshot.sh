#!/bin/bash
# ============================================================================
# Screenshot capture script for Synmergia Docker
# Usage: ./screenshot.sh [filename] [delay_seconds]
# Examples:
#   ./screenshot.sh                           # screenshot.png in 1 second
#   ./screenshot.sh my_shot.png               # my_shot.png in 1 second  
#   ./screenshot.sh action.png 3               # action.png in 3 seconds
# ============================================================================

set -e

DISPLAY_NUM=${DISPLAY_NUM:-:99}
OUTPUT_DIR=${OUTPUT_DIR:-/workspace/project/synmergia/screenshots}
FILENAME=${1:-screenshot_$(date +%Y%m%d_%H%M%S).png}
DELAY=${2:-1}
OUTPUT_PATH="${OUTPUT_DIR}/${FILENAME}"

echo "📸 Synmergia Screenshot Capture"
echo "================================"
echo "Display: $DISPLAY_NUM"
echo "Delay: ${DELAY}s"
echo "Output: $OUTPUT_PATH"

# Create output dir
mkdir -p "$OUTPUT_DIR"

# Wait for delay
sleep "$DELAY"

# Capture using scrot (if available) or VNC-compatible method
if command -v scrot &> /dev/null; then
    DISPLAY=$DISPLAY_NUM scrot "$OUTPUT_PATH" 2>/dev/null || {
        # Fallback to ImageMagick import
        DISPLAY=$DISPLAY_NUM import -window root "$OUTPUT_PATH"
    }
elif command -v import &> /dev/null; then
    DISPLAY=$DISPLAY_NUM import -window root "$OUTPUT_PATH"
elif command -v xwd &> /dev/null; then
    DISPLAY=$DISPLAY_NUM xwd -root -silent | xwdtoppm | ppm2png > "$OUTPUT_PATH"
else
    echo "ERROR: No screenshot tool found (scrot, imagemagick, or xwd)"
    exit 1
fi

if [ -f "$OUTPUT_PATH" ]; then
    SIZE=$(du -h "$OUTPUT_PATH" | cut -f1)
    echo ""
    echo "✅ Screenshot saved: $OUTPUT_PATH ($SIZE)"
    echo "   Dimensions: $(identify -format '%wx%h' "$OUTPUT_PATH" 2>/dev/null || echo 'unknown')"
else
    echo "❌ Failed to capture screenshot"
    exit 1
fi
