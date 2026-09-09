// Synmergia Web Client Configuration
// Edit these values to point to your server deployment.
window.SynmergiaConfig = {
	// Server WebSocket URL (ws:// or wss://)
	serverUrl: (location.protocol === 'https:' ? 'wss://' : 'ws://') + location.host + '/ws',

	// REST API base URL
	apiUrl: location.origin,

	// Godot engine options
	engineOptions: {
		// Enable the canvas for rendering
		module: 'game.wasm',
		// Use the WASM build
		wasm: true,
		// Initial arguments
		args: [],
		// Memory initial size (in MB)
		memory: 256,
		// Enable debug output
		debug: false,
	},

	// Input settings
	input: {
		// Shared buffer for input events (typed array)
		bufferSize: 65536,
		// Poll rate for input (ms)
		pollRate: 16,
	},

	// UI settings
	ui: {
		// Show FPS counter (for debugging)
		showFps: false,
		// Default graphics quality
		graphicsQuality: 'high',
	},
};