// Synmergia web export acceptance probe (PRD rounds 1-3).
// Navigates the live WASM game using ONLY the A11yService [A11Y] JSON
// stream: actions are discovered by name, clicked at their REPORTED
// rects, and every hop is verified through the game's own log marks.
// No hardcoded coordinates anywhere (labs/prd-accessibility.md sec 10).
// Run from the repo root:  xvfb-run -a node scripts/web_probe/probe_a11y.js
// Env: PROBE_CHROME (chromium binary; default: playwright browser cache),
//      PROBE_PORT (default 8134), PROBE_WEB (default <cwd>/web).
const http = require("http");
const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright-core");
const WEB = process.env.PROBE_WEB || path.join(process.cwd(), "web");
const PORT = Number(process.env.PROBE_PORT) || 8134;
const MIME = { ".html": "text/html", ".css": "text/css", ".js": "text/javascript", ".wasm": "application/wasm", ".pck": "application/octet-stream", ".png": "image/png", ".svg": "image/svg+xml" };
const server = http.createServer((req, res) => {
	let p = decodeURIComponent(req.url.split("?")[0]); if (p === "/") p = "/index.html";
	const file = path.join(WEB, p);
	if (!file.startsWith(WEB) || !fs.existsSync(file) || !fs.statSync(file).isFile()) { res.writeHead(404); res.end(); return; }
	res.writeHead(200, { "Content-Type": MIME[path.extname(file)] || "application/octet-stream", "Cross-Origin-Opener-Policy": "same-origin", "Cross-Origin-Embedder-Policy": "require-corp", "Cache-Control": "no-cache" });
	fs.createReadStream(file).pipe(res);
});
const actions = new Map();
const marks = new Set();
const errors = [];
const T0 = Date.now();
const left = () => 260000 - (Date.now() - T0);
function ingest(t) {
	if (t.startsWith("[A11Y]")) {
		try { const e = JSON.parse(t.slice(6)); if (e && e.action) actions.set(e.action, e); } catch {}
		return true;
	}
	if (/WorldPlayable: player registered/.test(t)) marks.add("registered");
	else if (/WorldPlayable: Spawning/.test(t)) marks.add("spawning");
	else if (/Entering gameplay/.test(t)) marks.add("entering");
	else if (/Game paused/.test(t)) marks.add("paused");
	else if (/Game resumed/.test(t)) marks.add("resumed");
	else if (/Click: StartButton/.test(t)) marks.add("start-clicked");
	else if (/Click: GuestButton/.test(t)) marks.add("guest-clicked");
	else if (/Linked new character/.test(t)) marks.add("char-linked");
	else if (/SCRIPT ERROR/.test(t)) errors.push(t.slice(0, 140));
	return false;
}
const waitForMark = async (tag, ms) => {
	const end = Date.now() + Math.min(ms, left());
	while (Date.now() < end) { if (marks.has(tag)) return true; await new Promise((r) => setTimeout(r, 300)); }
	return marks.has(tag);
};
const waitForAction = async (pred, ms) => {
	const end = Date.now() + Math.min(ms, left());
	while (Date.now() < end) {
		for (const [label, e] of actions) if (pred(label, e)) return { label, e };
		await new Promise((r) => setTimeout(r, 400));
	}
	return null;
};
const clickAction = async (pred, mark, tries, label) => {
	const found = await waitForAction(pred, 22000);
	if (!found) { console.log("FAIL: no action for", label); return false; }
	for (let t = 0; t < tries; t++) {
		const r = found.e.rect;
		await page.mouse.click(r.x + r.w / 2, r.y + r.h / 2);
		if (!mark || await waitForMark(mark, 5000)) { console.log(label, "OK:", found.label); return true; }
	}
	console.log("FAIL:", label, "clicks never verified");
	return false;
};
let page = null;
(async () => {
	await new Promise((r) => server.listen(PORT, "127.0.0.1", r));
	const launchOpts = { headless: false, args: ["--no-sandbox", "--disable-dev-shm-usage", "--disable-gpu-sandbox", "--enable-unsafe-swiftshader"] };
	if (process.env.PROBE_CHROME) launchOpts.executablePath = process.env.PROBE_CHROME;
	const browser = await chromium.launch(launchOpts);
	page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
	page.on("console", (m) => ingest(m.text()));
	page.on("pageerror", (e) => errors.push("pageerror: " + e.message.slice(0, 140)));
	await page.goto("http://127.0.0.1:" + PORT + "/index.html", { waitUntil: "load", timeout: 30000 });
	// 1. Menu announces; Start (verified via the game's click log).
	if (!await clickAction((l) => l === "Start playing", "start-clicked", 3, "STEP1 start")) { console.log("RESULT: FAIL(start)"); await browser.close(); server.close(); process.exit(1); }
	// 2. Guest login.
	if (!await clickAction((l) => l === "Play without an account", "guest-clicked", 3, "STEP2 guest")) { console.log("RESULT: FAIL(guest)"); await browser.close(); server.close(); process.exit(1); }
	// 3. Lobby announced itself (the layer's own report is the oracle).
	const lobby = await waitForAction((l) => l === "Create New", 25000);
	if (!lobby) { console.log("RESULT: FAIL(no-lobby)"); await browser.close(); server.close(); process.exit(1); }
	console.log("STEP3 lobby announced");
	await page.screenshot({ path: "/tmp/syn_a1_lobby.png" });
	// 4. Create New -> character select announced by species choices.
	if (!await clickAction((l) => l === "Create New", null, 2, "STEP4 create-new")) { console.log("RESULT: FAIL(create)"); await browser.close(); server.close(); process.exit(1); }
	const species = await waitForAction((l) => /^Choose /.test(l), 22000);
	if (!species) { console.log(ACTIONS_NOW(), "RESULT: FAIL(no-species)"); await browser.close(); server.close(); process.exit(1); }
	console.log("STEP5 species actions arrived:", species.label);
	await page.screenshot({ path: "/tmp/syn_a1_charsel.png" });
	// 5. Pick species; classes announce; pick the first class.
	await clickAction((l) => l === species.label, null, 2, "STEP5b species clicked");
	const klass = await waitForAction((l, e) => /^Play /.test(l) && l !== "Play without an account" && l !== "Play selected character", 22000);
	if (!klass) { console.log(ACTIONS_NOW(), "RESULT: FAIL(no-class)"); await browser.close(); server.close(); process.exit(1); }
	console.log("STEP6 class action arrived:", klass.label);
	await clickAction((l) => l === klass.label, null, 2, "STEP6b class clicked");
	// 6. Enter World -> the lobby auto-plays -> world.
	if (!await clickAction((l) => l === "Enter World", "char-linked", 3, "STEP7 enter-world")) { console.log("RESULT: FAIL(enter)"); await browser.close(); server.close(); process.exit(1); }
	// 7. World registration is THE oracle.
	const wEnd = Date.now() + Math.min(150000, left() - 15000);
	while (Date.now() < wEnd && !marks.has("registered")) await new Promise((r) => setTimeout(r, 500));
	console.log("STEP8 world-registered:", marks.has("registered"), "spawning:", marks.has("spawning"));
	await page.waitForTimeout(8000);
	await page.screenshot({ path: "/tmp/syn_a1_world.png" });
	// 8. Pause/resume through real keys.
	if (left() > 30000) {
		await page.keyboard.press("Escape");
		const pEnd = Date.now() + 10000;
		while (Date.now() < pEnd && !marks.has("paused")) await new Promise((r) => setTimeout(r, 400));
		await page.screenshot({ path: "/tmp/syn_a1_paused.png" });
		await page.keyboard.press("Escape");
		const rEnd = Date.now() + 10000;
		while (Date.now() < rEnd && !marks.has("resumed")) await new Promise((r) => setTimeout(r, 400));
		console.log("STEP9 pause/resume:", marks.has("paused"), marks.has("resumed"));
		await page.screenshot({ path: "/tmp/syn_a1_resumed.png" });
	}
	// 9. In-world entity actions (PRD round 3): the snapshot must carry
	// kind=entity entries ("Attack <name>") and activate() must dispatch
	// them. Spawn-dependent, so absence is reported, not hard-failed --
	// the damage path itself is pinned by game/tests/test_a11y_service.gd.
	const entity = await waitForAction((l, e) => e && e.kind === "entity", 30000);
	if (entity) {
		console.log("STEP10 entity action:", entity.label);
		const er = entity.e.rect;
		await page.mouse.click(er.x + er.w / 2, er.y + er.h / 2);
		await page.waitForTimeout(2500);
		console.log("STEP10b entity activated; script errors so far:", errors.length);
	} else {
		console.log("STEP10 entity actions: none announced in range (world-dependent)");
	}
	const reached = marks.has("registered");
	console.log("MARKS:", JSON.stringify(Array.from(marks)));
	console.log("ACTIONS_SEEN:", actions.size);
	console.log("ERRORS:", JSON.stringify(errors.slice(0, 5)));
	console.log("RESULT:", reached && errors.length === 0 ? "PASS" : "FAIL");
	await browser.close().catch(() => {});
	server.close();
	process.exit(reached && errors.length === 0 ? 0 : 1);
})();
function ACTIONS_NOW() { return "ACTIONS_NOW: " + JSON.stringify(Array.from(actions.keys())) + " "; }
