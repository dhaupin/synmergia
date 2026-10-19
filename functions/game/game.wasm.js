// Pages Function: stream the oversized Godot engine binary from R2.
//
// game.wasm is ~37 MiB, beyond the Pages 25 MiB per-file asset cap
// (docs: https://developers.cloudflare.com/pages/platform/limits —
// no plan override exists, Workers static assets cap the same way).
// The file ships via an R2 bucket; this function streams it so the
// client still loads /game/game.wasm with no HTML or loader change
// (the URL is baked into web/game.js). The vite build excludes the
// file from dist/ (see copy-godot-web plugin) so Pages validation
// passes; in dev/preview Vite serves the local web/ copy directly.
//
// Streaming law: return the R2 ReadableStream directly. Never
// .arrayBuffer()/.blob() the whole object — that buffers ~38 MB per
// in-flight download on a 128 MB isolate.
//
// Byte range: Godot's loader can issue Range requests on the engine;
// parse the header and hand R2 the proper {offset,length|suffix}.
//
// QoS law (WAF-off fallback): the paid WAF rate rules are OFF, so this
// Function rate-limits per IP itself (see ../rate-limiter.js) — tuned
// loose enough that a page load + Godot's Range retries can never trip
// it, tight enough that bandwidth-bleed scripts stop. Fail-open.
import { RateLimiter, rateGate } from "../rate-limiter.js";
const ONE_DAY = 86400;
const WASM_LIMIT = new RateLimiter({ maxRequests: 30, windowMs: 60000 });

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
	const throttled = rateGate(WASM_LIMIT, ctx.request, "game.wasm");
	if (throttled) return throttled;

	const bucket = ctx.env.R2_GAME_WASM;
	if (!bucket) {
		return new Response(
			"R2_GAME_WASM binding missing. Pages dashboard → Settings → Bindings → R2, then upload with: npm run r2:put:wasm (DEPLOY_WEB.md §3b).",
			{ status: 503, headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" } }
		);
	}

	const range = parseRange(ctx.request.headers.get("range"));
	const object = range
		? await bucket.get("game.wasm", { range })
		: await bucket.get("game.wasm");

	if (!object) {
		return new Response(
			"game.wasm not uploaded to R2 yet. Run: npm run r2:put:wasm (DEPLOY_WEB.md §3b).",
			{ status: 404, headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" } }
		);
	}

	const headers = new Headers();
	// Cache law mirrors _headers for /game/game.wasm: one-day TTL, the
	// no-cache boot anchors (index.html, game.pck.hash) keep a new
	// export honest on the next reload.
	headers.set("Content-Type", "application/wasm");
	headers.set("Cache-Control", "public, max-age=" + ONE_DAY);
	headers.set("ETag", object.httpEtag);
	if (range && object.range && typeof object.range.offset === "number") {
		headers.set("Content-Range", "bytes " + object.range.offset + "-" + (object.range.offset + object.range.length - 1) + "/" + object.size);
		headers.set("Accept-Ranges", "bytes");
	}

	const out = new Response(object.body, { headers });
	if (range) out.status = 206;
	return out;
};
