#!/bin/bash
# ============================================================================
# Video recording script for Synmergia Docker
# Usage: ./record-video.sh [start|stop|status]
# 
# Records using FFmpeg with VNC display capture
# Output: /workspace/project/synmergia/videos/recording_YYYYMMDD_HHMMSS.mp4
# ============================================================================

set -e

DISPLAY_NUM=${DISPLAY_NUM:-:99}
OUTPUT_DIR=${OUTPUT_DIR:-/workspace/project/synmergia/videos}
PID_FILE="/tmp/synmergia_recording.pid"
LOG_FILE="/tmp/synmergia_recording.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

case "${1:-start}" in
    start)
        if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
            log_warn "Recording already in progress (PID: $(cat $PID_FILE))"
            exit 1
        fi

        mkdir -p "$OUTPUT_DIR"
        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        OUTPUT_FILE="${OUTPUT_DIR}/recording_${TIMESTAMP}.mp4"
        
        log_info "Starting video recording..."
        log_info "Display: $DISPLAY_NUM"
        log_info "Output: $OUTPUT_FILE"
        log_info "Press Ctrl+C to stop recording"
        
        # Record using FFmpeg with X11 capture
        # -framerate 30: 30 FPS
        # -video_size 1920x1080: Capture resolution
        # -codec libx264: H.264 codec for good compression
        # -crf 23: Quality (lower = better, 18-28 is good range)
        ffmpeg -f x11grab \
            -framerate 30 \
            -video_size 1920x1080 \
            -i "$DISPLAY_NUM" \
            -codec:v libx264 \
            -preset medium \
            -crf 23 \
            -pix_fmt yuv420p \
            "$OUTPUT_FILE" \
            > "$LOG_FILE" 2>&1 &
        
        echo $! > "$PID_FILE"
        log_info "Recording started! PID: $(cat $PID_FILE)"
        log_info "Log: $LOG_FILE"
        ;;
        
    stop)
        if [ ! -f "$PID_FILE" ]; then
            log_error "No recording in progress"
            exit 1
        fi
        
        PID=$(cat "$PID_FILE")
        log_info "Stopping recording (PID: $PID)..."
        kill -INT "$PID" 2>/dev/null || true
        
        # Wait for FFmpeg to finish
        sleep 2
        
        # Find the output file
        OUTPUT_FILE=$(grep -oP "Output #0.*'\K[^']+\.mp4" "$LOG_FILE" 2>/dev/null | tail -1)
        
        if [ -f "$PID_FILE" ]; then
            rm "$PID_FILE"
        fi
        
        if [ -n "$OUTPUT_FILE" ] && [ -f "$OUTPUT_FILE" ]; then
            SIZE=$(du -h "$OUTPUT_FILE" | cut -f1)
            DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$OUTPUT_FILE" 2>/dev/null | cut -d. -f1)
            log_info "✅ Recording saved: $OUTPUT_FILE"
            log_info "   Size: $SIZE | Duration: ${DURATION}s"
        else
            log_warn "Recording may not have saved properly"
            log_info "Check log: $LOG_FILE"
        fi
        ;;
        
    status)
        if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
            PID=$(cat "$PID_FILE")
            DURATION=$(ps -o etimes= -p "$PID" 2>/dev/null | tr -d ' ')
            log_info "🔴 Recording in progress"
            log_info "   PID: $PID"
            log_info "   Duration: ${DURATION}s"
        else
            log_info "⚪ No recording in progress"
        fi
        ;;
        
    *)
        echo "Usage: $0 {start|stop|status}"
        echo ""
        echo "Commands:"
        echo "  start   - Start recording (Ctrl+C to stop)"
        echo "  stop    - Stop current recording"
        echo "  status  - Check if recording is active"
        exit 1
        ;;
esac
