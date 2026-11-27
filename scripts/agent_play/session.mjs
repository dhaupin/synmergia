#!/usr/bin/env node
// The persistent play session: one chromium, one wasm game, served as JSON on
// localhost so any number of short `play` commands share it.
//
// Why a session at all: booting the wasm build costs ~40 s (software GL), so a
// one-shot CLI would spend the whole budget on startup and lose the world state
// between commands. An agent plays in many small steps; the session keeps the
// game alive between them.
//
// The wire is the SAME primitives the native door speaks
// (observe/act/wait_for/events) because the in-page bridge forwards to the same
// AgentDriver. `read` is the a11y view of that one tree, so a screen reader and
// an agent are reading the same nodes.
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..', '..');
const STATE_PATH = path.join(os.tmpdir(), 'syn_agent_play.json');

const argv = process.argv.slice(2);
const flag = (name, dflt) => {
	const i = argv.indexOf('--' + name);
	return i >= 0 && argv[i + 1] ? argv[i + 1] : dflt;
};
const has = (name) => argv.includes('--' + name);

const TARGET = flag('target', 'local');
const LIVE_URL = flag('url', 'https://synmergia.creadev.org');
const PORT = parseInt(flag('port', '8137'), 10);
const HEADED = has('headed');
const IDLE_MS = parseInt(flag('idle-minutes', '60'), 10) * 60000;

// playwright-core lives in scripts/web_probe (the probe rig installs it);
// resolve from there so a play session needs no second install.
function loadPlaywright() {
	const require = createRequire(import.meta.url);
	for (const base of [HERE, path.join(ROOT, 'scripts', 'web_probe')]) {
		try {
			return require(require.resolve('playwright-core', { paths: [base] }));
		} catch { /* next candidate */ }
	}
	console.error('[session] playwright-core not found. Run: npm install --prefix scripts/web_probe');
	process.exit(2);
}

const MIME = {
	'.html': 'text/html; charset=utf-8',
	'.js': 'text/javascript; charset=utf-8',
	'.mjs': 'text/javascript; charset=utf-8',
	'.wasm': 'application/wasm',
	'.pck': 'application/octet-stream',
	'.png': 'image/png',
	'.json': 'application/json',
	'.css': 'text/css; charset=utf-8',
	'.svg': 'image/svg+xml',
};

// The threaded Godot build only boots when the page is cross-origin isolated,
// so the local server sends the same headers scripts/serve_web.py sends.
function staticServer(dir) {
	return http.createServer((req, res) => {
		const url = decodeURIComponent((req.url || '/').split('?')[0]);
		const rel = url === '/' ? '/index.html' : url;
		const file = path.join(dir, path.normalize(rel).replace(/^(\.\.[/\\])+/, ''));
		fs.readFile(file, (err, buf) => {
			if (err) { res.writeHead(404); res.end('not found'); return; }
			res.writeHead(200, {
				'Content-Type': MIME[path.extname(file)] || 'application/octet-stream',
				'Cross-Origin-Opener-Policy': 'same-origin',
				'Cross-Origin-Embedder-Policy': 'require-corp',
				'Cross-Origin-Resource-Policy': 'cross-origin',
				'Cache-Control': 'no-cache',
			});
			res.end(buf);
		});
	});
}

let browser = null;
let page = null;
let staticSrv = null;
let bootedAt = Date.now();
let lastTouch = Date.now();

// ---------------------------------------------------------------- reading ---
// One vocabulary for both audiences: the role a screen reader announces and
// the role an agent reasons about are the same word.
function roleOf(entry) {
	const kind = String(entry.kind || '').toLowerCase();
	if (kind.includes('button')) return 'button';
	if (kind.includes('edit') || kind.includes('field') || kind.includes('text')) return 'edit';
	if (kind === 'entity') return 'world';
	return kind || 'control';
}

function reading(snap) {
	const lines = [];
	for (const a of snap.actions || []) {
		const bits = [];
		if (a.focused) bits.push('focused');
		if (a.disabled) bits.push('unavailable');
		if (a.value !== undefined && a.value !== null && a.value !== '') {
			bits.push('value "' + (a.value === '<set>' ? '(set)' : a.value) + '"');
		}
		const detail = a.detail ? ' - ' + a.detail : '';
		lines.push(`${roleOf(a)} "${a.action}"${detail}${bits.length ? ' [' + bits.join(', ') + ']' : ''}`);
	}
	return lines;
}

// ------------------------------------------------------------ label match ---
// Agents and screen-reader users speak LABELS ("Enter World"), not engine
// handles. Resolve to the stable handle, and refuse to guess when ambiguous.
function resolve(snap, needle) {
	const actions = (snap.actions || []).filter((a) => !a.disabled);
	const exact = actions.filter((a) => String(a.action) === needle);
	if (exact.length === 1) return { hit: exact[0] };
	if (exact.length > 1) return { ambiguous: exact };
	const lower = String(needle).toLowerCase();
	const ci = actions.filter((a) => String(a.action).toLowerCase() === lower);
	if (ci.length === 1) return { hit: ci[0] };
	if (ci.length > 1) return { ambiguous: ci };
	const sub = actions.filter((a) => String(a.action).toLowerCase().includes(lower));
	if (sub.length === 1) return { hit: sub[0] };
	if (sub.length > 1) return { ambiguous: sub };
	return { missing: true };
}

// ------------------------------------------------------------------ verbs ---
// The wasm boundary hands back a JSON STRING (the host publishes each hook's
// result on window.__synAgentResult; a create_callback return does not survive
// the JS/GDScript boundary). Parse it here so every consumer sees an object.
const asObj = (v) => {
	if (v && typeof v === 'object') return v;
	try { return JSON.parse(v); } catch (e) { return { ok: false, reason: 'unparseable reply: ' + String(v).slice(0, 160) }; }
};

async function observe() {
	return asObj(await page.evaluate(() => window.SynmergiaAgent.observe()));
}

async function act(id, args) {
	return asObj(await page.evaluate(([i, a]) => window.SynmergiaAgent.act(i, a), [id, args || {}]));
}

async function events(since) {
	return asObj(await page.evaluate((s) => window.SynmergiaAgent.events(s), since));
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Declarative waits: a predicate on the observation, never a wall-clock
// displacement (fps changes the distance, not the state).
async function waitFor(spec, timeoutMs) {
	const end = Date.now() + timeoutMs;
	const [key, want] = String(spec).split(':');
	let last = null;
	while (Date.now() < end) {
		const s = await observe();
		last = s;
		if (key === 'in_world' && s.in_world === true) return { ok: true, snap: s };
		if (key === 'out_of_world' && s.in_world === false) return { ok: true, snap: s };
		if (key === 'scene' && String(s.scene).toLowerCase() === String(want || '').toLowerCase()) return { ok: true, snap: s };
		if (key === 'label' && !resolve(s, want || '').missing) return { ok: true, snap: s };
		if (key === 'gone' && resolve(s, want || '').missing) return { ok: true, snap: s };
		if (key === 'moving' && s.player && s.player.moving === true) return { ok: true, snap: s };
		if (key === 'still' && s.player && s.player.moving === false) return { ok: true, snap: s };
		await sleep(250);
	}
	return { ok: false, reason: `timed out after ${timeoutMs} ms waiting for ${spec}`, last };
}

async function command(cmd) {
	const t = cmd.cmd;
	if (t === 'status') {
		const s = page ? await observe().catch(() => null) : null;
		return {
			ok: true, ready: !!page, target: TARGET, url: page ? page.url() : null,
			pid: process.pid, port: PORT, uptime_s: Math.round((Date.now() - bootedAt) / 1000),
			scene: s ? s.scene : null, in_world: s ? s.in_world : false,
		};
	}
	if (!page) return { ok: false, reason: 'session is still booting' };
	if (t === 'observe') return observe();
	if (t === 'events') return { ok: true, events: await events(cmd.since) };
	if (t === 'read') {
		const s = await observe();
		return { ok: true, scene: s.scene, in_world: s.in_world, focus: s.focus, lines: reading(s), snap: s };
	}
	if (t === 'wait') return waitFor(cmd.spec, cmd.timeout_ms || 60000);
	if (t === 'act') {
		const s = await observe();
		let id = cmd.id;
		let label = cmd.label;
		if (!id) {
			const r = resolve(s, cmd.label);
			if (r.ambiguous) return { ok: false, reason: `ambiguous label "${cmd.label}"`, candidates: r.ambiguous.map((a) => a.action) };
			if (r.missing) return { ok: false, reason: `no action labelled "${cmd.label}"` };
			id = r.hit.id;
			label = r.hit.action;
		}
		const args = {};
		if (cmd.verb) args.verb = cmd.verb;
		if (cmd.value !== undefined) args.value = cmd.value;
		const res = await act(id, args);
		return { ...res, label, id };
	}
	if (t === 'move') {
		const dir = cmd.dir || 'forward';
		const res = await act('move', { [dir]: 1 });
		return { ...res, dir };
	}
	if (t === 'halt') return act('stop');
	if (t === 'shot') {
		const out = cmd.out || path.join(os.tmpdir(), 'syn_play.png');
		await page.screenshot({ path: out });
		return { ok: true, path: out };
	}
	if (t === 'quit') {
		setTimeout(() => shutdown(0), 50);
		return { ok: true, reason: 'stopping' };
	}
	return { ok: false, reason: 'unknown command ' + t };
}

// ------------------------------------------------------------------- boot ---
async function boot() {
	const { chromium } = loadPlaywright();
	let base = null;
	if (TARGET === 'local') {
		staticSrv = staticServer(path.join(ROOT, 'web'));
		await new Promise((r) => staticSrv.listen(0, '127.0.0.1', r));
		base = 'http://127.0.0.1:' + staticSrv.address().port;
	} else {
		base = LIVE_URL.replace(/\/$/, '');
	}
	const launchOpts = {
		headless: !HEADED,
		args: ['--no-sandbox', '--disable-dev-shm-usage', '--disable-gpu-sandbox', '--enable-unsafe-swiftshader'],
	};
	// Browser discovery, in order: explicit PROBE_CHROME, a system chrome, then
	// playwright's own cache. `play` must work with no env setup.
	const chromeCandidates = [process.env.PROBE_CHROME, '/usr/bin/chromium', '/usr/bin/chromium-browser', '/usr/bin/google-chrome', '/usr/bin/google-chrome-stable'].filter(Boolean);
	const chromePath = chromeCandidates.find((p) => { try { return fs.existsSync(p); } catch { return false; } });
	if (chromePath) launchOpts.executablePath = chromePath;
	browser = await chromium.launch(launchOpts);
	page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
	page.on('console', () => { /* drained: a per-frame print here is a disk bomb */ });
	// The agent surface is fail-closed in web/config.js; the operator opts in.
	// A play session IS the operator, so it appends the flag the same way the
	// probe does (per-session, never to the deployed config).
	await page.route('**/config.js', async (route) => {
		const resp = await route.fetch();
		const body = await resp.text();
		await route.fulfill({ response: resp, body: body + '\nwindow.SynmergiaConfig.agent = true;\n' });
	});
	await page.goto(base + '/index.html', { waitUntil: 'load', timeout: 60000 });
	const end = Date.now() + 180000;
	while (Date.now() < end) {
		if (await page.evaluate(() => !!window.SynmergiaAgent).catch(() => false)) return;
		await sleep(500);
	}
	throw new Error('window.SynmergiaAgent never appeared');
}

function shutdown(code) {
	try { if (browser) browser.close(); } catch { /* already gone */ }
	try { if (staticSrv) staticSrv.close(); } catch { /* already gone */ }
	try { fs.unlinkSync(STATE_PATH); } catch { /* not ours */ }
	process.exit(code);
}

// ------------------------------------------------------------------ serve ---
const api = http.createServer((req, res) => {
	if (req.method !== 'POST') { res.writeHead(405); res.end(); return; }
	let body = '';
	req.on('data', (c) => { body += c; });
	req.on('end', async () => {
		lastTouch = Date.now();
		let cmd = {};
		try { cmd = JSON.parse(body || '{}'); } catch { /* bad json */ }
		let out;
		try { out = await command(cmd); }
		catch (e) { out = { ok: false, reason: String(e && e.message ? e.message : e) }; }
		res.writeHead(200, { 'Content-Type': 'application/json' });
		res.end(JSON.stringify(out));
	});
});

// A stale socket from a killed session must not block a new one: walk forward
// a few ports and publish whichever one we actually got.
function listen(port, tries) {
	api.once('error', (e) => {
		if (e && e.code === 'EADDRINUSE' && tries > 0) { api.close(); listen(port + 1, tries - 1); return; }
		console.error('[session] cannot listen:', e && e.message ? e.message : e);
		shutdown(1);
	});
	api.listen(port, '127.0.0.1', () => {
		const got = api.address().port;
		fs.writeFileSync(STATE_PATH, JSON.stringify({ port: got, pid: process.pid, target: TARGET, started: Date.now() }));
		console.log(`[session] ready on 127.0.0.1:${got} (target=${TARGET}, pid=${process.pid})`);
	});
}

(async () => {
	try {
		await boot();
	} catch (e) {
		console.error('[session] boot failed:', e && e.message ? e.message : e);
		shutdown(1);
		return;
	}
	listen(PORT, 9);
	setInterval(() => {
		if (Date.now() - lastTouch > IDLE_MS) {
			console.log('[session] idle timeout, shutting down');
			shutdown(0);
		}
	}, 60000);
})();

process.on('SIGTERM', () => shutdown(0));
process.on('SIGINT', () => shutdown(0));
