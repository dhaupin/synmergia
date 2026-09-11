// Synmergia Web Client - Touch UI Overlay
// Renders virtual joystick and action buttons on touch devices.

class SynmergiaTouchUI {
	constructor() {
		this.canvas = null;
		this.active = false;
		this._joystickTouchId = null;
		this._joystickCenter = { x: 0, y: 0 };
		this._joystickOffset = { x: 0, y: 0 };
		this._joystickMaxRadius = 60;
		this._buttons = [];
		this._container = null;
	}

	init(canvas) {
		this.canvas = canvas;
		if (!this._isTouchDevice()) return;

		this.active = true;
		this._createOverlay();
		this._createJoystick();
		this._createButtons();
		this._bindJoystickEvents();
		this._bindButtonEvents();
	}

	_isTouchDevice() {
		return ('ontouchstart' in window) || (navigator.maxTouchPoints > 0);
	}

	_createOverlay() {
		this._container = document.createElement('div');
		this._container.id = 'touch-overlay';
		document.body.appendChild(this._container);
	}

	_createJoystick() {
		var js = document.createElement('div');
		js.id = 'touch-joystick';
		js.innerHTML = '<div class="js-base"></div><div class="js-thumb"></div>';
		this._container.appendChild(js);

		var rect = this.canvas.getBoundingClientRect();
		var cx = rect.width * 0.25;
		var cy = rect.height * 0.75;

		this._joystickCenter = { x: cx, y: cy };

		var base = js.querySelector('.js-base');
		base.style.left = (cx - 50) + 'px';
		base.style.top = (cy - 50) + 'px';
	}

	_createButtons() {
		var self = this;
		var rect = this.canvas.getBoundingClientRect();

		var buttons = [
			{ id: 'btn-jump', text: 'JUMP', x: rect.width - 100, y: rect.height - 100, w: 80, h: 80, key: 32 },
			{ id: 'btn-interact', text: 'ACT', x: rect.width - 100, y: rect.height - 210, w: 80, h: 80, key: 69 },
			{ id: 'btn-attack', text: 'ATK', x: rect.width - 100, y: rect.height - 320, w: 80, h: 80, key: 0, mouse: true }
		];

		for (var i = 0; i < buttons.length; i++) {
			var cfg = buttons[i];
			var btn = document.createElement('div');
			btn.id = cfg.id;
			btn.className = 'touch-btn';
			btn.style.left = cfg.x + 'px';
			btn.style.top = cfg.y + 'px';
			btn.style.width = cfg.w + 'px';
			btn.style.height = cfg.h + 'px';
			btn.textContent = cfg.text;
			this._container.appendChild(btn);
			this._buttons.push({ el: btn, cfg: cfg });
		}
	}

	_bindJoystickEvents() {
		var self = this;
		var js = document.getElementById('touch-joystick');

		js.addEventListener('touchstart', function(e) {
			e.preventDefault();
			var t = e.changedTouches[0];
			self._joystickTouchId = t.identifier;
			self._updateJoystick(t.clientX, t.clientY);
		}, { passive: false });

		js.addEventListener('touchmove', function(e) {
			e.preventDefault();
			for (var i = 0; i < e.changedTouches.length; i++) {
				var t = e.changedTouches[i];
				if (t.identifier === self._joystickTouchId) {
					self._updateJoystick(t.clientX, t.clientY);
				}
			}
		}, { passive: false });

		js.addEventListener('touchend', function(e) {
			e.preventDefault();
			for (var i = 0; i < e.changedTouches.length; i++) {
				var t = e.changedTouches[i];
				if (t.identifier === self._joystickTouchId) {
					self._joystickTouchId = null;
					self._resetJoystick();
				}
			}
		}, { passive: false });
	}

	_updateJoystick(clientX, clientY) {
		var rect = this.canvas.getBoundingClientRect();
		var x = clientX - rect.left;
		var y = clientY - rect.top;

		var dx = x - this._joystickCenter.x;
		var dy = y - this._joystickCenter.y;
		var dist = Math.sqrt(dx * dx + dy * dy);

		if (dist > this._joystickMaxRadius) {
			dx = dx / dist * this._joystickMaxRadius;
			dy = dy / dist * this._joystickMaxRadius;
		}

		this._joystickOffset = { x: dx, y: dy };

		var thumb = document.querySelector('.js-thumb');
		if (thumb) {
			thumb.style.left = (this._joystickCenter.x + dx - 15) + 'px';
			thumb.style.top = (this._joystickCenter.y + dy - 15) + 'px';
		}

		if (window.SynmergiaInput) {
			window.SynmergiaInput._enqueue(6, Math.floor(x), Math.floor(y), this._joystickTouchId);
		}
	}

	_resetJoystick() {
		var thumb = document.querySelector('.js-thumb');
		if (thumb) {
			thumb.style.left = (this._joystickCenter.x - 15) + 'px';
			thumb.style.top = (this._joystickCenter.y - 15) + 'px';
		}
		this._joystickOffset = { x: 0, y: 0 };
		if (window.SynmergiaInput) {
			window.SynmergiaInput._enqueue(7, 0, 0, this._joystickTouchId);
		}
	}

	_bindButtonEvents() {
		var self = this;
		for (var i = 0; i < this._buttons.length; i++) {
			var btn = this._buttons[i];
			(function(cfg) {
				btn.el.addEventListener('touchstart', function(e) {
					e.preventDefault();
					if (cfg.key && !cfg.mouse) {
						window.SynmergiaInput._enqueue(8, cfg.key, 1, 0);
					} else if (cfg.mouse) {
						var rect = self.canvas.getBoundingClientRect();
						window.SynmergiaInput._enqueue(1, Math.floor(cfg.x + cfg.w / 2), Math.floor(cfg.y + cfg.h / 2), 0);
					}
				}, { passive: false });

				btn.el.addEventListener('touchend', function(e) {
					e.preventDefault();
					if (cfg.key && !cfg.mouse) {
						window.SynmergiaInput._enqueue(9, cfg.key, 0, 0);
					} else if (cfg.mouse) {
						var rect = self.canvas.getBoundingClientRect();
						window.SynmergiaInput._enqueue(2, Math.floor(cfg.x + cfg.w / 2), Math.floor(cfg.y + cfg.h / 2), 0);
					}
				}, { passive: false });
			})(btn.cfg);
		}
	}
}

window.SynmergiaTouchUI = new SynmergiaTouchUI();