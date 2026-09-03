# Screenshot & Video Capture

## Current Status

**Xvfb Software Rendering Limitation:**
- Godot runs on llvmpipe (CPU-based OpenGL software renderer)
- Xvfb framebuffer captures (xwd, import, ffmpeg x11grab) produce dark/unusable images
- The 8-bit depth / software rendering doesn't update the framebuffer in a viewable way
- This is a known limitation of headless X without GPU

**What's Working:**
- ✅ noVNC browser viewing: `http://localhost:6080/vnc.html` - can see game in browser
- ✅ VNC port accessible: port 5900 for VNC clients
- ✅ Video recording: `ffmpeg -f x11grab` produces files (but dark content)
- ✅ Web server: screenshots saved to `./captures/` directory

## Available Methods

### 1. Browser Viewing (Recommended for Testing)
```bash
# View game in browser
open http://localhost:6080/vnc.html

# Or via HTTP
open http://localhost
```

### 2. Screenshot Capture
```bash
# These produce files but may be dark due to software rendering:
DISPLAY=:99 import -window root /captures/screenshot.png
DISPLAY=:99 xwd -root -out /captures/screenshot.xwd
DISPLAY=:99 ffmpeg -f x11grab -i :99 -vframes 1 /captures/screenshot.png

# Convert XWD to PNG
convert screenshot.xwd screenshot.png
```

### 3. Video Recording
```bash
DISPLAY=:99 ffmpeg -f x11grab -framerate 30 -i :99 -c:v libx264 -pix_fmt yuv420p /captures/gameplay.mp4
```

### 4. VNC Client
```bash
vncviewer localhost:5900
```

## For Visible Screenshots

Options for actual visible screenshots:
1. **GPU Passthrough**: Run with `--gpus all` and `--device /dev/dri`
2. **Real Display**: Xvfb doesn't support hardware rendering
3. **Use noVNC**: Take screenshots of the browser window itself
4. **Server with GPU**: Deploy on a machine with actual graphics hardware

## Screenshot Tools Available in Container

- `import` (ImageMagick) - X11 screen capture
- `xwd` - X Window Dump
- `ffmpeg` - Video capture and conversion
- `convert` (ImageMagick) - Format conversion
- `tigervnc-viewer` / `vncviewer` - VNC client

## Directory Structure
```
captures/
├── screenshots/    # Manual screenshots
├── videos/         # Recorded gameplay
└── *.png, *.mp4    # Output files
```

## Notes

- Screenshots save to `./captures/` which is volume-mounted
- Video quality is low (24kb/5sec) due to dark/uniform content
- Godot logs show "Main menu loaded" and all services initialize correctly
- The game is running - it's just the framebuffer capture that's limited
