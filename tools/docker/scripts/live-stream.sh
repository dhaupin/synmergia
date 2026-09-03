#!/bin/bash
# ============================================================================
# Live streaming script for Synmergia Docker
# Usage: ./live-stream.sh [start|stop] [rtmp_url]
#
# Streams to RTMP servers (YouTube, Twitch, custom)
# Requires: FFmpeg + valid RTMP URL
#
# Examples:
#   ./live-stream.sh start rtmp://a.rtmp.youtube.com/live2/KEY
#   ./live-stream.sh stop
# ============================================================================

set -e

DISPLAY_NUM=${DISPLAY_NUM:-:99}
PID_FILE="/tmp/synmergia_stream.pid"
LOG_FILE="/tmp/synmergia_stream.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_stream() { echo -e "${CYAN}[STREAM]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

case "${1:-start}" in
    start)
        if [ -z "$2" ]; then
            log_error "RTMP URL required!"
            echo "Usage: $0 start rtmp://a.rtmp.youtube.com/live2/YOUR_KEY"
            exit 1
        fi
        
        if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
            log_error "Stream already running (PID: $(cat $PID_FILE))"
            exit 1
        fi

        RTMP_URL="$2"
        log_stream "Starting live stream..."
        log_stream "RTMP: $RTMP_URL"
        log_stream "Display: $DISPLAY_NUM"
        log_stream "Press Ctrl+C to stop streaming"
        
        # Stream with FFmpeg
        # -re: Read at native frame rate (for live streaming)
        # -c:v libx264: H.264 hardware encoding if available
        # -b:v 4500k: 4.5 Mbps bitrate (good for 1080p)
        # -maxrate 5000k: Max bitrate
        # -bufsize 10000k: Buffer size
        ffmpeg -f x11grab \
            -re \
            -framerate 30 \
            -video_size 1920x1080 \
            -i "$DISPLAY_NUM" \
            -codec:v libx264 \
            -preset veryfast \
            -b:v 4500k \
            -maxrate 4500k \
            -bufsize 9000k \
            -codec:a aac \
            -b:a 128k \
            -ar 44100 \
            -f flv \
            "$RTMP_URL" \
            > "$LOG_FILE" 2>&1 &
        
        echo $! > "$PID_FILE"
        log_stream "Stream started! PID: $(cat $PID_FILE)"
        log_stream "Log: $LOG_FILE"
        ;;
        
    stop)
        if [ ! -f "$PID_FILE" ]; then
            log_error "No stream in progress"
            exit 1
        fi
        
        PID=$(cat "$PID_FILE")
        log_stream "Stopping stream (PID: $PID)..."
        kill -INT "$PID" 2>/dev/null || true
        
        sleep 2
        
        if [ -f "$PID_FILE" ]; then
            rm "$PID_FILE"
        fi
        
        log_stream "✅ Stream stopped"
        ;;
        
    *)
        echo "Usage: $0 {start|stop} [rtmp_url]"
        echo ""
        echo "Commands:"
        echo "  start RTMP_URL   - Start streaming to RTMP server"
        echo "  stop             - Stop current stream"
        echo ""
        echo "Examples:"
        echo "  YouTube: $0 start rtmp://a.rtmp.youtube.com/live2/YOUR_KEY"
        echo "  Twitch:  $0 start rtmp://live.twitch.tv/app/YOUR_STREAM_KEY"
        echo "  Custom:  $0 start rtmp://your-server.com/live/stream"
        exit 1
        ;;
esac
