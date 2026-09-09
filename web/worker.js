// Cloudflare Worker - Synmergia Web Client
// Serves static files and proxies WebSocket connections to the server.

export default {
	async fetch(request, env, ctx) {
		const url = new URL(request.url);

		// ── WebSocket upgrade ──────────────────────────────────────────
		if (request.headers.get('Upgrade') === 'websocket') {
			return handleWebSocket(request, env);
		}

		// ── API proxy ──────────────────────────────────────────────────
		if (url.pathname.startsWith('/api/')) {
			return proxyToApi(request, env);
		}

		// ── Static files ───────────────────────────────────────────────
		return serveStatic(request, env);
	},
};

function handleWebSocket(request, env) {
	const upgradeHeader = request.headers.get('Upgrade');
	if (upgradeHeader !== 'websocket') {
		return new Response('Expected WebSocket', { status: 400 });
	}

	const serverUrl = env.SERVER_URL || 'wss://localhost:9000/ws';
	const ws = new WebSocket(serverUrl);

	return new Response(ws, { status: 101 });
}

function proxyToApi(request, env) {
	const apiUrl = env.API_URL || 'https://localhost:8080';
	const targetUrl = apiUrl + request.url.replace(/^.*\/\/[^\/]+/, '');

	return fetch(targetUrl, {
		method: request.method,
		headers: request.headers,
		body: request.body,
	});
}

function serveStatic(request, env) {
	const url = new URL(request.url);
	const pathname = url.pathname;

	// Map paths to file extensions
	const pathMap = {
		'/': '/index.html',
		'/game.js': '/game.js',
		'/game.wasm': '/game.wasm',
		'/game.pck': '/game.pck',
		'/config.js': '/config.js',
		'/style.css': '/style.css',
		'/icon.svg': '/icon.svg',
	};

	const filePath = pathMap[pathname] || pathname;
	const cacheTTL = getCacheTTL(filePath);

	const response = new Response(
		`File not found: ${filePath}`,
		{ status: 404, headers: { 'Content-Type': 'text/plain' } }
	);

	return response;
}

function getCacheTTL(path) {
	if (path.endsWith('.wasm') || path.endsWith('.pck')) return 31536000;
	if (path.endsWith('.js')) return 86400;
	if (path.endsWith('.html') || path.endsWith('.css')) return 0;
	return 3600;
}