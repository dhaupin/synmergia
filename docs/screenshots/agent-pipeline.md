# Agent Screenshot Pipeline — noVNC → Puppeteer

## The Problem

Godot runs in Docker with **Xvfb** (virtual framebuffer) + **llvmpipe**
(CPU-based OpenGL). This means:

- `ffmpeg -f x11grab` → **dark/black frames** (Xvfb doesn't flush pixels to
  the X11 framebuffer in a way x11grab can read)
- `import` (ImageMagick) → same dark frame problem
- **noVNC in a browser** → renders correctly because noVNC reads from VNC's
  framebuffer state, not from X11

## The Solution

```
Godot (Xvfb DISPLAY=:99)
  → x11vnc  (:99 X11 → VNC port 5900)
  → websockify  (5900 VNC → WebSocket 6080)
  → noVNC canvas (browser renders it correctly)
  → Puppeteer screenshots the noVNC page
```

The noVNC canvas is what Puppeteer screenshots. The VNC protocol carries the
actual pixel data — no X11 framebuffer grab required.

## Quick Start

```bash
# 1. Start the Docker dev environment
docker compose up --build

# 2. Install the screenshot tool (one-time)
cd synmergia/scripts && npm install

# 3. Wait for noVNC to be ready, then capture
sleep 5
node synmergia/scripts/screenshot.js

# 4. Find your screenshot
ls captures/screenshots/
```

## Architecture

```
Docker Container (synmergia)

  Godot ──→ Xvfb ──→ x11vnc ──→ websockify ──→ noVNC
              (:99)    (port 5900)  (port 6080)    (browser)

  Puppeteer (inside container or on host)
  connects to http://localhost:6080/vnc.html
  screenshots the noVNC canvas
```

## Screenshot Tool

`synmergia/scripts/screenshot.js` — Puppeteer script.

### Installation

**In Docker (already installed in Dockerfile):**
```bash
cd synmergia/scripts && npm install
```

**On host machine:**
```bash
cd tools && npm install
```

### Usage

```bash
# Basic screenshot (auto-saved to captures/screenshots/<ts>.png)
node synmergia/scripts/screenshot.js

# Custom output path
node synmergia/scripts/screenshot.js --output my-screenshot.png

# Different noVNC URL (e.g., connecting to a remote container)
node synmergia/scripts/screenshot.js --url http://192.168.1.100:6080/vnc.html

# Video recording (30 seconds at 10fps)
node synmergia/scripts/screenshot.js --video 30

# Higher quality video
node synmergia/scripts/screenshot.js --video 30 --fps 30

# Wait longer before capturing (game needs more init time)
node synmergia/scripts/screenshot.js --wait 8000

# Retry on dark/blank frames
node synmergia/scripts/screenshot.js --retry 5

# Verbose debug output
node synmergia/scripts/screenshot.js --debug
```

### How It Works

1. **Launches Chromium** in headless mode via Puppeteer
2. **Navigates to noVNC URL** (`http://localhost:6080/vnc.html`)
3. **Auto-clicks Connect** if the connect button is visible
4. **Waits for noVNC to connect** — polls `window.RFB.connectionState`
5. **Finds the game canvas** — checks for `<canvas>` elements (top-level,
   inside iframes, or `#canvas` / `#screen` ids)
6. **Screenshots the page** — captures the rendered noVNC canvas
7. **Saves to disk** — auto-generates timestamped filename or uses `--output`

### Retry Logic

If the first screenshot is dark/blank (noVNC not yet fully rendered), the
script retries up to `--retry` times with 2-second delays. Default: 3 attempts.
Increase `--wait` if the game needs more init time.

### Video Recording

When `--video N` is set, the script:
1. Records `N × FPS` frames (default 10 fps)
2. Saves each frame as a PNG in `captures/videos/<ts>-frames/`
3. If `ffmpeg` is in PATH, encodes to MP4 automatically
4. If no `ffmpeg`, raw frames are kept and instructions are printed

## File Structure

```
synmergia/
├── scripts/
│   ├── screenshot.js       # Puppeteer capture tool
│   ├── package.json        # Dependencies
│   ├── package-lock.json   # Lockfile
│   └── # node_modules/ built by Dockerfile (gitignored)
│
├── captures/               # Gitignored — volume-mounted
│   ├── screenshots/
│   │   └── *.png
│   └── videos/
│       └── *.mp4
│
└── docs/
    └── screenshots/
        └── agent-pipeline.md   # This file
```

## Gitignore

`captures/` is gitignored. The volume mount in `docker-compose.yml`
keeps screenshots and videos on the host:

```yaml
volumes:
  - ./captures:/workspace/project/synmergia/captures
```

## Troubleshooting

### "noVNC did not connect in time"

- Is Godot running? `docker compose logs synmergia`
- Is VNC running? Check port 5900: `curl -sf http://localhost:6080`
- Increase `--wait`: `node screenshot.js --wait 8000`

### Screenshots are dark/blank

- This is the core problem this pipeline solves
- If noVNC itself shows dark content: Godot may have crashed or Xvfb
  is not rendering. Check `docker compose logs`.
- Increase `--wait` and `--retry`.

### "Cannot find game canvas"

- noVNC may not have fully loaded
- Try visiting `http://localhost:6080/vnc.html` manually in a browser
- Check that the canvas element is present

### Puppeteer launch fails

- On Linux, you may need `--no-sandbox` and `--disable-setuid-sandbox`
  (already included in the script's launch args)
- Ensure Chromium/Chrome is installed: Puppeteer downloads it automatically

## For Agents

An agent running in this environment can use the screenshot pipeline to:

1. **Verify UI changes** — take a screenshot after a code change and compare
2. **Debug rendering issues** — capture state of the game at any point
3. **Generate documentation** — take screenshots for readmes and docs
4. **QA workflows** — screenshot the game at key states (login, main menu,
   in-game, etc.) to verify features

The agent workflow:
```bash
# 1. Make a code change to the game
# 2. Restart Godot inside Docker
docker compose restart synmergia

# 3. Wait for startup
sleep 10

# 4. Capture
node synmergia/scripts/screenshot.js --output captures/screenshots/my-change.png

# 5. Inspect the screenshot
# 6. Continue development
```
