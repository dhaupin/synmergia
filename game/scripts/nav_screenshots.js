#!/usr/bin/env node
/**
 * nav_screenshots.js — Navigate game screens and capture screenshots.
 *
 * Architecture:
 *   Puppeteer + noVNC  -> establish VNC connection (host)
 *   xdotool + import   -> drive Godot & capture (inside Docker container)
 *
 * xwd output from Xvfb has a corrupted header (wrong dimensions),
 * so we use ImageMagick's `import` instead for reliable PNG capture.
 */
const { execSync } = require("child_process");
const puppeteer = require("puppeteer");
const { sync: whichSync } = require("which");
const fs = require("fs");
const path = require("path");

const sleep = ms => new Promise(r => setTimeout(r, ms));

const VNC_URL    = "http://localhost:6080/vnc.html";
const OUT_DIR    = path.join(__dirname, "..", "..", "docs", "screenshots");
const CONTAINER  = "synmergia-synmergia-1";
const DISPLAY    = ":99";

// ── Docker helpers ─────────────────────────────────────────────────────────────

function dockerExec(cmd) {
    return execSync(
        "sudo docker exec " + CONTAINER + " bash -c '" + cmd.replace(/'/g, "'\\''") + "'",
        { stdio: "pipe", encoding: "utf-8" }
    );
}

function dockerCp(src, dest) {
    return execSync(
        "sudo docker cp " + CONTAINER + ":" + src + " " + dest,
        { stdio: "pipe", encoding: "utf-8" }
    );
}

// ── Input helpers (xdotool inside container) ──────────────────────────────────

function xdotool(cmd) {
    dockerExec("DISPLAY=" + DISPLAY + " xdotool " + cmd);
}

// ── Screenshot (ImageMagick import inside container) ───────────────────────────

async function takeScreenshot(label) {
    const tmpPng  = "/tmp/ss_" + label + ".png";
    const outPath = path.join(OUT_DIR, label + ".png");

    // import: reliable screen capture (works where xwd header is corrupted)
    dockerExec("DISPLAY=" + DISPLAY + " import -window root " + tmpPng);
    dockerCp(tmpPng, outPath);
    dockerExec("rm -f " + tmpPng);

    const size = fs.statSync(outPath).size;
    console.log("[screenshot] " + label + ": " + outPath + " (" + (size / 1024).toFixed(0) + "KB)");
}

// ── Coordinate helpers ────────────────────────────────────────────────────────
// Godot renders at 1024x600 centered in the 1920x1080 Xvfb screen

function gameToScreen(gx, gy) {
    return {
        x: Math.round((1920 - 1024) / 2 + gx),
        y: Math.round((1080 - 600) / 2 + gy),
    };
}

function clickGame(gx, gy) {
    const p = gameToScreen(gx, gy);
    xdotool("mousemove " + p.x + " " + p.y + " click 1");
    console.log("  -> click (" + p.x + "," + p.y + ") [game " + gx + "," + gy + "]");
}

function pressKey(key) {
    xdotool("key " + key);
    console.log("  -> key " + key);
}

function typeText(text) {
    const escaped = text.replace(/"/g, "\\\"");
    xdotool("type --delay 30 \"" + escaped + "\"");
    console.log("  -> type: " + text);
}

// ── Main ─────────────────────────────────────────────────────────────────────

async function main() {
    if (!fs.existsSync(OUT_DIR)) {
        fs.mkdirSync(OUT_DIR, { recursive: true });
    }

    const CHROME = (
        process.env.PUPPETEER_EXECUTABLE_PATH ||
        whichSync("google-chrome", { nothrow: true }) ||
        whichSync("chromium-browser", { nothrow: true }) ||
        "/usr/bin/chromium"
    );

    console.log("Launching browser for VNC handshake...");
    const browser = await puppeteer.launch({
        headless: true,
        executablePath: CHROME,
        args: [
            "--no-sandbox",
            "--disable-setuid-sandbox",
            "--disable-dev-shm-usage",
            "--disable-gpu",
            "--window-size=1920,1080",
        ],
    });

    const page = await browser.newPage();
    await page.setViewport({ width: 1920, height: 1080 });

    console.log("Connecting to noVNC...");
    await page.goto(VNC_URL, { waitUntil: "networkidle0", timeout: 30000 });
    await sleep(2000);

    // Click Connect in the noVNC dialog
    try {
        await page.click("#noVNC_connect_button");
    } catch (e) {
        console.log("[VNC] Connect button not found (may already be connecting)");
    }

    // Wait for Connected status
    let connected = false;
    for (let i = 0; i < 20; i++) {
        await sleep(1000);
        const status = await page.evaluate(
            () => (document.querySelector("#noVNC_status") || {}).textContent || ""
        );
        if (status.includes("Connected")) {
            connected = true;
            break;
        }
    }
    console.log(connected ? "[VNC] Connected!" : "[VNC] Warning: not connected");

    // Give Godot time to fully render the main menu
    await sleep(8000);

    // ── Screen 1: Main Menu ────────────────────────────────────────────────
    console.log("\n=== 1. Main Menu ===");
    await takeScreenshot("01-main-menu");

    console.log("Clicking Play...");
    clickGame(512, 420);
    await sleep(3000);

    // ── Screen 2: Login ───────────────────────────────────────────────────
    console.log("\n=== 2. Login ===");
    await takeScreenshot("02-login");

    console.log("Filling player name...");
    clickGame(512, 280);   // username text field
    await sleep(300);
    typeText("TestPlayer");
    await sleep(300);
    clickGame(512, 330);   // Login button
    await sleep(4000);

    // ── Screen 3: Character Select ─────────────────────────────────────────
    console.log("\n=== 3. Character Select ===");
    await takeScreenshot("03-character-select");

    console.log("Clicking Create Character...");
    clickGame(512, 450);
    await sleep(2000);

    // ── Screen 4: Species Select ────────────────────────────────────────────
    console.log("\n=== 4. Species Select ===");
    await takeScreenshot("04-species-select");

    clickGame(200, 400);   // first species
    await sleep(1000);
    clickGame(512, 520);   // Next
    await sleep(2000);

    // ── Screen 5: Class Select ─────────────────────────────────────────────
    console.log("\n=== 5. Class Select ===");
    await takeScreenshot("05-class-select");

    clickGame(200, 400);   // first class
    await sleep(1000);
    clickGame(512, 520);   // Create
    await sleep(4000);

    // ── Screen 6: In-Game HUD ──────────────────────────────────────────────
    console.log("\n=== 6. In-Game HUD ===");
    await takeScreenshot("06-hud-ingame");

    // Inventory
    console.log("Opening Inventory (I)...");
    pressKey("i");
    await sleep(1500);
    await takeScreenshot("07-hud-inventory");
    pressKey("Escape");
    await sleep(500);

    // Character Stats
    console.log("Opening Character Stats (C)...");
    pressKey("c");
    await sleep(1500);
    await takeScreenshot("08-hud-character-stats");
    pressKey("Escape");
    await sleep(500);

    // Blacksmith
    console.log("Opening Blacksmith (B)...");
    pressKey("b");
    await sleep(1500);
    await takeScreenshot("09-hud-blacksmith");
    pressKey("Escape");
    await sleep(500);

    // Skill Academy
    console.log("Opening Skill Academy (H)...");
    pressKey("h");
    await sleep(1500);
    await takeScreenshot("10-hud-skill-academy");
    pressKey("Escape");

    await browser.close();

    console.log("\nAll screenshots saved to: " + OUT_DIR);
    const files = fs.readdirSync(OUT_DIR).filter(f => f.endsWith(".png"));
    console.log("Files: " + files.join(", "));
}

main().catch(e => {
    console.error("Fatal:", e.message);
    process.exit(1);
});
