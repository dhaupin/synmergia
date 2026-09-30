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
//   game.pck?v=<hash>    -> immutable, 1 year (content-addressed: CI
//     writes web/game.pck.hash on every content change and game.html
//     appends ?v=<hash> via mainPack). Bare /game.pck 302s to the
//     current hash so old bookmarks and direct links still resolve.
//   game.pck.hash        -> no-store (the cache-buster itself).
//   index/game.html      -> no-store (must always pair the right
//     wasm/pck pair). Everything else (icons, css, config) -> 1 hour.
const IMMUTABLE_FILES = new Set(['game.wasm', 'game.js', 'game.pck']);

function serveStatic(request, ctx, env) {
	const url = new URL(request.url);
	const file = url.pathname.split('/').pop() || '';

	// Content-addressed pack: the bare path carries no version. Redirect
	// to the hashed URL (reads the hash off the ASSETS copy cheaply via
	// env var if provided, else off the file itself) so direct links get
	// the cacheable form and the HTML keeps one fetch flow.
	if (file === 'game.pck' && !url.searchParams.has('v')) {
		return resolvePckHash(env).then((hash) => {
			const target = new URL(request.url);
			if (hash !== '') {
				target.searchParams.set('v', hash);
				return Response.redirect(target.toString(), 302);
			}
			// No hash published (first deploy / hash step not run yet):
			// serve bare with no-store so stale packs can never stick.
			return servePck(request, ctx, env, 'no-store, must-revalidate');
		});
	}

	if (file === 'game.pck' && url.searchParams.has('v')) {
		// Hashed request: immutable (the version IS the content).
		return servePck(request, ctx, env, 'public, max-age=31536000, immutable');
	}

	if (file === 'game.pck.hash') {
		// The cache-buster itself must never be cached.
		return env.ASSETS.fetch(request).then((resp) => {
			const out = new Response(resp.body, resp);
			out.headers.set('Cache-Control', 'no-store, must-revalidate');
			out.headers.set('X-Content-Type-Options', 'nosniff');
			return out;
		});
	}

	if (IMMUTABLE_FILES.has(file)) {
		const cacheUrl = new URL(request.url);
		// Ignore query strings for the engine pair: one edge entry.
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
		if (file === 'index.html' || file === 'game.html') {
			out.headers.set('Cache-Control', 'no-store, must-revalidate');
		} else {
			out.headers.set('Cache-Control', 'public, max-age=3600');
		}
		out.headers.set('X-Content-Type-Options', 'nosniff');
		return out;
	});
}

// Read the current pack hash. PCK_HASH env var wins (set it in the
// wrangler vars on deploy for zero extra fetches); otherwise fetch the
// hash file once per invocation (edge cache keeps this cheap).
function resolvePckHash(env) {
	if (env.PCK_HASH) {
		return Promise.resolve(String(env.PCK_HASH));
	}
	const hashUrl = new URL('/', 'https://hash.invalid');
	return env.ASSETS.fetch(new Request('/game.pck.hash'))
		.then((r) => (r.ok ? r.text() : ''))
		.then((t) => t.trim())
		.catch(() => '');
}

// Serve the pack bytes with the given cache policy (edge-cached per
// full URL, so ?v=<hash> entries accumulate one per release and old
// ones simply expire).
function servePck(request, ctx, env, cacheControl) {
	return ctx.cache.match(request).then((cached) => {
		if (cached) {
			return cached;
		}
		return env.ASSETS.fetch(new Request(request.url.split('?')[0])).then((resp) => {
			const out = new Response(resp.body, resp);
			out.headers.set('Cache-Control', cacheControl);
			out.headers.set('X-Content-Type-Options', 'nosniff');
			if (cacheControl.indexOf('immutable') !== -1) {
				ctx.cache.put(request, out.clone());
			}
			return out;
		});
	});
}