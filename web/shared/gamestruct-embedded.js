// gamestruct embedded binding (SPEC N27) - GENERATED, DO NOT EDIT.
//
// Source: gamestruct@1.5.0 lib/bindings/embedded.mjs
// Regenerate: node scripts/build_embedded_bundle.mjs
//
// The client half of the boundary law: createFacade({ callbacks, read })
// wraps a host's JSON-string callbacks plus a side-channel reader into the
// four primitives returning parsed objects. The host half (the GDScript
// WebInputBridge hooks) is the other end of the same contract.

var GamestructEmbedded = (() => {
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: true });
  };
  var __copyProps = (to, from, except, desc) => {
    if (from && typeof from === "object" || typeof from === "function") {
      for (let key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    }
    return to;
  };
  var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

  // node_modules/gamestruct/lib/bindings/embedded.mjs
  var embedded_exports = {};
  __export(embedded_exports, {
    PRIMITIVES: () => PRIMITIVES,
    createDoor: () => createDoor,
    createFacade: () => createFacade
  });

  // node_modules/gamestruct/lib/roles.mjs
  var ROLES = Object.freeze({
    // structure
    GROUP: "group",
    REGION: "region",
    LIST: "list",
    LISTITEM: "listitem",
    MENU: "menu",
    MENUITEM: "menuitem",
    DIALOG: "dialog",
    TABLIST: "tablist",
    TAB: "tab",
    TABPANEL: "tabpanel",
    SEPARATOR: "separator",
    HEADING: "heading",
    TEXT: "text",
    IMAGE: "image",
    // interactive
    BUTTON: "button",
    LINK: "link",
    TEXTBOX: "textbox",
    CHECKBOX: "checkbox",
    RADIO: "radio",
    SLIDER: "slider",
    SWITCH: "switch",
    COMBOBOX: "combobox",
    PROGRESSBAR: "progressbar",
    // live
    STATUS: "status",
    LOG: "log",
    ALERT: "alert"
  });
  var ACTIONS = Object.freeze({
    ACTIVATE: "activate",
    // press a button / follow a link / toggle
    FOCUS: "focus",
    // move focus here (the AT "move to" verb)
    SET_VALUE: "set_value",
    // type / slide / select
    SELECT: "select",
    // choose this item in a list/menu/tablist
    EXPAND: "expand",
    // open a disclosure
    COLLAPSE: "collapse",
    SCROLL: "scroll"
    // reveal this node in its container
  });
  var INTERACTIVE_ROLES = Object.freeze(/* @__PURE__ */ new Set([
    ROLES.BUTTON,
    ROLES.LINK,
    ROLES.TEXTBOX,
    ROLES.CHECKBOX,
    ROLES.RADIO,
    ROLES.SLIDER,
    ROLES.SWITCH,
    ROLES.COMBOBOX,
    ROLES.MENUITEM,
    ROLES.TAB,
    ROLES.LISTITEM
  ]));
  var LIVE_ROLES = Object.freeze(/* @__PURE__ */ new Set([
    ROLES.STATUS,
    ROLES.LOG,
    ROLES.ALERT
  ]));
  var DEFAULT_ACTION = Object.freeze({
    [ROLES.BUTTON]: ACTIONS.ACTIVATE,
    [ROLES.LINK]: ACTIONS.ACTIVATE,
    [ROLES.CHECKBOX]: ACTIONS.ACTIVATE,
    [ROLES.RADIO]: ACTIONS.ACTIVATE,
    [ROLES.SWITCH]: ACTIONS.ACTIVATE,
    [ROLES.MENUITEM]: ACTIONS.ACTIVATE,
    [ROLES.TAB]: ACTIONS.SELECT,
    [ROLES.LISTITEM]: ACTIONS.SELECT,
    [ROLES.TEXTBOX]: ACTIONS.SET_VALUE,
    [ROLES.COMBOBOX]: ACTIONS.SET_VALUE,
    [ROLES.SLIDER]: ACTIONS.SET_VALUE
  });
  var LIVE_POLITENESS = Object.freeze({
    [ROLES.STATUS]: "polite",
    [ROLES.LOG]: "polite",
    [ROLES.ALERT]: "assertive"
  });

  // node_modules/gamestruct/lib/bridge.mjs
  function matchesSnapshot(snap, expected) {
    for (const key of Object.keys(expected)) {
      if (key === "summary") {
        const want = expected.summary;
        for (const k of Object.keys(want)) {
          if (snap.summary[k] !== want[k]) return false;
        }
      } else if (snap[key] !== expected[key]) {
        return false;
      }
    }
    return true;
  }

  // node_modules/gamestruct/lib/bindings/embedded.mjs
  var PRIMITIVES = Object.freeze(["observe", "act", "wait_for", "events"]);
  function _message(e) {
    return e && e.message ? e.message : String(e);
  }
  function _decode(raw) {
    if (raw === void 0 || raw === null) return null;
    if (typeof raw !== "string") return raw;
    const text = raw.trim();
    if (!text) return null;
    try {
      return JSON.parse(text);
    } catch {
      return null;
    }
  }
  function createDoor(bridge, opts = {}) {
    if (!bridge || typeof bridge.observe !== "function") {
      throw new Error("createDoor: a Bridge is required");
    }
    const stringify = typeof opts.stringify === "function" ? opts.stringify : JSON.stringify;
    const door = {
      observe() {
        return stringify(bridge.observe());
      },
      act(payload) {
        const p = _decode(payload);
        if (p == null) return stringify({ ok: false, reason: "act requires a payload" });
        if (typeof p === "string") return stringify(bridge.act(p));
        if (typeof p === "object" && p.id) {
          return stringify(bridge.act(String(p.id), p.verb, p.value));
        }
        return stringify({ ok: false, reason: "act requires an id" });
      },
      events(since) {
        const n = Number(_decode(since));
        return stringify(bridge.events(Number.isFinite(n) ? n : -1));
      }
    };
    if (bridge.canSee) {
      door.see = (payload) => {
        const p = _decode(payload) || {};
        return bridge.see(p).then((res) => stringify(res));
      };
    }
    return door;
  }
  function createFacade(opts = {}) {
    const callbacks = opts.callbacks || {};
    const read = typeof opts.read === "function" ? opts.read : null;
    const parse = typeof opts.parse === "function" ? opts.parse : JSON.parse;
    function readResult(what) {
      if (!read) return { ok: false, reason: "the embedded door has no side channel" };
      let raw;
      try {
        raw = read();
      } catch (e) {
        return { ok: false, reason: "the side channel threw: " + _message(e) };
      }
      if (raw === void 0 || raw === null || raw === "") {
        return { ok: false, reason: "the host published no " + what + " result" };
      }
      try {
        return parse(String(raw));
      } catch (e) {
        return { ok: false, reason: "the host published malformed JSON: " + _message(e) };
      }
    }
    function invoke(name, arg) {
      const fn = callbacks[name];
      if (typeof fn !== "function") {
        return { ok: false, reason: 'the embedded door has no "' + name + '" callback' };
      }
      try {
        fn(arg === void 0 ? "" : arg);
      } catch (e) {
        return { ok: false, reason: 'the "' + name + '" callback threw: ' + _message(e) };
      }
      return null;
    }
    return {
      /** True when the host bound a `see` callback (the surface has eyes). */
      get canSee() {
        return typeof callbacks.see === "function";
      },
      observe() {
        const err = invoke("observe");
        return err || readResult("observe");
      },
      act(id, verb, value) {
        const payload = id && typeof id === "object" ? id : { id, verb, value };
        const err = invoke("act", JSON.stringify(payload));
        return err || readResult("act");
      },
      events(since) {
        const cursor = since === void 0 || since === null ? -1 : since;
        const err = invoke("events", JSON.stringify(cursor));
        return err || readResult("events");
      },
      // wait_for is JS-side polling of observe(): a boundary callback cannot
      // park a host thread, so the honest implementation is the same one a
      // browser door uses — poll, and time out honestly (N3).
      async waitFor(predicate, timeoutMs = 5e3, o = {}) {
        const step = o.step || 25;
        const deadline = Date.now() + Math.max(0, Number(timeoutMs) || 0);
        const test = typeof predicate === "function" ? predicate : (snap) => matchesSnapshot(snap, predicate || {});
        for (; ; ) {
          const snap = this.observe();
          if (test(snap)) return { ok: true, frame: snap.frame, snapshot: snap };
          if (Date.now() >= deadline) {
            return { ok: false, reason: "timeout", snapshot: snap };
          }
          await new Promise((r) => setTimeout(r, step));
        }
      },
      async see(o = {}) {
        const fn = callbacks.see;
        if (typeof fn !== "function") return { ok: false, reason: "this surface has no eyes" };
        let out;
        try {
          out = fn(JSON.stringify(o || {}));
        } catch (e) {
          return { ok: false, reason: 'the "see" callback threw: ' + _message(e) };
        }
        if (out && typeof out.then === "function") {
          try {
            out = await out;
          } catch (e) {
            return { ok: false, reason: "the capture failed: " + _message(e) };
          }
        }
        if (typeof out === "string" && out.trim()) {
          try {
            return parse(out);
          } catch (e) {
            return { ok: false, reason: "the host published malformed JSON: " + _message(e) };
          }
        }
        return readResult("see");
      }
    };
  }
  return __toCommonJS(embedded_exports);
})();
