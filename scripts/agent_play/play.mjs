#!/usr/bin/env node
// play - drive the running Synmergia wasm build the way a player does.
//
// Every command is a thin client of the persistent session
// (scripts/agent_play/session.mjs). The session is started on demand, so an
// agent can just call `play` and go.
//
//   play start [--target local|live] [--headed]   boot the game
//   play look                                    where am I (compact)
//   play read                                    the screen-reader view
//   play act "Enter World"                       activate by LABEL
//   play act "Username" --verb set_value --value hunter2
//   play move forward | play halt                hold / release movement
//   play wait in_world | scene:LOBBY | label:"Create New" | moving
//   play events [--since N]                      live-region announcements
//   play shot [--out file.png]                   screenshot (for eyes)
//   play status | play quit
//
// Labels are what a screen reader announces, so the same command line works
// for a human with NVDA and for an agent with no eyes.
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const SESSION = path.join(HERE, 'session.mjs');
const STATE_PATH = path.join(os.tmpdir(), 'syn_agent_play.json');

const argv = process.argv.slice(2);
const cmd = argv[0];
const rest = argv.slice(1);
const flag = (name, dflt) => {
	const i = argv.indexOf('--' + name);
	return i >= 0 && argv[i + 1] ? argv[i + 1] : dflt;
};
const has = (name) => argv.includes('--' + name);
const JSON_OUT = has('json');
const positional = rest.filter((a, i) => !a.startsWith('--') && !(i > 0 && rest[i - 1].startsWith('--')));

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function readState() {
	try { return JSON.parse(fs.readFileSync(STATE_PATH, 'utf8')); } catch { return null; }
}

function post(port, payload) {
	return new Promise((resolve, reject) => {
		const body = JSON.stringify(payload);
		const req = http.request({ host: '127.0.0.1', port, method: 'POST', path: '/', headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) } }, (res) => {
			let out = '';
			res.on('data', (c) => { out += c; });
			res.on('end', () => {
				try { resolve(JSON.parse(out)); } catch (e) { reject(new Error('bad response: ' + out.slice(0, 200))); }
			});
		});
		req.on('error', reject);
		req.end(body);
	});
}

async function livePort() {
	const st = readState();
	if (!st) return null;
	try { const s = await post(st.port, { cmd: 'status' }); return s && s.ready ? st.port : null; }
	catch { return null; }
}

async function startSession() {
	const args = [SESSION];
	for (const name of ['target', 'url', 'port', 'idle-minutes']) {
		if (flag(name, null) !== null) args.push('--' + name, flag(name));
	}
	if (has('headed')) args.push('--headed');
	// Keep the child's own log: an auto-started session that dies must leave a
	// reason behind, not just "did not come up".
	const logPath = path.join(os.tmpdir(), 'syn_agent_play_session.log');
	const fd = fs.openSync(logPath, 'w');
	const child = spawn(process.execPath, args, { detached: true, stdio: ['ignore', fd, fd] });
	child.unref();
	const end = Date.now() + 200000;
	process.stderr.write('[play] booting the game (software GL, ~40-60 s)... log: ' + logPath + '\n');
	while (Date.now() < end) {
		const port = await livePort();
		if (port) return port;
		await sleep(1000);
	}
	let tail = '';
	try { tail = fs.readFileSync(logPath, 'utf8').split('\n').slice(-12).join('\n'); } catch { /* no log */ }
	throw new Error('the session did not come up. Last lines of ' + logPath + ':\n' + tail);
}

async function ensure() {
	let port = await livePort();
	if (!port) port = await startSession();
	return port;
}

function print(obj) {
	if (JSON_OUT) { console.log(JSON.stringify(obj, null, 2)); return; }
	if (obj.ok === false) {
		console.log('no: ' + (obj.reason || 'refused'));
		if (obj.candidates) for (const c of obj.candidates) console.log('  candidate: ' + c);
		if (obj.last) printLook(obj.last);
		process.exitCode = 1;
		return;
	}
	console.log(JSON.stringify(obj, null, 2));
}

function printLook(s) {
	if (!s) return;
	console.log(`scene: ${s.scene}${s.in_world ? ' (in world)' : ''}`);
	if (s.player) {
		const p = s.player;
		const who = [p.character_name || p.name || p.id || 'body'];
		if (p.class || p.char_class) who.push('class ' + (p.class || p.char_class));
		if (p.species) who.push(p.species);
		if (p.level) who.push('level ' + p.level);
		who.push(`hp ${p.health}/${p.max_health}`);
		if (p.mana !== undefined) who.push('mana ' + p.mana);
		if (p.is_dead) who.push('DEAD');
		if (p.on_ground === false) who.push('airborne');
		if (p.moving) who.push(`moving ${p.speed} m/s`);
		console.log('body:  ' + who.join(', '));
		if (p.position) console.log(`at:    ${p.position.x.toFixed(2)}, ${p.position.y.toFixed(2)}, ${p.position.z.toFixed(2)}`);
	}
	if (s.target) console.log(`target: ${s.target.name} <${s.target.id}>`);
	const actions = s.actions || [];
	console.log(`actions (${actions.length}), focus: ${s.focus || 'none'}`);
	for (const a of actions.slice(0, 24)) {
		const bits = [];
		if (a.focused) bits.push('focused');
		if (a.disabled) bits.push('unavailable');
		if (a.value) bits.push('value "' + (a.value === '<set>' ? '(set)' : a.value) + '"');
		console.log(`  ${a.action}${a.detail ? ' - ' + a.detail : ''}${bits.length ? ' [' + bits.join(', ') + ']' : ''}`);
	}
	if (actions.length > 24) console.log(`  ... ${actions.length - 24} more (use \`read\` or --json)`);
}

(async () => {
	if (!cmd || cmd === 'help' || cmd === '--help') {
		const src = fs.readFileSync(fileURLToPath(import.meta.url), 'utf8').split('\n').slice(1);
		const help = [];
		for (const line of src) {
			if (!line.startsWith('//')) break;
			help.push(line.replace(/^\/\/ ?/, ''));
		}
		console.log(help.join('\n'));
		return;
	}
	if (cmd === 'quit' || cmd === 'stop') {
		const port = await livePort();
		if (!port) { console.log('no session running'); return; }
		console.log(JSON.stringify(await post(port, { cmd: 'quit' })));
		return;
	}
	if (cmd === 'start') {
		const port = await ensure();
		console.log(JSON.stringify(await post(port, { cmd: 'status' }), null, 2));
		return;
	}

	const port = await ensure();
	let payload = null;
	if (cmd === 'look' || cmd === 'observe') payload = { cmd: 'observe' };
	else if (cmd === 'read') payload = { cmd: 'read' };
	else if (cmd === 'status') payload = { cmd: 'status' };
	else if (cmd === 'events') payload = { cmd: 'events', since: flag('since', -1) };
	else if (cmd === 'wait') payload = { cmd: 'wait', spec: positional[0], timeout_ms: parseInt(flag('timeout', '60'), 10) * 1000 };
	else if (cmd === 'act') payload = { cmd: 'act', label: positional[0], id: flag('id', null), verb: flag('verb', null), value: flag('value', null) };
	else if (cmd === 'move') payload = { cmd: 'move', dir: positional[0] || 'forward' };
	else if (cmd === 'halt') payload = { cmd: 'halt' };
	else if (cmd === 'shot') payload = { cmd: 'shot', out: flag('out', null) };
	else { console.error('unknown command: ' + cmd + ' (try `play help`)'); process.exit(2); }

	const res = await post(port, payload);

	if (cmd === 'look' || cmd === 'observe') {
		if (JSON_OUT || res.ok === false) print(res); else printLook(res);
		return;
	}
	if (cmd === 'read') {
		if (JSON_OUT || res.ok === false) { print(res); return; }
		console.log(`${res.scene}${res.in_world ? ' (in world)' : ''}`);
		for (const line of res.lines || []) console.log('  ' + line);
		return;
	}
	if (cmd === 'wait' && res.ok && res.snap) { if (JSON_OUT) print(res); else console.log('yes: ' + payload.spec); return; }
	if (cmd === 'act' && res.ok && !JSON_OUT) { console.log('yes: ' + (res.label || res.handle || payload.label)); return; }
	if (cmd === 'move' && res.ok && !JSON_OUT) { console.log('yes: holding ' + res.dir); return; }
	if (cmd === 'halt' && res.ok && !JSON_OUT) { console.log('yes: stopped'); return; }
	print(res);
})().catch((e) => { console.error('play: ' + (e && e.message ? e.message : e)); process.exit(1); });
