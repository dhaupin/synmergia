// Synmergia mount-journey acceptance probe (R47, labs/prd-mounts.md).
// The a11y journey plus the stable: the SAME stream drives guest ->
// world -> menu bar -> the Mounts panel -> BUY the starter mount
// (lawful: role 0 spawns with 500 gold; the Meadow Pacer costs 150,
// level 1) -> summon -> the walk -> the air-tap demount. The game's
// own GameLog audit marks are the oracles (RideService's
// purchased/summoned/dismissed trio); no coordinates, no cheats --
// the product must carry the probe the way it carries a player.
// Run from the repo root:  xvfb-run -a node scripts/web_probe/probe_mount_journey.js
const http = require("http");
const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright-core");
const WEB = process.env.PROBE_WEB || path.join(process.cwd(), "web");
const PORT = Number(process.env.PROBE_PORT) || 8136;
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
let enteringCount = 0; // count-based: the SECOND world load must be observable (the Set only remembers the first)
const errors = [];
const T0 = Date.now();
// 420s: the R48 journey is TWO world loads (the reload leg boots the
// whole engine a second time) -- at software-GL fps the old 280s
// budget collapsed the final world window to seconds.
const left = () => 420000 - (Date.now() - T0);
function ingest(t) {
	if (t.startsWith("[A11Y]")) {
		try { const e = JSON.parse(t.slice(6)); if (e && e.action) actions.set(e.action, e); } catch {}
		return true;
	}
	if (/WorldPlayable: player registered/.test(t)) marks.add("registered");
	else if (/RideService: mount purchased/.test(t)) marks.add("bought");
	else if (/RideService: mount summoned/.test(t)) marks.add("summoned");
	else if (/RideService: mount dismissed/.test(t)) marks.add("dismounted");
	else if (/Entering gameplay/.test(t)) { marks.add("entering"); enteringCount++; }
	else if (/Click: StartButton/.test(t)) marks.add("start-clicked");
	else if (/Click: GuestButton/.test(t)) marks.add("guest-clicked");
	else if (/Linked new character/.test(t)) marks.add("char-linked");
	else if (/SCRIPT ERROR/.test(t)) errors.push(t.slice(0, 140));
	else if (/WebIdBridge:/.test(t)) console.log("BRIDGE:", t.slice(0, 100));
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
		if (!mark || await waitForMark(mark, 9000)) { console.log(label, "OK:", found.label); return true; }
	}
	console.log("FAIL:", label, "clicks never verified");
	return false;
};
let page = null;
function ACTIONS_NOW() { return "ACTIONS_NOW: " + JSON.stringify(Array.from(actions.keys())) + " "; }
(async () => {
	await new Promise((r) => server.listen(PORT, "127.0.0.1", r));
	const launchOpts = { headless: false, args: ["--no-sandbox", "--disable-dev-shm-usage", "--disable-gpu-sandbox", "--enable-unsafe-swiftshader"] };
	if (process.env.PROBE_CHROME) launchOpts.executablePath = process.env.PROBE_CHROME;
	const browser = await chromium.launch(launchOpts);
	// 1280x720 is the calibrated rig: the a11y rects are canvas-space,
	// and a smaller CSS window desyncs them from page coordinates (a
	// logical-viewport stretch rescales the canvas -- clicks landed 2x
	// off at 640x360). The fps lever is NOT a viewport squeeze.
	page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
	page.on("console", (m) => ingest(m.text()));
	page.on("pageerror", (e) => errors.push("pageerror: " + e.message.slice(0, 140)));

	await page.goto("http://127.0.0.1:" + PORT + "/index.html", { waitUntil: "load", timeout: 30000 });
	if (!await clickAction((l) => l === "Start playing", "start-clicked", 3, "STEP1 start")) { console.log("RESULT: FAIL(start)"); await browser.close(); server.close(); process.exit(1); }
	if (!await clickAction((l) => l === "Play without an account", "guest-clicked", 3, "STEP2 guest")) { console.log("RESULT: FAIL(guest)"); await browser.close(); server.close(); process.exit(1); }
	if (!await clickAction((l) => l === "Create New", null, 2, "STEP3 create-new")) { console.log("RESULT: FAIL(create)"); await browser.close(); server.close(); process.exit(1); }
	// The char-list screen can swallow a click at slow fps: retry the
	// Create New press until the species buttons announce.
	let species = await waitForAction((l) => /^Choose /.test(l), 45000);
	for (let attempt = 0; attempt < 3 && !species; attempt++) {
		await clickAction((l) => l === "Create New", null, 2, "STEP3b retry");
		species = await waitForAction((l) => /^Choose /.test(l), 30000);
	}
	if (!species) { console.log(ACTIONS_NOW(), "RESULT: FAIL(no-species)"); await browser.close(); server.close(); process.exit(1); }
	console.log("STEP4 species:", species.label);
	await clickAction((l) => l === species.label, null, 2, "STEP5 species clicked");
	// The species->class hop is the slow-fps pinch: re-click species
	// until the class actions announce (stale a11y entries linger in
	// the map, so presence of old labels is not screen truth).
	let klass = await waitForAction((l) => /^Play /.test(l) && l !== "Play without an account" && l !== "Play selected character", 30000);
	for (let attempt = 0; attempt < 3 && !klass; attempt++) {
		await clickAction((l) => l === species.label, null, 2, "STEP5b species retry");
		klass = await waitForAction((l) => /^Play /.test(l) && l !== "Play without an account" && l !== "Play selected character", 25000);
	}
	if (!klass) { console.log(ACTIONS_NOW(), "RESULT: FAIL(no-class)"); await browser.close(); server.close(); process.exit(1); }
	console.log("STEP6 class:", klass.label);
	await clickAction((l) => l === klass.label, null, 2, "STEP7 class clicked");
	if (!await clickAction((l) => l === "Enter World", "char-linked", 3, "STEP8 enter-world")) { console.log("RESULT: FAIL(enter)"); await browser.close(); server.close(); process.exit(1); }
	// The world is THE gate for everything after this point. GameLog
	// marks can be dropped by wasm stdout batching at slow fps, so the
	// gate is the a11y stream's own truth: the in-world HUD's "=" menu
	// button exists ONLY once the world is live (MainMenuBar rides
	// HudLayer). The registered mark is recorded as bonus evidence.
	const wEnd = Date.now() + Math.min(90000, left() - 45000);
	let worldLive = false;
	while (Date.now() < wEnd && !worldLive) {
		if (marks.has("registered")) { worldLive = true; break; }
		if (await waitForAction((l) => l === "=", 2500)) worldLive = true;
	}
	console.log("STEP9 world-live:", worldLive, "registered-mark:", marks.has("registered"));
	if (!worldLive) { console.log("MARKS:", JSON.stringify(Array.from(marks)), "ERRORS:", JSON.stringify(errors.slice(0, 5)), "RESULT: FAIL(world)"); await browser.close().catch(() => {}); server.close(); process.exit(1); }
	// Let the spawn settle, then walk forward a beat (the walk leg;
	// W for a few seconds is a plain gallop once mounted).
	await page.keyboard.down("w");
	await page.waitForTimeout(4000);
	await page.keyboard.up("w");
	console.log("STEP10 walked");
	// Open the menu bar (the "=" button -- the a11y label law is
	// annotation, then text, so the icon button announces as "="), then
	// click the Mounts item (announced as "[U] Mounts  [U]"). The panel
	// is verified by APPEARANCE: the shop's Buy actions arriving.
	if (!await clickAction((l) => l === "=", null, 3, "STEP11 open menu")) { console.log(ACTIONS_NOW(), "RESULT: FAIL(no-menu)"); await browser.close(); server.close(); process.exit(1); }
	const mountsItem = await waitForAction((l) => /\bMounts\b/.test(l) && l.includes("[U]"), 15000);
	if (!mountsItem) { console.log(ACTIONS_NOW(), "RESULT: FAIL(no-mounts-item)"); await browser.close(); server.close(); process.exit(1); }
	let shopOpen = await waitForAction((l) => l.startsWith("Buy "), 8000);
	for (let attempt = 0; attempt < 3 && !shopOpen; attempt++) {
		const mr = mountsItem.e.rect;
		await page.mouse.click(mr.x + mr.w / 2, mr.y + mr.h / 2);
		shopOpen = await waitForAction((l) => l.startsWith("Buy "), 12000);
	}
	if (!shopOpen) { console.log(ACTIONS_NOW(), "RESULT: FAIL(shop-closed)"); await browser.close(); server.close(); process.exit(1); }
	console.log("STEP12 stable open:", mountsItem.label);
	// BUY the starter in the shop window. The oracle is the LABEL
	// TRANSITION (batching-proof a11y truth): the shop's "Buy Meadow
	// Pacer" becomes the owned row's "Ride Meadow Pacer" -- which no
	// screen shows before ownership. The predicate is the EXACT label:
	// the shop carries three Buy buttons (gullwing, pacer, runner) and
	// a prefix match grabs whichever announced first.
	const buyBtn = await waitForAction((l) => l === "Buy Meadow Pacer", 12000);
	if (!buyBtn) { console.log(ACTIONS_NOW(), "RESULT: FAIL(no-buy)"); await browser.close(); server.close(); process.exit(1); }
	let ownedRow = null;
	for (let t = 0; t < 3 && !ownedRow; t++) {
		const br = buyBtn.e.rect;
		await page.mouse.click(br.x + br.w / 2, br.y + br.h / 2);
		ownedRow = await waitForAction((l) => l === "Ride Meadow Pacer", 12000);
	}
	if (!ownedRow) { console.log(ACTIONS_NOW(), "MARKS:", JSON.stringify(Array.from(marks)), "RESULT: FAIL(no-owned-row)"); await browser.close(); server.close(); process.exit(1); }
	console.log("STEP13 bought the Meadow Pacer:", marks.has("bought") ? "audit-mark OK" : "label-transition OK");
	// RIDE it: the active row flips to "Dismiss Meadow Pacer".
	let activeRow = null;
	for (let t = 0; t < 3 && !activeRow; t++) {
		const or = ownedRow.e.rect;
		await page.mouse.click(or.x + or.w / 2, or.y + or.h / 2);
		activeRow = await waitForAction((l) => l === "Dismiss Meadow Pacer", 12000);
	}
	if (!activeRow) { console.log(ACTIONS_NOW(), "MARKS:", JSON.stringify(Array.from(marks)), "RESULT: FAIL(no-active-row)"); await browser.close(); server.close(); process.exit(1); }
	console.log("STEP14 mounted:", marks.has("summoned") ? "audit-mark OK" : "label-transition OK");
	// THE GALLOP: hold W through the mounted frames (the frozen-saddle
	// fix's live proof -- the body must integrate and move).
	await page.keyboard.down("w");
	await page.waitForTimeout(5000);
	await page.keyboard.up("w");
	console.log("STEP15 galloped");
	// Jump in the air -> the air-tap demount ("press jump in air to
	// glide, demounts if mounted"): jump, then tap jump again at apex.
	await page.keyboard.press("Space");
	await page.waitForTimeout(700);
	await page.keyboard.press("Space");
	await page.waitForTimeout(2500);
	// The dismount oracle: the row flips BACK to "Ride Meadow Pacer"
	// (active -> idle) -- the saddle's air-tap law, read off the panel.
	const backToIdle = await waitForAction((l) => l === "Ride Meadow Pacer", 15000);
	console.log("STEP16 air-tap demount:", backToIdle ? "label-transition OK" : "NOT observed", "audit-mark:", marks.has("dismounted"));
	if (!backToIdle) { console.log(ACTIONS_NOW(), "MARKS:", JSON.stringify(Array.from(marks)), "RESULT: FAIL(no-dismount)"); await browser.close().catch(() => {}); server.close(); process.exit(1); }

	// R48 THE RELOAD LEG: the ownership ledger must survive a page
	// reload. Reload, boot again, press the SAME guest button (which
	// now reads "Continue as guest" -- WebIdBridge remembers the id in
	// browser local storage), enter the world, open the stable, and
	// the owned row must be there WITHOUT a second buy. The pacer row
	// is the oracle: ownership is ledger truth, session-riding is not.
	console.log("STEP17 reloading the page...");
	actions.clear();
	await page.reload({ waitUntil: "load", timeout: 30000 });
	if (!await clickAction((l) => l === "Start playing", null, 3, "STEP18 start-again")) { console.log(ACTIONS_NOW(), "RESULT: FAIL(restart)"); await browser.close(); server.close(); process.exit(1); }
	// The resume door: the guest button relabeled when the user://
	// identity file survived (WebIdBridge v2 -- NOT localStorage, which
	// failed silently through Godot's JS-worker bridge). Failing back
	// to the plain label is a soft miss; the ledger oracle below is
	// the hard law either way.
	const resumeLabel = await waitForAction((l) => l === "Continue as guest" || l === "Play without an account", 25000);
	console.log("STEP19 guest door:", resumeLabel ? resumeLabel.label : "(no door announced)");
	if (!await clickAction((l) => l === "Continue as guest" || l === "Play without an account", null, 3, "STEP20 resume-guest")) { console.log(ACTIONS_NOW(), "RESULT: FAIL(resume)"); await browser.close(); server.close(); process.exit(1); }
	// Step 20 pressed the guest door. The resumed lobby lists the old
	// character ("Play selected character") AND volunteers the class-
	// select "Enter World" hop EITHER way: the resumed path can stay in
	// the lobby (old character -> Enter World) or come back through the
	// class-select card. Both roads end with the world gate below.
	const resumeChar = await waitForAction((l) => l === "Play selected character", 25000);
	console.log("STEP21 old character listed:", resumeChar ? "yes" : "NO (fresh guest)");
	if (resumeChar) {
		await clickAction((l) => l === "Play selected character", null, 2, "STEP22a play-selected");
		// The class-select hop may reappear on the resumed path (slow fps:
		// give it a wide window -- the first run's STEP8 needed it too).
		const ew = await waitForAction((l) => l === "Enter World", 35000);
		if (ew) {
			console.log("STEP22b Enter World hop (class-select)");
			if (!await clickAction((l) => l === "Enter World", null, 3, "STEP22c enter-world-again")) { console.log(ACTIONS_NOW(), "RESULT: FAIL(reenter)"); await browser.close(); server.close(); process.exit(1); }
		}
	}
	const w2End = Date.now() + Math.min(120000, left() - 30000);
	let world2Live = false;
	while (Date.now() < w2End && !world2Live) {
		if (enteringCount >= 2) { world2Live = true; break; }
		if (await waitForAction((l) => l === "=", 2500)) world2Live = true;
	}
	console.log("STEP24 world-live-again:", world2Live, "entering-count:", enteringCount);
	if (!world2Live) { await page.screenshot({ path: "/tmp/syn_mj_world2_stuck.png" }); console.log("MARKS:", JSON.stringify(Array.from(marks)), "ERRORS:", JSON.stringify(errors.slice(0, 5)), "RESULT: FAIL(world2)"); await browser.close().catch(() => {}); server.close(); process.exit(1); }
	// Open the stable: the owned row must appear WITHOUT any Buy press.
	const rideRow2 = await waitForAction((l) => l === "Ride Meadow Pacer", 6000);
	if (!await clickAction((l) => l === "=", null, 3, "STEP25 open menu again")) { console.log(ACTIONS_NOW(), "RESULT: FAIL(no-menu2)"); await browser.close(); server.close(); process.exit(1); }
	const mountsItem2 = await waitForAction((l) => /\bMounts\b/.test(l) && l.includes("[U]"), 15000);
	if (!mountsItem2) { console.log(ACTIONS_NOW(), "RESULT: FAIL(no-mounts-item2)"); await browser.close(); server.close(); process.exit(1); }
	let survivedRow = rideRow2;
	if (!survivedRow) survivedRow = await waitForAction((l) => l === "Ride Meadow Pacer", 8000);
	for (let attempt = 0; attempt < 3 && !survivedRow; attempt++) {
		const mr2 = mountsItem2.e.rect;
		await page.mouse.click(mr2.x + mr2.w / 2, mr2.y + mr2.h / 2);
		survivedRow = await waitForAction((l) => l === "Ride Meadow Pacer", 12000);
	}
	console.log("STEP26 ownership survived the reload:", survivedRow ? "YES" : "NO");
	await page.screenshot({ path: "/tmp/syn_mj_final.png" });
	console.log("MARKS:", JSON.stringify(Array.from(marks)));
	console.log("ACTIONS_SEEN:", actions.size);
	console.log("ERRORS:", JSON.stringify(errors.slice(0, 5)));
	const pass = survivedRow && errors.length === 0;
	console.log("RESULT:", pass ? "PASS" : "FAIL");
	await browser.close().catch(() => {});
	server.close();
	process.exit(pass ? 0 : 1);
})();
