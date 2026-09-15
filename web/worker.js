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
  return env.ASSETS.fetch(request);
}