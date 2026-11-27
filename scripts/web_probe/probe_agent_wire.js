// Synmergia agent-wire acceptance probe (outside-in).
//
// Drives the live WASM export through the gamestruct FOUR-PRIMITIVE WIRE,
// not the A11Y console stream: window.SynmergiaAgent.observe()/act()/events()
// (the in-page transport of web/shared/agent-client.js, same verbs the HTTP
// AgentDoor serves). Every hop acts by STABLE HANDLE (ui:<path>), never a
// rect. The oracles are the game's own log marks.
//
// Run from the repo root:  xvfb-run -a node scripts/web_probe/probe_agent_wire.js
// Env: PROBE_CHROME, PROBE_PORT (default 8138), PROBE_WEB, PROBE_OUT.
const http = require("http");
const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright-core");
const WEB = process.env.PROBE_WEB || path.join(process.cwd(), "web");
const PORT = Number(process.env.PROBE_PORT) || 8138;
const OUT = process.env.PROBE_OUT || "/tmp";
const MIME = { ".html": "text/html", ".css": "text/css", ".js": "text/javascript", ".wasm": "application/wasm", ".pck": "application/octet-stream", ".png": "image/png", ".svg": "image/svg+xml" };
const server = http.createServer((req, res) => {
        let p = decodeURIComponent(req.url.split("?")[0]); if (p === "/") p = "/index.html";
        const file = path.join(WEB, p);
        if (!file.startsWith(WEB) || !fs.existsSync(file) || !fs.statSync(file).isFile()) { res.writeHead(404); res.end(); return; }
        res.writeHead(200, { "Content-Type": MIME[path.extname(file)] || "application/octet-stream", "Cross-Origin-Opener-Policy": "same-origin", "Cross-Origin-Embedder-Policy": "require-corp", "Cache-Control": "no-cache" });
        fs.createReadStream(file).pipe(res);
});

const marks = new Set();
const errors = [];
const T0 = Date.now();
const left = () => 900000 - (Date.now() - T0);
function ingest(t) {
        if (/Linked new character/.test(t)) marks.add("char-linked");
        else if (/Game state changed:/.test(t)) marks.add(t.match(/Game state changed:.*/)[0].slice(0, 60));
        else if (/World scene loaded/.test(t)) marks.add("world-loaded");
        else if (/player_entered_world/.test(t)) marks.add("spawning");
        else if (/Entering gameplay/.test(t)) marks.add("entering");
        else if (/SCRIPT ERROR/.test(t)) errors.push(t.slice(0, 140));
}
let page = null, browser = null;

// The in-page wire: evaluate window.SynmergiaAgent.observe()/act() inside the
// page (the exact functions a companion on the same page calls).
const obs = () => page.evaluate(() => {
        if (!window.SynmergiaAgent) return { ok: false, reason: "no window.SynmergiaAgent" };
        try { return JSON.parse(window.SynmergiaAgent.observe()); }
        catch (e) { return { ok: false, reason: "observe threw: " + e.message }; }
});
const act = (id, args) => page.evaluate(({ id, args }) => {
        if (!window.SynmergiaAgent) return { ok: false, reason: "no window.SynmergiaAgent" };
        try { return JSON.parse(window.SynmergiaAgent.act(args ? { id, args } : id)); }
        catch (e) { return { ok: false, reason: "act threw: " + e.message }; }
}, { id, args });

const waitAgent = async (ms) => {
        const end = Date.now() + Math.min(ms, left());
        while (Date.now() < end) {
                const ready = await page.evaluate(() => !!window.SynmergiaAgent).catch(() => false);
                if (ready) return true;
                await new Promise((r) => setTimeout(r, 500));
        }
        return false;
};

// Find an action by handle predicate; re-reads the live snapshot each poll.
const findAct = async (pred, ms) => {
        const end = Date.now() + Math.min(ms, left());
        while (Date.now() < end) {
                const s = await obs();
                const hit = (s.actions || []).find((a) => pred(a.action, a));
                if (hit) return { hit, snap: s };
                await new Promise((r) => setTimeout(r, 350));
        }
        return null;
};

const bail = async (tag, extra) => {
        console.log("RESULT: FAIL(" + tag + ")");
        if (extra) console.log(extra);
        console.log("MARKS:", JSON.stringify(Array.from(marks)));
        console.log("ERRORS:", JSON.stringify(errors.slice(0, 6)));
        // CI uploads these on failure: a red probe whose console only lived on
        // the runner cannot be diagnosed from the summary line.
        fs.writeFileSync(OUT + "/syn_wire_console.txt", consoleLines.join("\n"));
        await page.screenshot({ path: OUT + "/syn_wire_fail.png" }).catch(() => {});
        await browser.close().catch(() => {});
        server.close();
        process.exit(1);
};

(async () => {
        await new Promise((r) => server.listen(PORT, "127.0.0.1", r));
        const launchOpts = { headless: !process.env.PROBE_HEADED, args: ["--no-sandbox", "--disable-dev-shm-usage", "--disable-gpu-sandbox", "--enable-unsafe-swiftshader"] };
        if (process.env.PROBE_CHROME) launchOpts.executablePath = process.env.PROBE_CHROME;
        browser = await chromium.launch(launchOpts);
        page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
        page.on("console", (m) => ingest(m.text()));
        page.on("pageerror", (e) => errors.push("pageerror: " + e.message.slice(0, 140)));
        // The web opt-in. The native SYN_AGENT=1 has no browser equivalent, so
        // the operator enables the agent surface in web/config.js by setting
        // `window.SynmergiaConfig.agent = true` (fail-closed default is off).
        // A browser also may set it per-session with ?agent=1. The probe plays
        // the operator: it appends the flag to the served config.js (the real
        // deploy config is where this line lives).
        await page.route("**/config.js", async (route) => {
                const resp = await route.fetch();
                const body = await resp.text();
                await route.fulfill({ response: resp, body: body + "\nwindow.SynmergiaConfig.agent = true;\n" });
        });
        await page.goto("http://127.0.0.1:" + PORT + "/index.html", { waitUntil: "load", timeout: 30000 });

        // STEP 1: the wire is present once the runtime boots.
        if (!await waitAgent(120000)) return bail("no-wire");
        console.log("STEP1 window.SynmergiaAgent present");
        const first = await obs();
        console.log("STEP1 observe:", JSON.stringify({ ok: first.ok, enabled: first.enabled, scene: first.scene, in_world: first.in_world, actions: (first.actions || []).length, reason: first.reason }));
        if (!first.ok) return bail("observe-refused", JSON.stringify(first));
        if (!first.enabled) return bail("driver-disabled", "driver reports enabled=false; the web opt-in did not take");

        // STEP 2: act on the menu's Start button by STABLE HANDLE (no rect).
        const start = await findAct((l) => /Start playing/.test(l), 60000);
        if (!start) return bail("no-start-handle");
        console.log("STEP2 start handle:", start.hit.id, "|", start.hit.action);
        const r2 = await act(start.hit.id);
        console.log("STEP2 act(start):", JSON.stringify(r2));
        if (!r2.ok) return bail("act-refused-start", JSON.stringify(r2));

        // STEP 3: wait for the login scene to announce its own handles.
        const reg = await findAct((l) => /Create a new account/.test(l), 30000);
        if (!reg) return bail("no-register-handle");
        console.log("STEP3 register handle:", reg.hit.id);
        const r3 = await act(reg.hit.id);
        console.log("STEP3 act(register):", JSON.stringify(r3));

        // STEP 4: the register form exposes its fields as stable handles.
        const email = await findAct((l) => /Email input field/.test(l), 30000);
        const user = await findAct((l) => /Username input field/.test(l), 5000);
        const passField = await findAct((l) => /Password input field/.test(l), 5000);
        if (!email || !user || !passField) return bail("no-register-fields", JSON.stringify({ email: !!email, user: !!user, pass: !!passField }));
        console.log("STEP4 register fields:", user.hit.id, "|", passField.hit.id, "|", email.hit.id);
        const u = "wire" + Date.now().toString().slice(-6);
        // set_value is the world verb for a text control (the door's set_value).
        console.log("STEP4 set user:", JSON.stringify(await act(user.hit.id, { verb: "set_value", value: u })));
        console.log("STEP4 set pass:", JSON.stringify(await act(passField.hit.id, { verb: "set_value", value: "hunter2hunter2" })));
        console.log("STEP4 set email:", JSON.stringify(await act(email.hit.id, { verb: "set_value", value: u + "@example.com" })));
        const afterFill = await obs();
        console.log("STEP4 values:", JSON.stringify((afterFill.actions || []).filter((a) => /Field/.test(a.id)).map((a) => ({ id: a.id, value: a.value }))));

        // STEP 5: submit; the lobby announces Create New.
        const submit = await findAct((l) => /Create account and enter/.test(l), 20000);
        if (!submit) return bail("no-submit-handle");
        console.log("STEP5 submit handle:", submit.hit.id, "|", submit.hit.action);
        console.log("STEP5 submit act:", JSON.stringify(await act(submit.hit.id)));
        await new Promise((r) => setTimeout(r, 3000));
        const afterSubmit = await obs();
        console.log("STEP5 after submit scene:", afterSubmit.scene, "| actions:", JSON.stringify((afterSubmit.actions || []).map((a) => a.action).slice(0, 12)));

        // STEP 6: lobby -> Create New -> species -> class -> Enter World,
        // each hop by stable handle through the agent wire.
        const createNew = await findAct((l) => l === "Create New", 30000);
        if (!createNew) return bail("no-create-new");
        console.log("STEP6 create-new handle:", createNew.hit.id);
        await act(createNew.hit.id);

        const species = await findAct((l, e) => /\/species_[a-z_]+\/Margin/.test(e.id), 90000);
        if (!species) return bail("no-species");
        console.log("STEP6 species handle:", species.hit.id, "|", species.hit.action);
        await act(species.hit.id);

        const klass = await findAct((l, e) => /\/class_[a-z_]+\/Margin/.test(e.id), 60000);
        if (!klass) return bail("no-class");
        console.log("STEP6 class handle:", klass.hit.id, "|", klass.hit.action);
        await act(klass.hit.id);

        const enter = await findAct((l, e) => /CharacterSelect\/PlayButton$/.test(e.id) && e.disabled === false, 30000);
        if (!enter) return bail("no-enter-world");
        console.log("STEP6 enter-world handle:", enter.hit.id);
        await act(enter.hit.id);

        // STEP 7: the world loads + registers the player; observe() flips in_world.
        const wEnd = Date.now() + Math.min(240000, left() - 60000);
        let world = null;
        while (Date.now() < wEnd) {
                const s = await obs();
                if (s.in_world) { world = s; break; }
                await new Promise((r) => setTimeout(r, 500));
        }
        console.log("STEP7 in_world via agent wire:", !!world, "| marks registered:", marks.has("registered"));
        if (!world) return bail("never-in-world", "observe().in_world stayed false");
        console.log("STEP7 player:", JSON.stringify(world.player));

        // STEP 8: locomotion is asserted as a STATE TRANSITION, never as a
        // distance over wall-clock time. A displacement threshold is
        // fps-dependent (software GL runs at 2-4 fps and the body can still be
        // settling), which is how this step spent a round reporting 0.001 m and
        // nearly filed a bogus "wasm movement is broken" bug.
        //
        // The driver's player block carries `moving`/`speed` (the TANGENTIAL
        // component on the body's own up axis, so falling never reads as
        // walking). The claim is causal: no input -> not moving; forward ->
        // moving; stop -> not moving. A no-op move verb cannot pass any hop.
        const loco = { legs: [] };
        const locoFail = async (tag, extra) => {
                console.log("STEP8 legs:", JSON.stringify(loco.legs));
                return bail(tag, extra);
        };
        if (!world.player || typeof world.player.moving !== "boolean") {
                return locoFail("no-locomotion-state", "player block has no moving/speed: the served pck predates the driver locomotion fields");
        }
        const pollState = async (pred, ms) => {
                const end = Date.now() + Math.min(ms, left());
                let last = null;
                while (Date.now() < end) {
                        const s = await obs();
                        last = s.player || null;
                        if (last && pred(last)) return last;
                        await new Promise((r) => setTimeout(r, 250));
                }
                return null;
        };

        // L1 (negative control): with no input the body must stay put. This is
        // the hop that proves the assertion can fail.
        const idle = await pollState((p) => p.moving === true, 4000);
        const idleSnap = await obs();
        loco.legs.push({ leg: "L1 control: no input stays still", pass: idle === null, speed: idleSnap.player ? idleSnap.player.speed : -1 });
        if (idle !== null) return locoFail("loco-idle-moved", "the body reports moving=true with no input, so L2 would prove nothing");

        // L2: forward is held -> the body reports motion.
        const mv = await act("move", { forward: 1 });
        if (!mv || !mv.ok) return locoFail("move-refused", JSON.stringify(mv));
        const startPos = (await obs()).player.position;
        const walking = await pollState((p) => p.moving === true, 60000);
        loco.legs.push({ leg: "L2 forward -> moving", pass: !!walking, speed: walking ? walking.speed : 0 });
        if (!walking) return locoFail("loco-never-moved", "move{forward:1} returned ok but the body never reported moving");

        // L3: stop -> motion ends (the verb is not a sticky state).
        const st = await act("stop");
        if (!st || !st.ok) return locoFail("stop-refused", JSON.stringify(st));
        const stopped = await pollState((p) => p.moving === false, 60000);
        loco.legs.push({ leg: "L3 stop -> not moving", pass: !!stopped });
        if (!stopped) return locoFail("loco-never-stopped", "stop returned ok but the body kept reporting moving");

        // L4 (coarse, non-threshold): the body's position is not frozen while
        // walking. Any change at all counts; the magnitude is logged only.
        const endPos = (await obs()).player.position;
        const travelled = startPos && endPos ? Math.hypot(endPos.x - startPos.x, endPos.y - startPos.y, endPos.z - startPos.z) : -1;
        loco.legs.push({ leg: "L4 position advanced", pass: travelled > 0, travelled_m: Number(travelled.toFixed(3)) });
        if (!(travelled > 0)) return locoFail("loco-position-frozen", "moving=true but the position never changed");
        console.log("STEP8 locomotion:", JSON.stringify(loco.legs));

        console.log("MARKS:", JSON.stringify(Array.from(marks)));
        console.log("ERRORS:", JSON.stringify(errors.slice(0, 6)));
        const pass = !!world && errors.length === 0 && loco.legs.every((l) => l.pass);
        console.log("RESULT:", pass ? "PASS (drove menu -> register -> lobby -> species -> class -> world by stable handle through window.SynmergiaAgent; locomotion proven by state transition)" : "PARTIAL");
        await browser.close().catch(() => {});
        server.close();
        process.exit(pass ? 0 : 1);
})();
