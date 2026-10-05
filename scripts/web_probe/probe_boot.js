// Live WASM boot probe for the Synmergia web export.
// Serves <repo>/web with COOP/COEP (the threaded Godot build requires
// cross-origin isolation), then drives a chromium build:
// loads the page, watches the console for the engine banner, and
// screenshots whatever renders. Exit 0 = engine booted.
// Run from the repo root:  xvfb-run -a node scripts/web_probe/probe_boot.js
// Env: PROBE_CHROME (chromium binary; default: playwright browser cache),
//      PROBE_PORT (default 8123), PROBE_WEB (default <cwd>/web).
const http = require("http");
const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright-core");

const WEB = process.env.PROBE_WEB || path.join(process.cwd(), "web");
const PORT = Number(process.env.PROBE_PORT) || 8123;

const MIME = { ".html": "text/html", ".css": "text/css", ".js": "text/javascript", ".wasm": "application/wasm", ".pck": "application/octet-stream", ".png": "image/png", ".svg": "image/svg+xml", ".json": "application/json" };

const server = http.createServer((req, res) => {
	let p = decodeURIComponent(req.url.split("?")[0]);
	if (p === "/") p = "/index.html";
	const file = path.join(WEB, p);
	if (!file.startsWith(WEB) || !fs.existsSync(file) || !fs.statSync(file).isFile()) {
		res.writeHead(404); res.end("nope"); return;
	}
	res.writeHead(200, {
		"Content-Type": MIME[path.extname(file)] || "application/octet-stream",
		"Cross-Origin-Opener-Policy": "same-origin",
		"Cross-Origin-Embedder-Policy": "require-corp",
		"Cache-Control": "no-cache",
	});
	fs.createReadStream(file).pipe(res);
});

const consoleLines = [];
const failures = [];

(async () => {
	await new Promise((r) => server.listen(PORT, "127.0.0.1", r));
	const launchOpts = {
		headless: false,
		args: ["--no-sandbox", "--disable-dev-shm-usage", "--disable-gpu-sandbox", "--enable-unsafe-swiftshader"],
	};
	if (process.env.PROBE_CHROME) launchOpts.executablePath = process.env.PROBE_CHROME;
	const browser = await chromium.launch(launchOpts);
	const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
	page.on("console", (m) => consoleLines.push("[" + m.type() + "] " + m.text()));
	page.on("pageerror", (e) => failures.push("pageerror: " + e.message));
	page.on("requestfailed", (r) => failures.push("reqfail: " + r.url() + " " + (r.failure() || {}).errorText));

	let booted = false;
	try {
		await page.goto("http://127.0.0.1:" + PORT + "/index.html", { waitUntil: "load", timeout: 30000 });
		for (let i = 0; i < 37 && !booted; i++) {
			await page.waitForTimeout(2000);
			const state = await page.evaluate(() => {
				const loading = document.getElementById("status");
				const canvas = document.querySelector("canvas");
				return {
					loadingText: loading ? loading.textContent.trim().slice(0, 120) : "(no #status)",
					hasCanvas: !!canvas,
					crossIsolated: !!window.crossOriginIsolated,
				};
			});
			booted = state.hasCanvas && state.crossIsolated && consoleLines.some((l) => /Godot Engine v/.test(l));
			if (i === 2) console.log("poll4s:", JSON.stringify(state));
			if (i === 9) console.log("poll20s:", JSON.stringify(state));
		}
		const final = await page.evaluate(() => ({
			loadingText: (document.getElementById("status") || {}).textContent,
			bodySnippet: document.body.innerText.replace(/\s+/g, " ").slice(0, 300),
		}));
		await page.screenshot({ path: "/tmp/syn_wasm.png" });
		await page.keyboard.press("Enter").catch(() => {});
		await page.waitForTimeout(1500);
		await page.screenshot({ path: "/tmp/syn_wasm_key.png" });
		console.log("BOOTED:", booted);
		console.log("FINAL:", JSON.stringify(final));
	} catch (e) {
		failures.push("harness: " + e.message);
	}
	console.log("--- console tail ---");
	for (const l of consoleLines.slice(-25)) console.log(l);
	console.log("--- failures ---");
	for (const f of failures.slice(0, 12)) console.log(f);
	console.log("RESULT:", booted ? "PASS" : "FAIL");
	await browser.close().catch(() => {});
	server.close();
	process.exit(booted ? 0 : 1);
})();
