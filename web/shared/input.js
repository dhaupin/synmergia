// Synmergia Web Client - Input Handling
//
// Captures DOM input events and enqueues them into a buffer drained by
// the Godot WebInputBridge autoload via window.SynmergiaInput.drain().
//
// NOTE: a plain Godot web export delivers mouse/keyboard/touch natively.
// This capture layer is for embedded/wrapper contexts (per labs/prd-web.md
// the portal's GodotCanvas.tsx wrapper and the 2D companion client) and for
// devices/emulations where native delivery is unavailable.
//
// Event contract (mirrored by game/core/autoload/web_input_bridge.gd):
//   type 1 mouseDown  / 2 mouseUp  : x,y canvas coords, data = button
//             (0 left, 1 right, 2 middle)
//   type 3 mouseMove               : x,y canvas coords
//   type 4 wheel                   : data = 3 (up) / 4 (down); stateless,
//             no release event is emitted
//   type 5 touchStart / 6 touchMove / 7 touchEnd
//                                  : x,y canvas coords, data = touch index
//   type 8 keyDown  / 9 keyUp      : x = JS keyCode, y = modifier bitmask
//             (1 shift, 2 ctrl, 4 alt), data = unicode char code (0 if none)
//   type 10 resize                 : x,y = new window size
//   type 11 gamepadButton          : x = device, y = button, data = pressed
//   type 12 gamepadAxis            : x = device, y = axis, data = int16 value

class SynmergiaInput {
	constructor() {
		this._queue = [];          // buffered event dicts, drained by the engine
		this._maxQueue = 2048;     // drop new events beyond this (never corrupt)
		this.canvas = null;
		this._bound = false;
		this._heldKeys = new Set();
		this._heldButtons = new Set();
		this._activeTouches = new Set();
		this._lastGamepadState = new Map(); // index -> {buttons: [], axes: []}
		this._gamepadPollId = null;
	}

	init(canvas) {
		if (!canvas) {
			throw new Error('SynmergiaInput.init(): canvas is required');
		}
		this.canvas = canvas;
		this._bindEvents();
		this._startGamepadPolling();
	}

	_bindEvents() {
		if (this._bound) {
			return;
		}
		this._bound = true;
		const c = this.canvas;

		c.addEventListener('mousedown', (e) => this._handleMouseButton(e, 1));
		c.addEventListener('mouseup', (e) => this._handleMouseButton(e, 2));
		c.addEventListener('mousemove', (e) => this._handleMouseMove(e));
		c.addEventListener('wheel', (e) => this._handleWheel(e), { passive: false });

		c.addEventListener('touchstart', (e) => this._handleTouchStart(e), { passive: false });
		c.addEventListener('touchmove', (e) => this._handleTouchMove(e), { passive: false });
		c.addEventListener('touchend', (e) => this._handleTouchEnd(e), { passive: false });
		c.addEventListener('touchcancel', (e) => this._handleTouchEnd(e), { passive: false });

		window.addEventListener('keydown', (e) => this._handleKeyDown(e));
		window.addEventListener('keyup', (e) => this._handleKeyUp(e));
		window.addEventListener('blur', () => this._releaseAll());

		window.addEventListener('resize', () => this._handleResize());
		window.addEventListener('orientationchange', () => this._handleResize());
	}

	_startGamepadPolling() {
		const poll = () => {
			this._pollGamepads();
			this._gamepadPollId = requestAnimationFrame(poll);
		};
		this._gamepadPollId = requestAnimationFrame(poll);
	}

	_pollGamepads() {
		if (!navigator.getGamepads) {
			return;
		}
		const gamepads = navigator.getGamepads();
		for (let i = 0; i < gamepads.length; i++) {
			const gp = gamepads[i];
			if (!gp) continue;

			const last = this._lastGamepadState.get(i) || { buttons: [], axes: [] };
			const buttons = gp.buttons.map((b) => (b.pressed ? 1 : 0));
			const axes = Array.from(gp.axes, (v) => (Math.abs(v) < 0.15 ? 0 : v));

			for (let btn = 0; btn < buttons.length; btn++) {
				if (buttons[btn] !== (last.buttons[btn] || 0)) {
					this._enqueue(11, i, btn, buttons[btn]);
				}
			}
			for (let axis = 0; axis < axes.length; axis++) {
				const scaled = Math.round(axes[axis] * 32767);
				const lastScaled = Math.round((last.axes[axis] || 0) * 32767);
				if (scaled !== lastScaled) {
					this._enqueue(12, i, axis, scaled);
				}
			}
			this._lastGamepadState.set(i, { buttons, axes });
		}
	}

	// Canvas-space pixel position (drawing-buffer coords), DPR-aware.
	_canvasPos(clientX, clientY) {
		const rect = this.canvas.getBoundingClientRect();
		const sx = this.canvas.width / Math.max(rect.width, 1);
		const sy = this.canvas.height / Math.max(rect.height, 1);
		return {
			x: Math.round((clientX - rect.left) * sx),
			y: Math.round((clientY - rect.top) * sy),
		};
	}

	_handleMouseButton(e, type) {
		const p = this._canvasPos(e.clientX, e.clientY);
		if (type === 1) {
			this._heldButtons.add(e.button);
		} else {
			this._heldButtons.delete(e.button);
		}
		this._enqueue(type, p.x, p.y, e.button);
		e.preventDefault();
	}

	_handleMouseMove(e) {
		const p = this._canvasPos(e.clientX, e.clientY);
		this._enqueue(3, p.x, p.y, 0);
	}

	_handleWheel(e) {
		e.preventDefault();
		const p = this._canvasPos(e.clientX, e.clientY);
		// Bridge maps 3 -> WHEEL_UP, 4 -> WHEEL_DOWN (see _map_mouse_button).
		this._enqueue(4, p.x, p.y, e.deltaY > 0 ? 4 : 3);
	}

	_handleTouchStart(e) {
		e.preventDefault();
		for (const touch of e.changedTouches) {
			this._activeTouches.add(touch.identifier);
			const p = this._canvasPos(touch.clientX, touch.clientY);
			this._enqueue(5, p.x, p.y, touch.identifier);
		}
	}

	_handleTouchMove(e) {
		e.preventDefault();
		for (const touch of e.changedTouches) {
			if (!this._activeTouches.has(touch.identifier)) continue;
			const p = this._canvasPos(touch.clientX, touch.clientY);
			this._enqueue(6, p.x, p.y, touch.identifier);
		}
	}

	_handleTouchEnd(e) {
		e.preventDefault();
		for (const touch of e.changedTouches) {
			if (!this._activeTouches.delete(touch.identifier)) continue;
			const p = this._canvasPos(touch.clientX, touch.clientY);
			// Touch end carries its last known position so the engine can
			// resolve taps/clicks at the right spot.
			this._enqueue(7, p.x, p.y, touch.identifier);
		}
	}

	// Legacy JS keyCode for a KeyboardEvent; 0 when unknown.
	_keyCodeOf(e) {
		const table = {
			Backspace: 8, Tab: 9, Enter: 13, ShiftLeft: 16, ShiftRight: 16,
			ControlLeft: 17, ControlRight: 17, AltLeft: 18, AltRight: 18,
			Pause: 19, CapsLock: 20, Escape: 27, Space: 32,
			PageUp: 33, PageDown: 34, End: 35, Home: 36,
			ArrowLeft: 37, ArrowUp: 38, ArrowRight: 39, ArrowDown: 40,
			Insert: 45, Delete: 46, MetaLeft: 91, MetaRight: 92, ContextMenu: 93,
			Numpad0: 96, Numpad1: 97, Numpad2: 98, Numpad3: 99, Numpad4: 100,
			Numpad5: 101, Numpad6: 102, Numpad7: 103, Numpad8: 104, Numpad9: 105,
			NumpadMultiply: 106, NumpadAdd: 107, NumpadSubtract: 109,
			NumpadDecimal: 110, NumpadDivide: 111,
			F1: 112, F2: 113, F3: 114, F4: 115, F5: 116, F6: 117,
			F7: 118, F8: 119, F9: 120, F10: 121, F11: 122, F12: 123,
			NumLock: 144, ScrollLock: 145,
		};
		if (e.code === 'NumpadEnter') {
			return 13;
		}
		if (Object.prototype.hasOwnProperty.call(table, e.code)) {
			return table[e.code];
		}
		if (e.key && e.key.length === 1) {
			const upper = e.key.toUpperCase().charCodeAt(0);
			if ((upper >= 65 && upper <= 90) || (upper >= 48 && upper <= 57)) {
				return upper;
			}
		}
		return 0;
	}

	_handleKeyDown(e) {
		if (e.ctrlKey || e.metaKey) return; // never steal browser combos
		const code = this._keyCodeOf(e);
		if (code === 0) return;
		if (this._heldKeys.has(code)) return; // ignore OS key repeat
		this._heldKeys.add(code);
		const mods = (e.shiftKey ? 1 : 0) | (e.ctrlKey ? 2 : 0) | (e.altKey ? 4 : 0);
		const uni = e.key && e.key.length === 1 ? e.key.charCodeAt(0) : 0;
		this._enqueue(8, code, mods, uni);
		// Stop the page from scrolling / tabbing away / navigating.
		if (code === 8 || code === 9 || code === 32 || (code >= 33 && code <= 40) || (code >= 112 && code <= 123)) {
			e.preventDefault();
		}
	}

	_handleKeyUp(e) {
		const code = this._keyCodeOf(e);
		if (code === 0) return;
		if (this._heldKeys.delete(code)) {
			const mods = (e.shiftKey ? 1 : 0) | (e.ctrlKey ? 2 : 0) | (e.altKey ? 4 : 0);
			this._enqueue(9, code, mods, 0);
		}
	}

	_handleResize() {
		this._enqueue(10, window.innerWidth, window.innerHeight, 0);
	}

	// Release all held keys/buttons/touches (tab blur).
	_releaseAll() {
		for (const code of this._heldKeys) {
			this._enqueue(9, code, 0, 0);
		}
		this._heldKeys.clear();
		for (const btn of this._heldButtons) {
			this._enqueue(2, 0, 0, btn);
		}
		this._heldButtons.clear();
		for (const id of this._activeTouches) {
			this._enqueue(7, 0, 0, id);
		}
		this._activeTouches.clear();
	}

	_enqueue(type, x, y, data) {
		if (this._queue.length >= this._maxQueue) {
			// Overflow: drop the new event rather than corrupting the ring.
			return;
		}
		this._queue.push({ type, x, y, data });
	}

	// Drained by WebInputBridge (game/core/autoload/web_input_bridge.gd).
	drain() {
		const out = this._queue;
		this._queue = [];
		return out;
	}

	reset() {
		this._queue = [];
		this._heldKeys.clear();
		this._heldButtons.clear();
		this._activeTouches.clear();
	}
}

// Export singleton
window.SynmergiaInput = new SynmergiaInput();
