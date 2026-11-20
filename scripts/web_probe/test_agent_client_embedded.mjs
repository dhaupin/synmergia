// agent-client-embedded.test.mjs - the in-page transport rides gamestruct's
// embedded binding (SPEC N27) end to end.
//
// The wasm boundary law says a host callback's RETURN VALUE never crosses back
// and a structured ARGUMENT arrives as an opaque handle, so the host publishes
// JSON on a side channel and the client reads it in the same turn. This test
// reproduces that shape faithfully: the "host" is a function that WRITES to
// window.__synAgentResult and returns undefined (exactly what a
// JavaScriptBridge.create_callback does), and the real bundled
// createFacade is what reads it back.
//
// Run: node --test scripts/web_probe/test_agent_client_embedded.mjs
//      (npm run test:web-agent)
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');

/**
 * A fresh browser-ish global with the committed bundle + client loaded as
 * classic scripts. Both files declare their global with a top-level `var`/IIFE,
 * which in a browser lands on `window`; running them in a vm context whose
 * global object IS `window` reproduces that exactly (wrapping them in a
 * function would not).
 */
function loadPage({ withBundle = true } = {}) {
    const win = { console, setTimeout, clearTimeout, JSON };
    win.window = win;
    vm.createContext(win);
    if (withBundle) {
        vm.runInContext(readFileSync(path.join(ROOT, 'web/shared/gamestruct-embedded.js'), 'utf8'), win);
    }
    vm.runInContext(readFileSync(path.join(ROOT, 'web/shared/agent-client.js'), 'utf8'), win);
    return win;
}

/**
 * A fake WebInputBridge: it records the JSON it was handed, publishes a reply
 * on the side channel, and returns NOTHING -- the wasm law. `behaviour` maps a
 * hook name to the JSON string it publishes.
 */
function installHost(win, behaviour) {
    const calls = [];
    const publish = (json) => { win.__synAgentResult = json; };
    win.SynmergiaAgent = {
        observe: () => { calls.push(['observe']); publish(behaviour.observe()); },
        act: (payload) => { calls.push(['act', payload]); publish(behaviour.act(payload)); },
        events: (since) => { calls.push(['events', since]); publish(behaviour.events(since)); },
    };
    return calls;
}

test('observe decodes the published JSON through the facade', async () => {
    const win = loadPage();
    installHost(win, {
        observe: () => JSON.stringify({ ok: true, frame: 7, in_world: true }),
    });
    const syn = win.SynmergiaCompanion.inPage();
    const snap = await syn.observe();
    assert.equal(snap.ok, true);
    assert.equal(snap.frame, 7);
    assert.equal(snap.in_world, true);
});

test('a host that publishes nothing is an honest refusal, not a throw', async () => {
    const win = loadPage();
    // A dead hook: typeof function, invocation silently no-ops (the collected
    // create_callback case). The facade must refuse rather than throw.
    win.SynmergiaAgent = { observe: () => {}, act: () => {}, events: () => {} };
    const syn = win.SynmergiaCompanion.inPage();
    const snap = await syn.observe();
    assert.equal(snap.ok, false);
    assert.match(snap.reason, /published no observe result/);
});

test('a hook that throws is an honest refusal naming the callback', async () => {
    const win = loadPage();
    win.SynmergiaAgent = {
        observe: () => { throw new Error('boom'); },
        act: () => {}, events: () => {},
    };
    const syn = win.SynmergiaCompanion.inPage();
    const snap = await syn.observe();
    assert.equal(snap.ok, false);
    assert.match(snap.reason, /"observe" callback threw: boom/);
});

test('malformed JSON from the host is an honest refusal', async () => {
    const win = loadPage();
    win.SynmergiaAgent = {
        observe: () => { win.__synAgentResult = '{not json'; },
        act: () => {}, events: () => {},
    };
    const syn = win.SynmergiaCompanion.inPage();
    const snap = await syn.observe();
    assert.equal(snap.ok, false);
    assert.match(snap.reason, /malformed JSON/);
});

test('act carries id + args so a verb payload is not dropped', async () => {
    const win = loadPage();
    let seen = null;
    installHost(win, {
        observe: () => JSON.stringify({ ok: true }),
        act: (payload) => { seen = payload; return JSON.stringify({ ok: true, handle: payload.id }); },
    });
    const syn = win.SynmergiaCompanion.inPage();
    const res = await syn.act('move', { forward: 1 });
    assert.equal(res.ok, true);
    assert.equal(seen.id, 'move');
    assert.deepEqual(seen.args, { forward: 1 });
});

test('act lifts verb + value to the top level (the set_value fold)', async () => {
    const win = loadPage();
    let seen = null;
    installHost(win, {
        observe: () => JSON.stringify({ ok: true }),
        act: (payload) => { seen = payload; return JSON.stringify({ ok: true }); },
    });
    const syn = win.SynmergiaCompanion.inPage();
    await syn.act('ui:Login/User', { verb: 'set_value', value: 'ada' });
    // The host's fold_act_body reads a top-level verb/value; both must be there
    // AND the nested args must survive so the fold can merge them.
    assert.equal(seen.id, 'ui:Login/User');
    assert.equal(seen.verb, 'set_value');
    assert.equal(seen.value, 'ada');
    assert.equal(seen.args.verb, 'set_value');
    assert.equal(seen.args.value, 'ada');
});

test('events passes the cursor through and answers the N4 object shape', async () => {
    const win = loadPage();
    let seen = null;
    installHost(win, {
        observe: () => JSON.stringify({ ok: true }),
        // SPEC N4: { ok, frame, events[] } -- the cursor rides top-level, which
        // is what DoorClient.events() reads. A bare array left that cursor
        // unadvanced forever.
        events: (since) => {
            seen = since;
            return JSON.stringify({ ok: true, frame: 7, events: [{ event: 'x' }] });
        },
    });
    const syn = win.SynmergiaCompanion.inPage();
    const res = await syn.events(42);
    assert.equal(seen, 42);
    assert.equal(res.frame, 7, 'the frame cursor is readable top-level (N4)');
    assert.equal(res.events.length, 1);
    // A missing cursor is the wire's -1 sentinel, not undefined.
    await syn.events();
    assert.equal(seen, -1);
});

test('waitFor polls observe and honours the Synmergia predicate vocabulary', async () => {
    const win = loadPage();
    let n = 0;
    installHost(win, {
        // Only the third poll is in-world with a Talk action.
        observe: () => {
            n += 1;
            return JSON.stringify(n >= 3
                ? { ok: true, in_world: true, actions: [{ id: 'world:npc', action: 'Talk to Elder' }] }
                : { ok: true, in_world: false, actions: [] });
        },
    });
    const syn = win.SynmergiaCompanion.inPage();
    const out = await syn.waitFor({ action_present: 'talk' }, 2000);
    assert.equal(out.ok, true);
});

test('an unknown predicate key never matches vacuously', async () => {
    // The door's matcher has `_: return false`. Without the same default the
    // page matched a typo'd key and returned ok:true at once -- a false
    // success on the one verb an agent uses to WAIT.
    const win = loadPage();
    installHost(win, { observe: () => JSON.stringify({ ok: true, in_world: false, actions: [] }) });
    const syn = win.SynmergiaCompanion.inPage();
    const typo = await syn.waitFor({ in_wrold: true }, 250);
    assert.equal(typo.ok, false, 'a typo must not resolve');
    assert.equal(typo.reason, 'timeout');
    // A real key with a real mismatch still refuses.
    const real = await syn.waitFor({ in_world: true }, 250);
    assert.equal(real.ok, false);
});

test('the in-page predicate vocabulary covers hp_below and event', async () => {
    const win = loadPage();
    installHost(win, {
        observe: () => JSON.stringify({
            ok: true, in_world: true,
            player: { health: 40, is_dead: false },
            events: [{ event: 'door_opened' }],
            actions: [],
        }),
    });
    const syn = win.SynmergiaCompanion.inPage();
    assert.equal((await syn.waitFor({ hp_below: 100 }, 500)).ok, true, 'hp_below reads player.health');
    assert.equal((await syn.waitFor({ hp_below: 40 }, 250)).ok, false, 'hp_below is strictly below');
    assert.equal((await syn.waitFor({ event: 'door_opened' }, 500)).ok, true);
    assert.equal((await syn.waitFor({ event: 'nope' }, 250)).ok, false);
});

test('waitFor times out honestly when the predicate never holds', async () => {
    const win = loadPage();
    installHost(win, { observe: () => JSON.stringify({ ok: true, in_world: false }) });
    const syn = win.SynmergiaCompanion.inPage();
    const out = await syn.waitFor({ in_world: true }, 120);
    assert.equal(out.ok, false);
    assert.equal(out.reason, 'timeout');
});

test('see refuses by name in-page (no eyes on the wasm surface)', async () => {
    const win = loadPage();
    installHost(win, { observe: () => JSON.stringify({ ok: true }) });
    const syn = win.SynmergiaCompanion.inPage();
    const out = await syn.see({ label: 'x' });
    assert.equal(out.ok, false);
    assert.match(out.reason, /no eyes/);
});

test('a hook that dies without publishing never returns the previous result', async () => {
    // The side channel is stateful: a dead hook publishes nothing, so without
    // invalidation the client would hand back the PREVIOUS result and report
    // success for an action that never ran. Proven live on the wasm build.
    const win = loadPage();
    let actAlive = true;
    win.SynmergiaAgent = {
        observe: () => { win.__synAgentResult = JSON.stringify({ ok: true, frame: 42 }); },
        act: () => { if (actAlive) win.__synAgentResult = JSON.stringify({ ok: true, acted: 'yes' }); },
        events: () => {},
    };
    const syn = win.SynmergiaCompanion.inPage();
    const first = await syn.observe();
    assert.equal(first.ok, true);
    assert.equal(first.frame, 42);

    actAlive = false;
    const acted = await syn.act('ui:Start');
    assert.equal(acted.ok, false, 'a dead act must not report the observe snapshot as success');
    assert.equal(acted.frame, undefined, 'the stale observe frame must not leak through');
});

test('in-page is not available before the hooks install', async () => {
    const win = loadPage();
    const syn = win.SynmergiaCompanion.inPage();
    assert.equal(syn.ready, false);
    const snap = await syn.observe();
    assert.equal(snap.ok, false);
    assert.equal(snap.reason, 'game not ready');
});

test('a missing bundle degrades to "game not ready", never a crash', async () => {
    const win = loadPage({ withBundle: false });
    // Hooks present but the gamestruct bundle absent: no facade can be built.
    win.SynmergiaAgent = { observe: () => '{}', act: () => '{}', events: () => '[]' };
    const syn = win.SynmergiaCompanion.inPage();
    const snap = await syn.observe();
    assert.equal(snap.ok, false);
    assert.equal(snap.reason, 'game not ready');
});
