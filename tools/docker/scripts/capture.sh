#!/bin/bash
# ============================================================================
# Synmergia Media Capture Hub
# Unified interface for screenshots, videos, and streams
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNMERGIA_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║         🎮 SYNMERGIA MEDIA CAPTURE HUB                     ║"
echo "║                                                              ║"
echo "║  Screenshot • Video Recording • Live Streaming              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Menu
show_menu() {
    echo ""
    echo -e "${GREEN}What would you like to do?${NC}"
    echo ""
    echo "  ${BLUE}[1]${NC} 📸 Screenshot       - Capture a single screenshot"
    echo "  ${BLUE}[2]${NC} 🎬 Record Video     - Record gameplay video"
    echo "  ${BLUE}[3]${NC} 📺 Live Stream      - Stream to RTMP (YouTube/Twitch)"
    echo "  ${BLUE}[4]${NC} 🧪 Puppeteer Test   - Run headless browser tests"
    echo "  ${BLUE}[5]${NC} 📁 Open Captures   - View saved media"
    echo "  ${BLUE}[6]${NC} 🧹 Clean Up        - Remove old captures"
    echo ""
    echo "  ${YELLOW}[0]${NC} Exit"
    echo ""
}

# Create directories
mkdir -p "$SYNMERGIA_ROOT/screenshots"
mkdir -p "$SYNMERGIA_ROOT/videos"

while true; do
    show_menu
    read -p "Select option: " choice
    
    case $choice in
        1)
            echo ""
            echo -e "${CYAN}📸 Screenshot Mode${NC}"
            read -p "Filename [screenshot_$(date +%Y%m%d_%H%M%S).png]: " filename
            filename=${filename:-screenshot_$(date +%Y%m%d_%H%M%S).png}
            read -p "Delay in seconds [1]: " delay
            delay=${delay:-1}
            
            bash "$SCRIPT_DIR/screenshot.sh" "$filename" "$delay"
            ;;
            
        2)
            echo ""
            echo -e "${CYAN}🎬 Video Recording${NC}"
            echo "Starting FFmpeg recording... Press Ctrl+C to stop."
            echo ""
            bash "$SCRIPT_DIR/record-video.sh" start
            ;;
            
        3)
            echo ""
            echo -e "${CYAN}📺 Live Streaming${NC}"
            read -p "RTMP URL: " rtmp_url
            if [ -n "$rtmp_url" ]; then
                bash "$SCRIPT_DIR/live-stream.sh" start "$rtmp_url"
            else
                echo -e "${RED}RTMP URL required!${NC}"
            fi
            ;;
            
        4)
            echo ""
            echo -e "${CYAN}🧪 Puppeteer Tests${NC}"
            node "$SCRIPT_DIR/test-novnc.js"
            ;;
            
        5)
            echo ""
            echo -e "${CYAN}📁 Saved Captures${NC}"
            echo ""
            echo "Screenshots:"
            ls -lh "$SYNMERGIA_ROOT/screenshots"/*.png 2>/dev/null | tail -5 || echo "  None yet"
            echo ""
            echo "Videos:"
            ls -lh "$SYNMERGIA_ROOT/videos"/*.mp4 2>/dev/null | tail -5 || echo "  None yet"
            ;;
            
        6)
            echo ""
            echo -e "${YELLOW}🧹 Cleaning up old captures...${NC}"
            find "$SYNMERGIA_ROOT/screenshots" -name "*.png" -mtime +7 -delete 2>/dev/null && echo "Removed old screenshots"
            find "$SYNMERGIA_ROOT/videos" -name "*.mp4" -mtime +7 -delete 2>/dev/null && echo "Removed old videos"
            echo "Done!"
            ;;
            
        0)
            echo ""
            echo -e "${GREEN}Goodbye! 👋${NC}"
            exit 0
            ;;
            
        *)
            echo -e "${RED}Invalid option${NC}"
            ;;
    esac
done
