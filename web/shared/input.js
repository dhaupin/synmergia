// Synmergia Web Client - Input Handling
// Shared buffer approach: writes input events into a typed array
// that the Godot WASM module reads via Emscripten's --preload.

class SynmergiaInput {
	constructor() {
		this.buffer = new Int32Array(256); // Fixed-size input buffer
		this.writePos = 0;
		this.readPos = 0;
		this.canvas = null;
		this._boundHandlers = {};
	}

	init(canvas) {
		this.canvas = canvas;
		this._bindEvents();
	}

	_bindEvents() {
		const c = this.canvas;

		// Mouse events
		c.addEventListener('mousedown', (e) => this._handleMouseDown(e));
		c.addEventListener('mouseup', (e) => this._handleMouseUp(e));
		c.addEventListener('mousemove', (e) => this._handleMouseMove(e));
		c.addEventListener('wheel', (e) => this._handleWheel(e));

		// Touch events
		c.addEventListener('touchstart', (e) => this._handleTouchStart(e), { passive: false });
		c.addEventListener('touchmove', (e) => this._handleTouchMove(e), { passive: false });
		c.addEventListener('touchend', (e) => this._handleTouchEnd(e), { passive: false });

		// Keyboard events (window-level)
		window.addEventListener('keydown', (e) => this._handleKeyDown(e));
		window.addEventListener('keyup', (e) => this._handleKeyUp(e));

		// Resize
		window.addEventListener('resize', () => this._handleResize());
	}

	_handleMouseDown(e) {
		const rect = this.canvas.getBoundingClientRect();
		const x = Math.floor(e.clientX - rect.left);
		const y = Math.floor(e.clientY - rect.top);
		this._enqueue(1, x, y, e.button); // 1 = mouse down
	}

	_handleMouseUp(e) {
		const rect = this.canvas.getBoundingClientRect();
		const x = Math.floor(e.clientX - rect.left);
		const y = Math.floor(e.clientY - rect.top);
		this._enqueue(2, x, y, e.button); // 2 = mouse up
	}

	_handleMouseMove(e) {
		const rect = this.canvas.getBoundingClientRect();
		const x = Math.floor(e.clientX - rect.left);
		const y = Math.floor(e.clientY - rect.top);
		this._enqueue(3, x, y, 0); // 3 = mouse move
	}

	_handleWheel(e) {
		e.preventDefault();
		this._enqueue(4, 0, 0, e.deltaY > 0 ? 1 : -1); // 4 = wheel
	}

	_handleTouchStart(e) {
		e.preventDefault();
		for (const touch of e.changedTouches) {
			const rect = this.canvas.getBoundingClientRect();
			const x = Math.floor(touch.clientX - rect.left);
			const y = Math.floor(touch.clientY - rect.top);
			this._enqueue(5, x, y, touch.identifier); // 5 = touch start
		}
	}

	_handleTouchMove(e) {
		e.preventDefault();
		for (const touch of e.changedTouches) {
			const rect = this.canvas.getBoundingClientRect();
			const x = Math.floor(touch.clientX - rect.left);
			const y = Math.floor(touch.clientY - rect.top);
			this._enqueue(6, x, y, touch.identifier); // 6 = touch move
		}
	}

	_handleTouchEnd(e) {
		e.preventDefault();
		for (const touch of e.changedTouches) {
			this._enqueue(7, 0, 0, touch.identifier); // 7 = touch end
		}
	}

	_handleKeyDown(e) {
		this._enqueue(8, e.keyCode, 1, 0); // 8 = key down
	}

	_handleKeyUp(e) {
		this._enqueue(9, e.keyCode, 0, 0); // 9 = key up
	}

	_handleResize() {
		this._enqueue(10, window.innerWidth, window.innerHeight, 0); // 10 = resize
	}

	_enqueue(type, x, y, data) {
		const idx = this.writePos % 256;
		this.buffer[idx * 4 + 0] = type;
		this.buffer[idx * 4 + 1] = x;
		this.buffer[idx * 4 + 2] = y;
		this.buffer[idx * 4 + 3] = data;
		this.writePos++;
	}

	drain() {
		const events = [];
		while (this.readPos < this.writePos) {
			const idx = this.readPos % 256;
			events.push({
				type: this.buffer[idx * 4 + 0],
				x: this.buffer[idx * 4 + 1],
				y: this.buffer[idx * 4 + 2],
				data: this.buffer[idx * 4 + 3]
			});
			this.readPos++;
		}
		return events;
	}

	reset() {
		this.writePos = 0;
		this.readPos = 0;
	}
}

// Export singleton
window.SynmergiaInput = new SynmergiaInput();