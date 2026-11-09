// Synmergia Companion Client - drive the game from a 2D helper, an agent, or
// a screen-reader-style control surface.
//
// One protocol, two transports, chosen automatically:
//   * in-page  -> window.SynmergiaAgent (the WebInputBridge hooks; same page
//                 as the Godot canvas). Zero network.
//   * remote   -> the AgentDoor HTTP listener (game/core/services/agent_door.gd)
//                 on 127.0.0.1 (or wherever the door is fronted). This is what
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
//   for (const e of await syn.events()) console.log(e.event, e.data);
//
// The object returned by observe():
//   { ok, frame, scene, in_world, player, target, party, actions[], events[] }
// Each action: { id, kind, action, detail, disabled }  (act by `id`, always)

(function (global) {
        'use strict';

        // -- In-page transport (window.SynmergiaAgent) ---------------------
        class InPageTransport {
                constructor() {
                        this._bridge = global.SynmergiaAgent || null;
                }
                get available() {
                        // The hooks register once the Godot runtime is up.
                        if (!global.SynmergiaAgent) this._bridge = global.SynmergiaAgent;
                        return !!this._bridge;
                }
                async observe() {
                        if (!this.available) return { ok: false, reason: 'game not ready' };
                        return JSON.parse(this._bridge.observe());
                }
                async act(id, args) {
                        if (!this.available) return { ok: false, reason: 'game not ready' };
                        return JSON.parse(this._bridge.act(args ? { id, args } : id));
                }
                async events(since) {
                        if (!this.available) return [];
                        return JSON.parse(this._bridge.events(since == null ? -1 : since));
                }
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
                async coord(op, extra) { return this._post('/coord', Object.assign({ op }, extra || {})); }
                async tools() { return this._get('/tools'); }
                async waitFor(predicate, timeoutMs) {
                        return this._post('/wait_for', { predicate, timeout_ms: timeoutMs || 8000 });
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

        // Predicate evaluation shared with the GDScript vocabulary.
        function matches(state, predicate) {
                for (const key of Object.keys(predicate)) {
                        const want = predicate[key];
                        if (key === 'in_world' && !!state.in_world !== !!want) return false;
                        if (key === 'player_dead') {
                                const dead = !!(state.player && state.player.is_dead);
                                if (dead !== !!want) return false;
                        }
                        if (key === 'action_present') {
                                const ok = (state.actions || []).some((a) =>
                                        String(a.action).toLowerCase().includes(String(want).toLowerCase()));
                                if (!ok) return false;
                        }
                        if (key === 'action_absent') {
                                const ok = (state.actions || []).some((a) =>
                                        String(a.action).toLowerCase().includes(String(want).toLowerCase()));
                                if (ok) return false;
                        }
                        if (key === 'target') {
                                const name = state.target ? String(state.target.name).toLowerCase() : '';
                                if (!name.includes(String(want).toLowerCase())) return false;
                        }
                }
                return true;
        }

        global.SynmergiaCompanion = SynmergiaCompanion;
})(typeof window !== 'undefined' ? window : this);
