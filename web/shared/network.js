// Synmergia Web Client - Network Layer
// WebSocket client for server communication.
// Uses binary protocol for efficiency.

class SynmergiaNetwork {
	constructor() {
		this.ws = null;
		this.url = '';
		this.reconnectAttempts = 0;
		this.maxReconnectAttempts = 5;
		this.reconnectDelay = 1000;
		this.handlers = {};
		this._messageQueue = [];
		this._connected = false;
	}

	init(url) {
		this.url = url;
		this._connect();
	}

	_connect() {
		try {
			this.ws = new WebSocket(this.url);
			this.ws.binaryType = 'arraybuffer';

			this.ws.onopen = () => this._onOpen();
			this.ws.onclose = (e) => this._onClose(e);
			this.ws.onerror = (e) => this._onError(e);
			this.ws.onmessage = (e) => this._onMessage(e);
		} catch (err) {
			console.error('WebSocket connect failed:', err);
			this._scheduleReconnect();
		}
	}

	_onOpen() {
		console.log('Connected to Synmergia server');
		this._connected = true;
		this.reconnectAttempts = 0;
		this._emit('connected');

		// Send any queued messages
		while (this._messageQueue.length > 0) {
			const msg = this._messageQueue.shift();
			this._sendRaw(msg);
		}
	}

	_onClose(e) {
		console.log('Disconnected from server:', e.code, e.reason);
		this._connected = false;
		this._emit('disconnected', { code: e.code, reason: e.reason });
		this._scheduleReconnect();
	}

	_onError(e) {
		console.error('WebSocket error:', e);
		this._emit('error', e);
	}

	_onMessage(e) {
		try {
			const data = new Uint8Array(e.data);
			const msgType = data[0];
			const payload = data.slice(1);
			this._emit('message', { type: msgType, payload });
			this._handleMessage(msgType, payload);
		} catch (err) {
			console.error('Failed to parse message:', err);
		}
	}

	_handleMessage(type, payload) {
		const handler = this.handlers[type];
		if (handler) {
			handler(payload);
		}
	}

	_emit(event, data) {
		const handlers = this.handlers['*'] || [];
		for (const h of handlers) h(event, data);
	}

	_sendRaw(data) {
		if (this.ws && this.ws.readyState === WebSocket.OPEN) {
			this.ws.send(data);
			return true;
		}
		return false;
	}

	send(type, payload) {
		const msg = new Uint8Array(payload.length + 1);
		msg[0] = type;
		msg.set(payload, 1);

		if (!this._sendRaw(msg)) {
			this._messageQueue.push(msg);
		}
	}

	on(event, handler) {
		if (!this.handlers[event]) this.handlers[event] = [];
		this.handlers[event].push(handler);
	}

	off(event, handler) {
		if (this.handlers[event]) {
			const idx = this.handlers[event].indexOf(handler);
			if (idx >= 0) this.handlers[event].splice(idx, 1);
		}
	}

	_scheduleReconnect() {
		if (this.reconnectAttempts >= this.maxReconnectAttempts) {
			this._emit('reconnect_failed');
			return;
		}
		this.reconnectAttempts++;
		const delay = this.reconnectDelay * Math.pow(2, this.reconnectAttempts - 1);
		console.log(`Reconnecting in ${delay}ms (attempt ${this.reconnectAttempts})`);
		setTimeout(() => this._connect(), delay);
	}

	isConnected() {
		return this._connected;
	}
}

// Export singleton
window.SynmergiaNetwork = new SynmergiaNetwork();