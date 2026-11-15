// Synmergia web export acceptance probe.
// Navigates the live WASM game using ONLY the A11yService [A11Y] JSON
// stream: actions are discovered by handle, clicked at their REPORTED
// rects, and every hop is verified through the game's own log marks.
// No hardcoded coordinates anywhere (labs/prd-accessibility.md sec 10).
//
// Guest play is RETIRED; accounts are email-bound. The journey is
// register -> lobby -> Create New -> species -> class -> Enter World,
// then a pixel check that the 3D world and terrain actually DRAW.
// Run from the repo root:  xvfb-run -a node scripts/web_probe/probe_a11y.js
// Env: PROBE_CHROME (chromium binary; default: playwright browser cache),
//      PROBE_PORT (default 8134), PROBE_WEB (default <cwd>/web),
//      PROBE_OUT (default /tmp).
const http = require("http");
const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright-core");
const WEB = process.env.PROBE_WEB || path.join(process.cwd(), "web");
const PORT = Number(process.env.PROBE_PORT) || 8134;
const OUT = process.env.PROBE_OUT || "/tmp";
const MIME = { ".html": "text/html", ".css": "text/css", ".js": "text/javascript", ".wasm": "application/wasm", ".pck": "application/octet-stream", ".png": "image/png", ".svg": "image/svg+xml" };
const server = http.createServer((req, res) => {
        let p = decodeURIComponent(req.url.split("?")[0]); if (p === "/") p = "/index.html";
        const file = path.join(WEB, p);
        if (!file.startsWith(WEB) || !fs.existsSync(file) || !fs.statSync(file).isFile()) { res.writeHead(404); res.end(); return; }
        res.writeHead(200, { "Content-Type": MIME[path.extname(file)] || "application/octet-stream", "Cross-Origin-Opener-Policy": "same-origin", "Cross-Origin-Embedder-Policy": "require-corp", "Cache-Control": "no-cache" });
        fs.createReadStream(file).pipe(res);
});

// The A11Y service dumps the WHOLE actionable set synchronously in one burst
// whenever it changes. A snapshot is therefore "all [A11Y] lines with no gap":
// buffer them and commit the set as current once the burst goes quiet.
const snap = new Map();
let buffer = [];
let lastA11yAt = 0;
const marks = new Set();
const errors = [];
const raw = [];
const T0 = Date.now();
const left = () => 900000 - (Date.now() - T0);

function commitIfQuiet() {
        if (buffer.length === 0 || Date.now() - lastA11yAt < 300) return;
        snap.clear();
        for (const e of buffer) snap.set(e.id, e);
        buffer = [];
}

function ingest(t) {
        raw.push(t);
        if (t.startsWith("[A11Y]")) {
                try { const e = JSON.parse(t.slice(6)); if (e && e.id) { buffer.push(e); lastA11yAt = Date.now(); } } catch {}
                return true;
        }
        if (/World scene loaded/.test(t)) marks.add("registered");
        else if (/player_entered_world/.test(t)) marks.add("spawning");
        else if (/Entering gameplay/.test(t)) marks.add("entering");
        else if (/Game paused/.test(t)) marks.add("paused");
        else if (/Game resumed/.test(t)) marks.add("resumed");
        else if (/Linked new character/.test(t)) marks.add("char-linked");
        else if (/Game state changed:/.test(t)) marks.add(t.match(/Game state changed:.*/)[0].slice(0, 60));
        else if (/SCRIPT ERROR/.test(t)) errors.push(t.slice(0, 140));
        return false;
}

const findAction = (pred) => {
        commitIfQuiet();
        for (const e of snap.values()) if (pred(e.action, e)) return e;
        return null;
};

const waitAction = async (pred, ms) => {
        const end = Date.now() + Math.min(ms, left());
        while (Date.now() < end) {
                const e = findAction(pred);
                if (e) return e;
                await new Promise((r) => setTimeout(r, 350));
        }
        return null;
};

let page = null;
let browser = null;

// Click the control matching `pred`, then wait until it clears (the screen
// advanced) or `nextPred` shows up. Re-resolves the rect each try because the
// layout can settle between the announce and the click.
const clickAction = async (pred, ms, nextPred = null) => {
        for (let t = 0; t < 6; t++) {
                const e = await waitAction(pred, ms);
                if (!e) continue;
                await page.mouse.click(e.rect.x + e.rect.w / 2, e.rect.y + e.rect.h / 2);
                const end = Date.now() + Math.min(30000, left());
                while (Date.now() < end) {
                        await new Promise((r) => setTimeout(r, 400));
                        if (nextPred && findAction(nextPred)) return e.action;
                        if (!findAction(pred)) return e.action;
                }
        }
        return null;
};

const typeInto = async (nameRe, text) => {
        const e = await waitAction((l) => nameRe.test(l), 30000);
        if (!e) return false;
        await page.mouse.click(e.rect.x + e.rect.w / 2, e.rect.y + e.rect.h / 2);
        await page.keyboard.type(text, { delay: 25 });
        return true;
};

// Pixel classifier, decoded in-page so no image lib is needed. Reports the
// SKY band (top third) and the GROUND band (bottom third) separately: a
// working world has sky up top and land/water below, a dead frame is flat
// black everywhere. Green = land, teal = water (the R13/R14 web draw law).
const classify = async (file) => {
        const buf = await page.screenshot({ path: file });
        return page.evaluate(async (b64) => {
                const img = new Image();
                await new Promise((r) => { img.onload = r; img.src = "data:image/png;base64," + b64; });
                const c = document.createElement("canvas"); c.width = img.width; c.height = img.height;
                const ctx = c.getContext("2d"); ctx.drawImage(img, 0, 0);
                const d = ctx.getImageData(0, 0, c.width, c.height).data;
                const band = (y0, y1) => {
                        let green = 0, teal = 0, dark = 0, n = 0;
                        for (let y = y0; y < y1; y += 3) for (let x = 0; x < c.width; x += 4) {
                                const i = (y * c.width + x) * 4;
                                const r = d[i], g = d[i + 1], b = d[i + 2]; n++;
                                if (r < 40 && g < 40 && b < 40) dark++;
                                else if (g > r + 8 && g > b + 4) green++;
                                else if (b > r + 10 && b > g + 4) teal++;
                        }
                        return { green: +(green / n).toFixed(3), teal: +(teal / n).toFixed(3), dark: +(dark / n).toFixed(3) };
                };
                const h3 = Math.floor(c.height / 3);
                return { sky: band(0, h3), ground: band(h3 * 2, c.height) };
        }, buf.toString("base64"));
};

const bail = async (tag) => {
        console.log("RESULT: FAIL(" + tag + ")");
        console.log("MARKS:", JSON.stringify(Array.from(marks)));
        console.log("ERRORS:", JSON.stringify(errors.slice(0, 6)));
        fs.writeFileSync(OUT + "/syn_a1_console.txt", raw.join("\n"));
        await page.screenshot({ path: OUT + "/syn_a1_fail.png" }).catch(() => {});
        await browser.close().catch(() => {});
        server.close();
        process.exit(1);
};

(async () => {
        await new Promise((r) => server.listen(PORT, "127.0.0.1", r));
        const launchOpts = { headless: false, args: ["--no-sandbox", "--disable-dev-shm-usage", "--disable-gpu-sandbox", "--enable-unsafe-swiftshader"] };
        if (process.env.PROBE_CHROME) launchOpts.executablePath = process.env.PROBE_CHROME;
        browser = await chromium.launch(launchOpts);
        page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
        page.on("console", (m) => ingest(m.text()));
        page.on("pageerror", (e) => errors.push("pageerror: " + e.message.slice(0, 140)));
        await page.goto("http://127.0.0.1:" + PORT + "/index.html", { waitUntil: "load", timeout: 30000 });

        // STEP 1: menu -> login (the one Start button).
        if (!await clickAction((l) => l === "Start playing", 90000, (l) => /Create a new account/.test(l))) return bail("start");
        console.log("STEP1 start -> login OK");
        // STEP 2: login -> register mode.
        if (!await clickAction((l) => /Create a new account/.test(l), 30000, (l) => /Email input field/.test(l))) return bail("register-mode");
        console.log("STEP2 register mode OK");
        // STEP 3: fill + submit (email-bound account).
        const u = "webprobe" + Date.now().toString().slice(-6);
        if (!await typeInto(/Username input field/, u)) return bail("username");
        if (!await typeInto(/Password input field/, "hunter2hunter2")) return bail("password");
        if (!await typeInto(/Email input field/, u + "@example.com")) return bail("email");
        await page.screenshot({ path: OUT + "/syn_a1_reg.png" });
        if (!await clickAction((l) => /Create account and enter/.test(l), 30000, (l) => l === "Create New")) return bail("create-account");
        console.log("STEP3 account created -> lobby OK");
        // STEP 4: lobby -> create new character.
        if (!await clickAction((l) => l === "Create New", 30000, (l, e) => /\/species_/.test(e.id))) return bail("create-new");
        // STEP 5: species (the scene swap can take ~35s under software GL).
        // Match by handle (species_<id>), never the label: the class strip's
        // "Play ..." labels would otherwise collide with a label predicate.
        const species = await waitAction((l, e) => /\/species_[a-z_]+\/Margin/.test(e.id), 90000);
        if (!species) return bail("no-species");
        console.log("STEP5 species list:", species.action);
        await page.screenshot({ path: OUT + "/syn_a1_charsel.png" });
        if (!await clickAction((l, e) => e.id === species.id, 30000, (l, e) => /\/class_[a-z_]+\/Margin/.test(e.id))) return bail("species-click");
        // STEP 6: class.
        const klass = await waitAction((l, e) => /\/class_[a-z_]+\/Margin/.test(e.id), 60000);
        if (!klass) return bail("no-class");
        console.log("STEP6 class list:", klass.action);
        if (!await clickAction((l, e) => e.id === klass.id, 30000, (l, e) => /CharacterSelect\/PlayButton$/.test(e.id) && e.disabled === false)) return bail("class-click");
        // STEP 7: Enter World (enabled by the class selection -- the state
        // change the R38 signature fix made announceable).
        if (!await clickAction((l, e) => /CharacterSelect\/PlayButton$/.test(e.id), 30000)) return bail("enter-world");
        console.log("STEP7 Enter World clicked");
        // STEP 8: the world scene loads + registers the player.
        const wEnd = Date.now() + Math.min(240000, left() - 90000);
        while (Date.now() < wEnd && !marks.has("registered")) await new Promise((r) => setTimeout(r, 500));
        console.log("STEP8 world-registered:", marks.has("registered"), "spawning:", marks.has("spawning"));
        // STEP 9: let the terrain derive + draw. Under software GL the first
        // world frames are still black while the clipmap bakes; poll until the
        // frame is no longer flat dark (or give up).
        let stats = null;
        const rEnd = Date.now() + Math.min(180000, left() - 40000);
        while (Date.now() < rEnd) {
                await page.waitForTimeout(12000);
                stats = await classify(OUT + "/syn_a1_world.png");
                if (stats.ground.dark < 0.85) break;
        }
        console.log("STEP9 world pixels:", JSON.stringify(stats));
        // STEP 10: nudge the camera (look right) and re-measure.
        await page.mouse.move(640, 360);
        await page.mouse.down();
        await page.mouse.move(800, 360, { steps: 12 });
        await page.mouse.up();
        await page.waitForTimeout(12000);
        const stats2 = await classify(OUT + "/syn_a1_world2.png");
        console.log("STEP10 after look:", JSON.stringify(stats2));
        // STEP 11: pause/resume through real keys.
        if (left() > 30000) {
                await page.keyboard.press("Escape");
                const pEnd = Date.now() + 10000;
                while (Date.now() < pEnd && !marks.has("paused")) await new Promise((r) => setTimeout(r, 400));
                await page.keyboard.press("Escape");
                const qEnd = Date.now() + 10000;
                while (Date.now() < qEnd && !marks.has("resumed")) await new Promise((r) => setTimeout(r, 400));
                console.log("STEP11 pause/resume:", marks.has("paused"), marks.has("resumed"));
        }
        // STEP 12: in-world entity actions. Spawn-dependent, so absence is
        // reported, not hard-failed -- the damage path is pinned by
        // game/tests/test_a11y_service.gd.
        const entity = await waitAction((l, e) => e.kind === "entity", 30000);
        if (entity) {
                console.log("STEP12 entity action:", entity.action);
                await page.mouse.click(entity.rect.x + entity.rect.w / 2, entity.rect.y + entity.rect.h / 2);
                await page.waitForTimeout(2500);
        } else {
                console.log("STEP12 entity actions: none announced in range (world-dependent)");
        }

        const reached = marks.has("registered");
        // Rendered == the ground band is NOT flat dark. We do not require
        // green specifically: a spawn point over water is a legitimate frame,
        // and the sky/ground split is the real tell.
        const rendered = (stats2.ground.green + stats2.ground.teal) > 0.10;
        console.log("MARKS:", JSON.stringify(Array.from(marks)));
        console.log("ERRORS:", JSON.stringify(errors.slice(0, 6)));
        console.log("RESULT:", reached && rendered && errors.length === 0 ? "PASS" : (reached ? "RENDER-FAIL" : "FLOW-FAIL"));
        await browser.close().catch(() => {});
        server.close();
        process.exit(reached && rendered && errors.length === 0 ? 0 : 1);
})();
