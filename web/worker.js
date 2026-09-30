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

		// ── Static files ──────────────────────────────────────────
		return serveStatic(request, ctx, env);
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

// Cache policy (play-day feedback A -- players were re-downloading
// the 38 MB engine on every visit):
//
//   game.wasm / game.js  -> immutable, 1 year. The Godot engine bundle
//     changes only when the engine/export template changes (rare); the
//     deploy flow updates BOTH the files and this policy together.
//     Cloudflare edge-caches these (cacheEverything), so most players
//     never even hit origin.
//   game.pck             -> no-store. Content changes on every game
//     push; the engine fetches it after boot, so an aggressive TTL here
//     would serve stale GAME content. (If pck size grows painful, the
//     follow-up is hash-suffixed pck filenames + immutable cache --
//     a build-script change, not a policy change.)
//   index/game.html      -> no-store (must always pair the right
//     wasm/pck pair). Everything else (icons, css, config) -> 1 hour.
const IMMUTABLE_FILES = new Set(['game.wasm', 'game.js']);

function serveStatic(request, ctx, env) {
	const url = new URL(request.url);
	const file = url.pathname.split('/').pop() || '';

	if (IMMUTABLE_FILES.has(file)) {
		const cacheUrl = new URL(request.url);
		// Ignore query strings for the immutable pair: one edge entry.
		cacheUrl.search = '';
		const cacheKey = new Request(cacheUrl.toString(), request);
		return ctx.cache.match(cacheKey).then((cached) => {
			if (cached) {
				return cached;
			}
			return env.ASSETS.fetch(request).then((resp) => {
				const cachedResp = new Response(resp.body, resp);
				cachedResp.headers.set('Cache-Control', 'public, max-age=31536000, immutable');
				cachedResp.headers.set('X-Content-Type-Options', 'nosniff');
				ctx.cache.put(cacheKey, cachedResp.clone());
				return cachedResp;
			});
		});
	}

	return env.ASSETS.fetch(request).then((resp) => {
		const out = new Response(resp.body, resp);
		if (file === 'game.pck' || file === 'index.html' || file === 'game.html') {
			out.headers.set('Cache-Control', 'no-store, must-revalidate');
		} else {
			out.headers.set('Cache-Control', 'public, max-age=3600');
		}
		out.headers.set('X-Content-Type-Options', 'nosniff');
		return out;
	});
}