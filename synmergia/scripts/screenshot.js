#!/usr/bin/env node
/**
 * screenshot.js — Puppeteer bridge for Synmergia noVNC game capture
 *
 * Captures the running Godot game via noVNC → Puppeteer.
 * This is the agent-side visual bridge: instead of ffmpeg x11grab
 * (which produces dark frames with Xvfb/llvmpipe), we screenshot
 * noVNC's rendered canvas which shows the actual game UI.
 *
 * Usage:
 *   node screenshot.js                          # screenshot → captures/screenshots/
 *   node screenshot.js --video 30               # record 30s video
 *   node screenshot.js --output /path/to/out.png
 *   node screenshot.js --url http://localhost:6080/vnc.html
 *
 * Options:
 *   --url    noVNC URL (default: http://localhost:6080/vnc.html)
 *   --output screenshot output path (default: captures/screenshots/<ts>.png)
 *   --video  record N seconds of video (default: none)
 *   --fps    video FPS (default: 10)
 *   --wait   ms to wait before capturing (default: 3000)
 *   --retry  capture retry attempts (default: 3)
 *   --debug  print extra logging
 *
 * Requirements (host):
 *   npm install puppeteer
 *
 * Requirements (in Docker):
 *   Node.js 20+, Puppeteer, Chromium (installed via Dockerfile)
 *
 * Run from repo root:
 *   node synmergia/scripts/screenshot.js --output captures/screenshots/main-menu.png
 */

// --- CLI args ---
const argv = require('minimist')(process.argv.slice(2));

if (argv.help || argv.h) {
  console.log(`Usage: node screenshot.js [options]

Screenshot/record Synmergia via noVNC using Puppeteer.
The game runs in a Docker container; this script connects to
noVNC (port 6080) and screenshots the rendered canvas — the
only way to get visible frames with Xvfb/llvmpipe.

Options:
  --url     noVNC URL (default: http://localhost:6080/vnc.html)
  --output  output path (default: captures/screenshots/<ts>.png)
  --video   record N seconds of video (default: 0, no video)
  --fps     video FPS (default: 10)
  --wait    ms to wait before capture (default: 3000)
  --retry   capture retry attempts (default: 3)
  --debug   verbose logging

Examples:
  node screenshot.js                              # screenshot
  node screenshot.js --output main-menu.png       # custom output
  node screenshot.js --video 30                   # record 30s
  node screenshot.js --wait 5000                  # wait longer
  node screenshot.js --debug                      # verbose
  node screenshot.js --url http://host:6080/vnc.html

Output: captures/screenshots/<timestamp>.png (or --output path)
Video:  captures/videos/<timestamp>.mp4  (requires ffmpeg in PATH)
`);
  process.exit(0);
}

if (argv.version || argv.v) {
  console.log('screenshot.js 1.0.0');
  process.exit(0);
}

const puppeteer = require('puppeteer');
const fs = require('fs');
const path = require('path');

const VNC_URL     = argv.url     || 'http://localhost:6080/vnc.html';
const OUTPUT_PATH = argv.output  || null;        // null = auto-generate
const VIDEO_SECS  = parseInt(argv.video  || '0', 10);
const FPS         = parseInt(argv.fps     || '10', 10);
const WAIT_MS     = parseInt(argv.wait    || '3000', 10);
const MAX_RETRIES = parseInt(argv.retry   || '3', 10);
const DEBUG       = argv.debug   || false;

function log(...args) {
  if (DEBUG) console.error('[screenshot]', ...args);
}

// --- Resolve output path ---
function resolveOutputPath(suffix) {
  if (OUTPUT_PATH) return OUTPUT_PATH;
  const dir = path.resolve(process.cwd(), 'captures', 'screenshots');
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  const ts = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
  return path.join(dir, `${ts}${suffix}`);
}

// --- NoVNC connection state ---
async function waitForNoVNCConnected(page, retries = 20, interval = 500) {
  for (let i = 0; i < retries; i++) {
    const connected = await page.evaluate(() => {
      // noVNC stores connection state in the RFB object
      // After connecting, the "state" property transitions to 'connected'
      const state = window.RFB ? window.RFB.connectionState : null;
      return state;
    }).catch(() => null);

    if (connected === 'connected') {
      log('noVNC connected');
      return true;
    }
    // Also check the DOM: noVNC removes the connecting overlay
    const overlay = await page.$('#noVNC_connecting').catch(() => null);
    if (overlay) {
      const visible = await overlay.isVisible().catch(() => false);
      if (!visible) {
        log('noVNC connection overlay hidden, assuming connected');
        return true;
      }
    }
    await new Promise(r => setTimeout(r, interval));
  }
  return false;
}

// --- Find the game canvas ---
async function findGameCanvas(page) {
  // Strategy 1: noVNC canvas inside the page
  let canvas = await page.$('canvas');
  if (canvas) {
    log('Found canvas via $("canvas")');
    return canvas;
  }

  // Strategy 2: inside an iframe
  const frames = await page.frames();
  for (const frame of frames) {
    canvas = await frame.$('canvas').catch(() => null);
    if (canvas) {
      log(`Found canvas in frame: "${frame.name()}" (${frame.url()})`);
      return canvas;
    }
  }

  // Strategy 3: any element with "canvas" class or id
  canvas = await page.$('[class*="canvas"]').catch(() => null)
    || await page.$('#canvas').catch(() => null)
    || await page.$('#screen').catch(() => null);
  if (canvas) {
    log('Found canvas via class/id selector');
    return canvas;
  }

  return null;
}

// --- Screenshot helper ---
async function capturePage(browser, page) {
  const connected = await waitForNoVNCConnected(page);
  if (!connected) {
    throw new Error('noVNC did not connect in time. Is Godot running? Check VNC port 5900.');
  }

  // Wait for game to render
  await new Promise(r => setTimeout(r, WAIT_MS));

  const canvas = await findGameCanvas(page);
  if (!canvas) {
    throw new Error('Could not find game canvas. noVNC may not have loaded correctly.');
  }

  const screenshot = await page.screenshot({
    type: 'png',
    fullPage: false,
  });
  return screenshot;
}

// --- Video recording ---
async function recordVideo(browser, page) {
  const connected = await waitForNoVNCConnected(page);
  if (!connected) {
    throw new Error('noVNC did not connect in time for video recording.');
  }

  const canvas = await findGameCanvas(page);
  if (!canvas) {
    throw new Error('Could not find canvas for video recording.');
  }

  const frames = [];
  const intervalMs = Math.round(1000 / FPS);
  const totalFrames = VIDEO_SECS * FPS;
  const dir = path.resolve(process.cwd(), 'captures', 'videos');
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  const ts = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
  const framesDir = path.join(dir, `${ts}-frames`);
  fs.mkdirSync(framesDir, { recursive: true });

  log(`Recording ${VIDEO_SECS}s at ${FPS}fps (${totalFrames} frames)...`);

  for (let i = 0; i < totalFrames; i++) {
    const frame = await page.screenshot({ type: 'png', fullPage: false });
    fs.writeFileSync(path.join(framesDir, `frame-${String(i).padStart(5, '0')}.png`), frame);
    await new Promise(r => setTimeout(r, intervalMs));
    if ((i + 1) % FPS === 0) {
      log(`  ${Math.round((i + 1) / totalFrames * 100)}% done`);
    }
  }

  // Encode with ffmpeg if available
  const ffmpegPath = require('which').sync('ffmpeg', { nothrow: true });
  const outPath = path.join(dir, `${ts}.mp4`);
  if (ffmpegPath) {
    const { execSync } = require('child_process');
    try {
      log(`Encoding video → ${outPath}`);
      execSync(
        `ffmpeg -y -framerate ${FPS} -i "${framesDir}/frame-%05d.png" ` +
        `-c:v libx264 -pix_fmt yuv420p "${outPath}"`,
        { stdio: 'inherit' }
      );
      // Clean up frames
      fs.rmSync(framesDir, { recursive: true, force: true });
      return outPath;
    } catch (e) {
      console.warn('[screenshot] ffmpeg encode failed, keeping raw frames:', e.message);
      return framesDir; // Return dir of frames instead
    }
  } else {
    console.warn('[screenshot] ffmpeg not found — raw frames saved to:', framesDir);
    console.warn('[screenshot] To encode: ffmpeg -framerate 10 -i <dir>/frame-%05d.png out.mp4');
    return framesDir;
  }
}

// --- Main ---
async function main() {
  log('Launching browser...');

  const browser = await puppeteer.launch({
    headless: 'new',
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-dev-shm-usage',
      '--disable-gpu',
      '--window-size=1920,1080',
    ],
    defaultViewport: { width: 1920, height: 1080 },
  });

  const page = await browser.newPage();

  console.log(`[screenshot] Navigating to noVNC: ${VNC_URL}`);
  await page.goto(VNC_URL, { waitUntil: 'networkidle0', timeout: 30000 });

  // Wait for noVNC UI to load
  await new Promise(r => setTimeout(r, 2000));

  // Auto-click Connect if the connect button is visible
  const connectBtn = await page.$('#noVNC_connect_button').catch(() => null)
    || await page.$('button:has-text("Connect")').catch(() => null);
  if (connectBtn) {
    const isVisible = await connectBtn.isVisible().catch(() => false);
    if (isVisible) {
      log('Auto-clicking Connect...');
      await connectBtn.click();
      await new Promise(r => setTimeout(r, 1000));
    }
  }

  let result;
  if (VIDEO_SECS > 0) {
    result = await recordVideo(browser, page);
  } else {
    // Retry logic for dark/blank captures
    let attempt = 0;
    let lastError = null;
    while (attempt < MAX_RETRIES) {
      attempt++;
      try {
        const screenshot = await capturePage(browser, page);
        const outPath = resolveOutputPath('.png');
        fs.writeFileSync(outPath, screenshot);
        console.log(`[screenshot] Saved: ${outPath}`);
        result = outPath;
        break;
      } catch (e) {
        lastError = e;
        console.warn(`  [attempt ${attempt}/${MAX_RETRIES}] ${e.message}`);
        if (attempt < MAX_RETRIES) {
          await new Promise(r => setTimeout(r, 2000));
        }
      }
    }
    if (!result) {
      console.error('[screenshot] All capture attempts failed.');
      console.error('  Hint: Is Godot running? Is noVNC connected? Try --wait 5000');
      await browser.close();
      process.exit(1);
    }
  }

  await browser.close();
  console.log(`[screenshot] Done: ${result}`);
}

main().catch(async (e) => {
  console.error('[screenshot] Fatal:', e.message);
  process.exit(1);
});
