// Synmergia Companion Client - drive the game from a 2D helper, an agent, or
// a screen-reader-style control surface.
//
// One protocol, two transports, chosen automatically:
//   * in-page  -> window.SynmergiaAgent (the WebInputBridge hooks; same page
//                 as the Godot canvas). Zero network. This transport is built
//                 on gamestruct's EMBEDDED binding (SPEC N27): the host
//                 publishes JSON text on a side channel and the facade reads
//                 it back in the same turn, because a create_callback return
//                 value does not survive the wasm boundary.
//   * remote   -> the AgentDoor HTTP listener (game/core/services/agent_door.gd)
//                 on 127.0.0.1 (or wherever the door is fronted). The door
//                 speaks the gamestruct four-primitive wire (/observe, /act,
//                 /wait_for, /events); the generic MCP projection lives in
//                 gamestruct (bindings/mcp.mjs), not on the door. This is what
//                 a headless companion / an LLM agent / another machine uses.
//
// Both reach the SAME AgentDriver verbs (observe/act/wait_for/events), so a
// companion plays by the exact rules a keypress takes -- no bypass, no agent
// rail. That is the whole point: the 2D helper is a player like any other.
//
// Usage (in-page, e.g. a helper bundled with the game page):
//   const syn = SynmergiaCompanion.inPage();
//   const state = await syn.observe();
//   await syn.act(state.actions.find(a => a.action.includes('Talk')).id);
//
// Usage (remote, e.g. a helper on the website talking to a running shard):
//   const syn = SynmergiaCompanion.remote('http://127.0.0.1:3789');
//   const { frame, events } = await syn.events();
//   for (const e of events) console.log(e.event, e.data);
//
// The object returned by observe():
//   { ok, frame, scene, in_world, player, target, party, focus, summary,
//     actions[], events[] }   // focus + summary are SPEC N5
//
// The object returned by events():
//   { ok, frame, events[] }  // SPEC N4: the cursor rides top-level
// Each action: { id, kind, action, detail, focused, disabled }  (act by `id`, always)

(function (global) {
        'use strict';

        // -- In-page transport (the gamestruct EMBEDDED binding, SPEC N27) ---
        //
        // The host (WebInputBridge) publishes each hook's JSON on
        // window.__synAgentResult and the client reads it back in the same turn.
        // The facade is built HERE, never handed across as a host-side literal:
        // an object containing host callbacks does not survive the marshal.
        // createFacade turns every failure mode (a missing hook, a throw, an
        // empty publish, malformed JSON) into an honest { ok:false, reason }.
        class InPageTransport {
                constructor() {
                        this._facade = null;
                }
                get available() {
                        // The hooks register once the Godot runtime is up.
                        return !!global.SynmergiaAgent;
                }
                _build() {
                        if (this._facade) return this._facade;
                        // Both the host hooks and the bundle must be present; a
                        // facade built against a missing host would cache a
                        // permanently broken transport.
                        var hooks = global.SynmergiaAgent;
                        var embed = global.GamestructEmbedded;
                        if (!hooks) return null;
                        if (!embed || typeof embed.createFacade !== 'function') return null;
                        // Each callback takes the JSON string the facade sends and
                        // hands it to the hook; the hook publishes the result.
                        this._facade = embed.createFacade({
                                callbacks: {
                                        observe: () => { hooks.observe(); },
                                        act: (json) => { hooks.act(JSON.parse(json)); },
                                        events: (json) => { hooks.events(JSON.parse(json)); },
                                },
                                read: () => global.__synAgentResult,
                                // The side channel is stateful: a hook that dies
                                // without publishing would otherwise hand back the
                                // PREVIOUS result as a success that never happened.
                                // The host exposes __synAgentClear for exactly this;
                                // absent it, the facade cannot invent one.
                                clear: () => {
                                        if (typeof global.__synAgentClear === 'function') global.__synAgentClear();
                                        else global.__synAgentResult = undefined;
                                },
                        });
                        return this._facade;
                }
                async observe() {
                        var f = this._build();
                        if (!f) return { ok: false, reason: 'game not ready' };
                        return f.observe();
                }
                async act(id, args) {
                        var f = this._build();
                        if (!f) return { ok: false, reason: 'game not ready' };
                        // The wire body is {id, verb, value} and the host folds it
                        // (AgentDriver.fold_act_body), which reads a nested `args`
                        // object AND lifts a top-level verb/value. Send both shapes
                        // so a companion's act(id, {forward:1}) keeps its args and a
                        // set_value still arrives as a value write.
                        if (id && typeof id === 'object') return f.act(id);
                        var payload = { id: id };
                        if (args && typeof args === 'object') {
                                payload.args = args;
                                if (args.verb !== undefined) payload.verb = args.verb;
                                if (args.value !== undefined) payload.value = args.value;
                        }
                        return f.act(payload);
                }
                async events(since) {
                        var f = this._build();
                        // SPEC N4 shape even when the door is down: a bare []
                        // would read as "no events yet", and a caller doing
                        // `res.events` would throw on an array.
                        if (!f) return { ok: false, reason: 'game not ready', events: [] };
                        return f.events(since == null ? -1 : since);
                }
                // wait_for polls observe() here, exactly as the facade does for a
                // browser door: a boundary callback cannot park a host thread.
                async waitFor(predicate, timeoutMs) {
                        var f = this._build();
                        if (!f) return { ok: false, reason: 'game not ready' };
                        // The `event` key is frame-scoped: the door captures its
                        // cursor at wait start ("since": _frames), so the page must
                        // too. Read the baseline from the first observation; until
                        // then `matches` treats -1 as "any frame", which only
                        // affects the pre-baseline ticks.
                        var base = null;
                        return f.waitFor((snap) => {
                                if (base === null && snap && typeof snap.frame === 'number') base = snap.frame;
                                return matches(snap, predicate, base === null ? undefined : base);
                        }, timeoutMs || 8000);
                }
                // A viewport capture writes a PNG into the wasm virtual
                // filesystem, which the page cannot fetch back; the door serves
                // this verb, the page does not. Refuse by name, never silently.
                async see() { return { ok: false, reason: 'the in-page surface has no eyes (use the door)' }; }
                // Multi-agent lives on the door, not in-page; report honestly.
                async coord() { return { ok: false, reason: 'coordinator needs the door (remote)' }; }
        }

        // -- Remote transport (AgentDoor HTTP) -----------------------------
        class RemoteTransport {
                constructor(baseUrl) {
                        this.base = (baseUrl || 'http://127.0.0.1:3789').replace(/\/$/, '');
                }
                get available() { return true; }
                async _get(path) {
                        const r = await fetch(this.base + path);
                        return r.json();
                }
                async _post(path, body) {
                        const r = await fetch(this.base + path, {
                                method: 'POST',
                                headers: { 'Content-Type': 'application/json' },
                                body: JSON.stringify(body || {}),
                        });
                        return r.json();
                }
                async observe() { return this._get('/observe'); }
                async act(id, args) { return this._post('/act', { id, args: args || {} }); }
                async events(since) { return this._get('/events?since=' + (since == null ? -1 : since)); }
                async see(opts) { return this._post('/see', opts || {}); }
                async coord(op, extra) { return this._post('/coord', Object.assign({ op }, extra || {})); }
                async waitFor(predicate, timeoutMs) {
                        return this._post('/wait_for', { predicate, timeoutMs: timeoutMs || 8000 });
                }
        }

        // -- The companion facade ------------------------------------------
        class SynmergiaCompanion {
                constructor(transport) {
                        this._t = transport;
                }

                static inPage() { return new SynmergiaCompanion(new InPageTransport()); }
                static remote(url) { return new SynmergiaCompanion(new RemoteTransport(url)); }

                // Auto-pick: in-page if the hooks are live, else remote.
                static auto(url) {
                        const inPage = new InPageTransport();
                        if (inPage.available) return new SynmergiaCompanion(inPage);
                        return new SynmergiaCompanion(new RemoteTransport(url));
                }

                get ready() { return this._t.available; }

                observe() { return this._t.observe(); }
                act(id, args) { return this._t.act(id, args); }
                events(since) { return this._t.events(since); }
                see(opts) { return this._t.see(opts); }

                // -- Multi-agent (the coordinator; remote/door only) ----------------
                coord(op, extra) { return this._t.coord(op, extra); }
                agents() { return this.coord('list'); }
                register(handle, opts) { return this.coord('register', { handle, opts: opts || {} }); }
                unregister(handle) { return this.coord('unregister', { handle }); }
                pause(handle) { return this.coord('pause', { handle }); }
                resume(handle) { return this.coord('resume', { handle }); }
                delegate(handle, task) { return this.coord('delegate', { handle, task: task || {} }); }
                poll(handle) { return this.coord('poll', { handle }); }
                queue(handle) { return this.coord('queue', { handle }); }
                approve(handle, workId) { return this.coord('approve', { handle, work_id: workId }); }
                reject(handle, workId, reason) { return this.coord('reject', { handle, work_id: workId, reason: reason || '' }); }
                step() { return this.coord('step'); }
                run() { return this.coord('run'); }

                // wait_for: the door parks server-side; in-page we poll observe().
                async waitFor(predicate, timeoutMs) {
                        timeoutMs = timeoutMs || 8000;
                        if (this._t.waitFor) return this._t.waitFor(predicate, timeoutMs);
                        const start = Date.now();
                        while (Date.now() - start < timeoutMs) {
                                const s = await this.observe();
                                if (matches(s, predicate)) return { ok: true };
                                await new Promise((r) => setTimeout(r, 100));
                        }
                        return { ok: false, reason: 'timeout' };
                }

                // Convenience: act on the first action whose label contains `text`.
                async actByLabel(text, args) {
                        const s = await this.observe();
                        const needle = String(text).toLowerCase();
                        const hit = (s.actions || []).find(
                                (a) => String(a.action).toLowerCase().includes(needle) && !a.disabled
                        );
                        if (!hit) return { ok: false, reason: 'no action matching "' + text + '"' };
                        return this.act(hit.id, args);
                }

                // Walk toward a world entity id (chunked move), then stop.
                async approach(entityId, opts) {
                        opts = opts || {};
                        const stepMs = opts.stepMs || 250;
                        const maxSteps = opts.maxSteps || 40;
                        for (let i = 0; i < maxSteps; i++) {
                                const s = await this.observe();
                                if (!s.in_world) return { ok: false, reason: 'not in world' };
                                const me = s.player;
                                const eid = entityId.replace(/^world:/, '');
                                const ent = (s.actions || []).find((a) => a.id === 'world:' + eid);
                                if (!ent) return { ok: true, reason: 'in range' };
                                await this.act('move', { forward: 1 });
                                await new Promise((r) => setTimeout(r, stepMs));
                        }
                        await this.act('stop');
                        return { ok: false, reason: 'did not reach target' };
                }
        }

        // Predicate evaluation shared with the GDScript vocabulary
        // (AgentDriver._predicate_met). The two MUST agree: a predicate that
        // resolves in-page but times out at the door (or the reverse) makes the
        // transport, not the game, decide what an agent sees.
        //
        // An UNKNOWN key is a refusal, exactly as GDScript's `_: return false`
        // is. Without this, a typo'd key ({in_wrold:true}) matched vacuously and
        // waitFor returned ok:true at once while the player was not in the
        // world -- a false success on the one verb an agent uses to WAIT.
        function matches(state, predicate, sinceFrame) {
                // A REFUSAL is not a state: {ok:false, reason} from a dead door
                // has no fields, so {in_world:false} used to match it and
                // waitFor resolved ok:true while the game was not running.
                if (!state || state.ok === false) return false;
                for (const key of Object.keys(predicate)) {
                        const want = predicate[key];
                        switch (key) {
                        case 'in_world':
                                if (!!state.in_world !== !!want) return false;
                                break;
                        case 'player_dead': {
                                const dead = !!(state.player && state.player.is_dead);
                                if (dead !== !!want) return false;
                                break;
                        }
                        case 'hp_below': {
                                // The snapshot field is `health` (see
                                // AgentDriver._player_block), not `hp`.
                                const hp = state.player && typeof state.player.health === 'number'
                                        ? state.player.health : null;
                                if (hp === null || hp >= Number(want)) return false;
                                break;
                        }
                        case 'action_present': {
                                const ok = (state.actions || []).some((a) =>
                                        String(a.action).toLowerCase().includes(String(want).toLowerCase()));
                                if (!ok) return false;
                                break;
                        }
                        case 'action_absent': {
                                const ok = (state.actions || []).some((a) =>
                                        String(a.action).toLowerCase().includes(String(want).toLowerCase()));
                                if (ok) return false;
                                break;
                        }
                        case 'target': {
                                const name = state.target ? String(state.target.name).toLowerCase() : '';
                                if (!name.includes(String(want).toLowerCase())) return false;
                                break;
                        }
                        case 'event': {
                                // Frame-scoped, exactly as AgentDriver._event_since
                                // reads it: an event from BEFORE the wait started is
                                // not a match. Without this a wait for 'combat_hit'
                                // resolved in 1ms on a hit hundreds of frames old --
                                // stale read as fresh.
                                const base = typeof sinceFrame === 'number' ? sinceFrame : -1;
                                const seen = (state.events || []).some((e) =>
                                        Number(e.frame) > base &&
                                        String(e.event || '').toLowerCase() === String(want).toLowerCase());
                                if (!seen) return false;
                                break;
                        }
                        default:
                                // Unknown key: never vacuously true.
                                return false;
                        }
                }
                return true;
        }

        global.SynmergiaCompanion = SynmergiaCompanion;
})(typeof window !== 'undefined' ? window : this);
