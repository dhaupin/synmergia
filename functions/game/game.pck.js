// Pages Function: stream the Godot CONTENT pack (game.pck) from R2.
//
// Migrated off the Pages asset tree (2026-10-19): CI commit-backs were
// growing the repo by ~6 MB per content change, and game.pck will
// eventually cross the Pages 25 MiB per-file cap (game.wasm already
// did — see functions/game/game.wasm.js). R2 is the serving home; the
// bundled copy in dist/game/ is the warm standby.
//
// Order of preference:
//   1. R2 object `game.pck` via the R2_GAME_WASM binding (CI keeps it
//      fresh on every push; local uploads via npm run r2:put:pck).
//   2. Stale fallback: the copy vite ships into dist/game/ — warm
//      standby so a cold bucket or CI-without-token can never 404 the
//      whole client. Served with no-store so a stale pack never sticks
//      past this request.
//
// The hash flow is unchanged: game.pck.hash keeps shipping from the
// bundled assets (it is tiny and boot law requires it no-cache), so
// the shell still fetches game.pck?v=<hash>. This function ignores
// the query for R2 lookup (the cache key) but honors it for edge
// caching semantics per the worker prior-art in web/worker.js.
const ONE_DAY = 86400;

function parseRange(header) {
	const m = /^bytes=(\d*)-(\d*)$/.exec(header || "");
	if (!m) return null;
	const [, a, b] = m;
	if (a === "" && b === "") return null;
	if (a === "") return { suffix: parseInt(b, 10) };
	if (b === "") return { offset: parseInt(a, 10) };
	const offset = parseInt(a, 10);
	const length = parseInt(b, 10) - offset + 1;
	return length > 0 ? { offset, length } : null;
}

export const onRequest = async (ctx) => {
	const bucket = ctx.env.R2_GAME_WASM;

	if (bucket) {
		const range = parseRange(ctx.request.headers.get("range"));
		const object = range
			? await bucket.get("game.pck", { range })
			: await bucket.get("game.pck");

		if (object) {
			const headers = new Headers();
			headers.set("Content-Type", "application/octet-stream");
			headers.set("ETag", object.httpEtag);
			if (range && object.range && typeof object.range.offset === "number") {
				headers.set(
					"Content-Range",
					"bytes " + object.range.offset + "-" + (object.range.offset + object.range.length - 1) + "/" + object.size
				);
				headers.set("Accept-Ranges", "bytes");
				const out = new Response(object.body, { headers });
				out.status = 206;
				return out;
			}
			// Content-addressed by the ?v= hash, so the URL is the cache
			// key — an immutable entry per release, per _headers semantics.
			const bare = new URL(ctx.request.url);
			bare.search = "";
			const isContentAddressed = bare.pathname === "/game/game.pck" && new URL(ctx.request.url).searchParams.has("v");
			headers.set(
				"Cache-Control",
				isContentAddressed
					? "public, max-age=" + ONE_DAY * 365 + ", immutable"
					: "public, max-age=" + ONE_DAY
			);
			return new Response(object.body, { headers });
		}
	}

	// Fallback: stream the bundled (possibly stale) copy from dist/.
	// env.ASSETS routes past the function; dist/game/game.pck still
	// ships in the bundle (5.8 MB today, under the cap), so this only
	// fires when R2 is cold, unwired, or stale.
	const assetResp = await ctx.env.ASSETS.fetch(new Request(ctx.request.url.split("?")[0], { method: "GET" }));
	if (assetResp.status === 200) {
		const out = new Response(assetResp.body, assetResp);
		out.headers.set("Cache-Control", "no-store, must-revalidate");
		out.headers.set("X-Content-Type-Options", "nosniff");
		out.headers.set("X-Synmergia-Pack-Source", "bundled-fallback");
		return out;
	}

	return new Response(
		"game.pck missing from both R2 and the bundled assets. Run: npm run r2:put:pck (DEPLOY_WEB.md §3b).",
		{ status: 404, headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" } }
	);
};
