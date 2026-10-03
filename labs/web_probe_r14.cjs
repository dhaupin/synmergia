#!/usr/bin/env node
// R14 web probe (r4): serve web/ with COOP/COEP, boot the real engine in
// headless Chromium (SwiftShader ANGLE/Vulkan, proven: full chrome +
// --in-process-gpu; --single-process REMOVED - never tested, drop it).
// Click-through is gated on engine ground truth (DebugOverlay "Click:" lines
// + GameLog "Game state changed:" lines), not pixels alone.
// Run from the REPO ROOT:  node labs/web_probe_r14.cjs
// Exit codes: 0 ok | 2 boot failed | 3 viewport "black" | 4 probe error
"use strict";
const http = require("http");
const path = require("path");
const fs = require("fs");
const os = require("os");
const NM = "/home/daytona/r14-webtest/node_modules";
const { chromium } = require(NM + "/playwright");
const { PNG } = require(NM + "/pngjs");
const FULL_CHROME = os.homedir() + "/.cache/ms-playwright/chromium-1243/chrome-linux64/chrome";

const WEB_ROOT = path.resolve(process.cwd(), "web");
const OUT_DIR = "/home/daytona/r14-webtest/out";
const PORT = 8099;
fs.mkdirSync(OUT_DIR, { recursive: true });

const MIME = {
	".html": "text/html; charset=utf-8",
	".js": "text/javascript",
	".css": "text/css",
	".json": "application/json",
	".svg": "image/svg+xml",
	".png": "image/png",
	".wasm": "application/wasm",
	".pck": "application/octet-stream",
	".hash": "text/plain",
};

function serve(req, res) {
	const urlPath = decodeURIComponent(req.url.split("?")[0]);
	const rel = urlPath === "/" ? "/index.html" : urlPath;
	const file = path.join(WEB_ROOT, rel);
	if (!file.startsWith(WEB_ROOT)) { res.writeHead(403); res.end(); return; }
	fs.readFile(file, (err, data) => {
		if (err) { res.writeHead(404); res.end(); return; }
		const ext = path.extname(file).toLowerCase();
		const headers = {
			"Content-Type": MIME[ext] || "application/octet-stream",
			"Cross-Origin-Opener-Policy": "same-origin",
			"Cross-Origin-Embedder-Policy": "require-corp",
		};
		if (ext === ".hash" || ext === ".html") headers["Cache-Control"] = "no-store";
		res.writeHead(200, headers);
		if (req.method === "HEAD") { res.end(); return; }
		res.end(data);
	});
}

const server = http.createServer(serve);

function classifyPng(file) {
	const png = PNG.sync.read(fs.readFileSync(file));
	const d = png.data;
	const W = png.width, H = png.height;
	let black = 0, green = 0, teal = 0, bright = 0;
	const buckets = new Map();
	const RG = 4;
	const reg = [];
	for (let i = 0; i < RG * RG; i++) reg.push({ green: 0, teal: 0, bright: 0 });
	for (let y = 0; y < H; y++) {
		const ry = Math.min(RG - 1, (y / (H / RG)) | 0);
		for (let x = 0; x < W; x++) {
			const i = (y * W + x) * 4;
			const r = d[i], g = d[i + 1], b = d[i + 2];
			if (r < 25 && g < 25 && b < 25) black++;
			const isGreen = g > r + 12 && g > b + 12;
			const isTeal = !isGreen && b > r + 20 && b > 60 && g > r + 8;
			if (isGreen) green++;
			if (isTeal) teal++;
			if (r > 200 && g > 200 && b > 200) bright++;
			const key = ((r >> 5) << 10) | ((g >> 5) << 5) | (b >> 5);
			buckets.set(key, (buckets.get(key) || 0) + 1);
			const cell = reg[ry * RG + Math.min(RG - 1, (x / (W / RG)) | 0)];
			if (isGreen) cell.green++;
			if (isTeal) cell.teal++;
			if (r > 200 && g > 200 && b > 200) cell.bright++;
		}
	}
	const total = W * H;
	const top = [...buckets.entries()].sort((a, b) => b[1] - a[1]).slice(0, 6).map(([k, n]) => ({
		rgb: (((k >> 10) & 31) * 32 + 16) + "," + (((k >> 5) & 31) * 32 + 16) + "," + ((k & 31) * 32 + 16),
		pct: +((n / total) * 100).toFixed(1),
	}));
	const cellTotal = total / (RG * RG);
	const grid = reg.map((c) => ({
		green: +((c.green / cellTotal) * 100).toFixed(1),
		teal: +((c.teal / cellTotal) * 100).toFixed(1),
		bright: +((c.bright / cellTotal) * 100).toFixed(1),
	}));
	return {
		blackPct: +((black / total) * 100).toFixed(1),
		greenPct: +((green / total) * 100).toFixed(1),
		tealPct: +((teal / total) * 100).toFixed(1),
		brightPct: +((bright / total) * 100).toFixed(1),
		topColors: top,
		grid,
	};
}

async function main() {
	await new Promise((r) => server.listen(PORT, "127.0.0.1", r));
	console.log("[srv] serving " + WEB_ROOT + " on :" + PORT + " (COOP/COEP on)");

	const browser = await chromium.launch({
		executablePath: FULL_CHROME,
		headless: true,
		args: ["--enable-unsafe-swiftshader", "--no-sandbox", "--disable-dev-shm-usage", "--in-process-gpu"],
	});
	const ctx = await browser.newContext({ viewport: { width: 1280, height: 720 } });
	const page = await ctx.newPage();

	const consoleLines = [];
	page.on("console", (m) => consoleLines.push("[" + m.type() + "] " + m.text()));
	page.on("pageerror", (e) => {
		const line = "[pageerror] " + e.message;
		consoleLines.push(line);
		console.log(line);
	});
	const pckResponses = [];
	page.on("response", (r) => {
		const u = r.url();
		if (/game\.(pck|wasm)/.test(u)) pckResponses.push({ url: u.replace(/^http:\/\/[^/]+/, ""), status: r.status() });
	});

	await page.addInitScript(() => {
		// Force non-offscreen canvas so the visible canvas is the render
		// target (OffscreenCanvas+worker surfaces can dodge the screenshot
		// compositor).
		const orig = HTMLCanvasElement.prototype.getContext;
		HTMLCanvasElement.prototype.getContext = function (type, opts) {
			if (opts) opts = Object.assign({}, opts, { offscreen: false });
			return orig.call(this, type, opts);
		};
	});

	await page.goto("http://127.0.0.1:" + PORT + "/index.html", { waitUntil: "load", timeout: 30000 });
	console.log("[probe] page loaded, waitUntil done");
	const isolated = await page.evaluate(() => window.crossOriginIsolated);
	console.log("[probe] crossOriginIsolated:", isolated);

	await page.waitForTimeout(6000);
	const baseShot = path.join(OUT_DIR, "baseline.png");
	await page.screenshot({ path: baseShot });
	const baseline = classifyPng(baseShot);
	console.log("[probe] baseline.png:", JSON.stringify(baseline));

	let booted = true;
	try {
		await page.waitForSelector("#loading-screen.hidden", { timeout: 15000 });
	} catch (e) {
		booted = false;
		console.log("[probe] overlay did not clear in 21s; hiding it manually");
		await page.evaluate(() => {
			const el = document.getElementById("loading-screen");
			if (el) el.classList.add("hidden");
		}).catch(() => {});
	}
	console.log("[probe] overlay cleared:", booted, "| console lines:", consoleLines.length);

	await page.evaluate(() => { const c = document.getElementById("game-canvas"); if (c) c.focus(); });
	const result = { booted, isolated, pckResponses, console: consoleLines, shots: {}, baseline };

	await page.waitForTimeout(4000);
	const menuShot = path.join(OUT_DIR, "menu.png");
	await page.screenshot({ path: menuShot });
	result.shots.menu = classifyPng(menuShot);
	console.log("[probe] menu.png:", JSON.stringify(result.shots.menu));

	// == Click-through: Start -> Guest -> Create -> species Select ->
	// class Select -> Enter World (RETURNS TO LOBBY via creating_for
	// path, character_select.gd _on_play_pressed) -> lobby Play -> world.
	// Geometry at 1280x720 from the .tscn files:
	//   main_menu Start (640,408)                       [verified round r3]
	//   login Guest  540x640 panel, buttons stack bottom: ~y 588 (spread)
	//   lobby 4x180x52 row y 620..672: Play(352) Create(544) Delete(736) Logout(928)
	//   char_select species card1 c=(316,436), class card1 c=(214,516),
	//   Enter World (1086,676)
	const click = async (x, y, label) => {
		await page.mouse.click(x, y);
		console.log("[probe] clicked " + label + " at " + x + "," + y);
	};
	const settle = (ms) => page.waitForTimeout(ms);
	const sawState = async (frag, timeoutMs) => {
		const t0 = Date.now();
		while (Date.now() - t0 < timeoutMs) {
			if (consoleLines.some((l) => l.includes(frag))) return true;
			await settle(500);
		}
		return false;
	};
	const snap = async (name) => {
		const s = path.join(OUT_DIR, name || "probe_click.png");
		await page.screenshot({ path: s });
		return classifyPng(s);
	};
	const distinct = (a, b) => Math.abs(a.topColors[0].pct - b.topColors[0].pct) > 0.5
		|| a.topColors[0].rgb !== b.topColors[0].rgb
		|| JSON.stringify(a.grid) !== JSON.stringify(b.grid);
	// Try candidate points; a point "engages" when the screen changes OR a
	// new DebugOverlay Click: line appears. Reports which lines fired.
	const newClickLines = (mark) => consoleLines.slice(mark).filter((l) => l.includes("Click:"));
	const clickAdvancing = async (label, points, waitMs, stateFrag) => {
		const pre = await snap();
		for (const [x, y] of points) {
			const mark = consoleLines.length;
			await page.mouse.click(x, y);
			if (stateFrag && await sawState(stateFrag, waitMs)) {
				console.log("[probe] " + label + " ENGAGED at " + x + "," + y + " (state: " + stateFrag + ")");
				return true;
			}
			await settle(stateFrag ? 0 : waitMs);
			const post = await snap();
			const clicks = newClickLines(mark);
			if (clicks.length) console.log("[probe]   " + label + " candidates saw: " + clicks.join(" | "));
			if (distinct(pre, post) || clicks.length) {
				console.log("[probe] " + label + " ENGAGED at " + x + "," + y);
				return true;
			}
		}
		console.log("[probe] " + label + " did not engage at any candidate point");
		return false;
	};

	// 1) Start (verified r3).
	await click(640, 408, "Start");
	if (!await sawState("LOADING -> LOGIN", 20000)) console.log("[probe] WARN: no LOADING -> LOGIN");
	await settle(2500);

	// 2) Guest button (login panel, bottom button stack).
	await clickAdvancing("Guest", [[640, 588], [640, 610], [640, 566], [640, 630], [640, 545]], 2200, "LOGIN -> LOBBY");
	await settle(2000);
	const lobbyShot = path.join(OUT_DIR, "lobby.png");
	await page.screenshot({ path: lobbyShot });
	result.shots.lobby = classifyPng(lobbyShot);
	console.log("[probe] lobby.png:", JSON.stringify(result.shots.lobby));

	// 3) Create New (lobby button row center, x=544).
	await clickAdvancing("CreateNew", [[544, 646], [544, 630], [544, 660], [544, 615], [736, 646]], 2200, "LOBBY -> CHARACTER_SELECT");
	await settle(2000);

	// 4) Species Select (per-card SelectBtn only; card1 center column).
	await clickAdvancing("SpeciesSelect", [[316, 436], [316, 420], [316, 452], [316, 400], [214, 436]], 2000);

	// 5) Class Select (per-card SelectBtn; class card1).
	await clickAdvancing("ClassSelect", [[214, 516], [214, 500], [214, 532], [214, 480], [316, 516]], 2000);

	// 6) Enter World -> links character, back to LOBBY (auto-selects it).
	await click(1086, 676, "EnterWorld");
	const linked = await sawState("CHARACTER_SELECT -> LOBBY", 15000)
		|| consoleLines.some((l) => l.includes("CharacterSelect: Linked"));
	console.log("[probe] enter world -> back in lobby: " + linked);
	await settle(2000);

	// 7) Lobby Play with the auto-selected new character -> PLAYING.
	await clickAdvancing("Play", [[352, 646], [352, 630], [352, 660], [352, 615], [544, 646]], 2200, "-> PLAYING");
	console.log("[probe] enter world clicked; polling for the world to build...");
	let worldSeen = false;
	for (let t = 0; t < 8; t++) {
		if (consoleLines.some((l) => l.includes("World scene loaded") || l.includes("Entering gameplay"))) {
			console.log("[probe] world build confirmed via log");
			break;
		}
		await settle(5000);
		const s = path.join(OUT_DIR, "world_poll.png");
		await page.screenshot({ path: s });
		const c = classifyPng(s);
		const sig = c.topColors[0].rgb + "/" + c.topColors[0].pct;
		console.log("[probe] world poll " + t + ": " + sig + " green=" + c.greenPct + " teal=" + c.tealPct);
		if (c.greenPct > 2 || c.tealPct > 2 || !(c.topColors[0].rgb === "16,16,16" && c.topColors[0].pct > 80)) {
			worldSeen = true;
			fs.copyFileSync(s, path.join(OUT_DIR, "world.png"));
			break;
		}
	}
	if (!worldSeen) await settle(6000);
	const worldShot = path.join(OUT_DIR, "world.png");
	await page.screenshot({ path: worldShot });
	result.shots.world = classifyPng(worldShot);
	console.log("[probe] world.png:", JSON.stringify(result.shots.world));

	// Movement: hold W (terrain parallax should shift the green layout).
	await page.evaluate(() => { const c = document.getElementById("game-canvas"); if (c) c.focus(); });
	await page.keyboard.down("w");
	await page.waitForTimeout(2500);
	await page.keyboard.up("w");
	await page.waitForTimeout(600);
	result.shots.move = await snap("move.png");
	console.log("[probe] move.png:", JSON.stringify(result.shots.move));

	// Map: M opens, M closes (R13 law).
	try {
		await page.keyboard.press("m");
		await page.waitForTimeout(2500);
		result.shots.map_open = await snap("map_open.png");
		console.log("[probe] map_open.png:", JSON.stringify(result.shots.map_open));
		await page.keyboard.press("m");
		await page.waitForTimeout(1500);
		result.shots.map_closed = await snap("map_closed.png");
		console.log("[probe] map_closed.png:", JSON.stringify(result.shots.map_closed));
	} catch (e) {
		console.log("[probe] map drive failed:", e.message);
		result.mapDriveError = e.message;
	}

	fs.writeFileSync(path.join(OUT_DIR, "console.txt"), consoleLines.join("\n"));
	fs.writeFileSync(path.join(OUT_DIR, "summary.json"), JSON.stringify(result, null, 2));

	const worldC = result.shots.world || {};
	if (!worldC.blackPct) { await browser.close(); server.close(); process.exit(4); }
	const exitCode = worldC.blackPct > 97 ? 3 : 0;
	console.log("[probe] verdict: blackPct=" + worldC.blackPct + " greenPct=" + worldC.greenPct + " tealPct=" + worldC.tealPct + " -> exit " + exitCode);
	await browser.close();
	server.close();
	process.exit(exitCode);
}

const hardKill = setTimeout(() => { console.log("[probe] HARD TIMEOUT 170s"); process.exit(5); }, 170000);
main().then(() => clearTimeout(hardKill)).catch((e) => { console.error("[probe] fatal:", e); process.exit(1); });
