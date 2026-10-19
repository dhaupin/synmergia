// Workers-native per-IP in-memory rate limiter (Pages Functions).
//
// Graceful-fallback law (DEPLOY_WEB.md §5): the Cloudflare WAF rate
// rules are a PAID product and are deliberately OFF for this site.
// This module is the free defense-in-depth layer that still applies:
// an in-memory token window per IP, checked inside the Functions that
// stream the multi-MB R2 objects. API shape mirrors
// @creadev.org/security's RateLimiter (the Node-side toolkit for the
// game server) so the two can converge on one convention; this port
// never calls setInterval — Workers isolates are ephemeral, so cleanup
// is a lazy sweep and the limit is approximate across isolates/colos
// (per DOC, not a global quota; it stops lazy scripts and bandwidth
// bleeds, not determined attackers — same honest threat model as the
// gates).
//
// Fail-open law: any limiter error allows the request. QoS must never
// become the outage.
const MAX_KEYS = 4096; // bound memory per isolate

export class RateLimiter {
	constructor({ maxRequests, windowMs }) {
		this.maxRequests = maxRequests;
		this.windowMs = windowMs;
		this.hits = new Map(); // ip -> { count, resetAt }
	}

	check(key) {
		const now = Date.now();
		if (this.hits.size > MAX_KEYS) {
			for (const [k, v] of this.hits) if (now > v.resetAt) this.hits.delete(k);
		}
		const entry = this.hits.get(key);
		if (!entry || now > entry.resetAt) {
			this.hits.set(key, { count: 1, resetAt: now + this.windowMs });
			return { allowed: true, remaining: this.maxRequests - 1, retryAfter: 0 };
		}
		if (entry.count >= this.maxRequests) {
			return {
				allowed: false,
				remaining: 0,
				retryAfter: Math.max(1, Math.ceil((entry.resetAt - now) / 1000)),
			};
		}
		entry.count += 1;
		return { allowed: true, remaining: this.maxRequests - entry.count, retryAfter: 0 };
	}
}

/** True client IP as CF sees it, with a safe constant fallback. */
export function clientIp(request) {
	return request.headers.get("CF-Connecting-IP") || "unknown";
}

/**
 * Gate helper: returns a 429 Response when over limit, or null to
 * proceed. Fail-open on any internal error. `name` feeds the hint so
 * operators know which endpoint tripped.
 */
export function rateGate(limiter, request, name) {
	try {
		const decision = limiter.check(clientIp(request));
		if (decision.allowed) return null;
		return new Response(`429 ${name}: slow down (retry in ${decision.retryAfter}s)`, {
			status: 429,
			headers: {
				"Content-Type": "text/plain; charset=utf-8",
				"Cache-Control": "no-store",
				"Retry-After": String(decision.retryAfter),
			},
		});
	} catch (e) {
		return null; // fail-open: limiter broken != endpoint broken
	}
}
