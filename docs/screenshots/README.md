# Screenshots

UI/HUD screenshots captured via the noVNC → Puppeteer pipeline.

## Captured Screens

| File | Scene | Description |
|------|-------|-------------|
| `01-main-menu.png` | `ui/menus/main_menu.tscn` | Main menu with Synmergia logo |
| `02-after-enter.png` | — | Welcome / login screen (New Player / Returning Player) |
| `04-after-tab.png` | — | Character class selection (Akkan archetypes) |

## How to Capture

Run inside the dev container:

```bash
# Screenshot of current scene
docker exec <container> node /workspace/project/synmergia/synmergia/scripts/screenshot.js \
  --output /workspace/project/synmergia/captures/screenshots/<name>.png \
  --wait 10000

# Screenshot of specific URL (e.g., work host)
docker exec <container> node /workspace/project/synmergia/synmergia/scripts/screenshot.js \
  --url http://<host-ip>:6080/vnc.html \
  --output /workspace/project/synmergia/captures/screenshots/<name>.png

# Record video
docker exec <container> node /workspace/project/synmergia/synmergia/scripts/screenshot.js \
  --video 30 --fps 10 --output video.png
```

The `--wait` flag controls how long to wait after noVNC connects
before capturing. The default is 3s; use `--wait 10000` for Godot scenes
that need time to load.

## Pipeline

```
Godot (Xvfb DISPLAY=:99)
  → x11vnc (port 5900)
  → websockify (port 6080)
  → noVNC canvas
  → Puppeteer/Chromium screenshot
  → PNG file
```

## Requirements

- Container running with Godot in normal mode (not `START_GODOT=headless`)
- Chromium installed (`npx puppeteer browsers install chrome`)
- `screenshot.js` at `/workspace/project/synmergia/synmergia/scripts/screenshot.js`
