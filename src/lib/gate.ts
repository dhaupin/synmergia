// Shared gate machinery for /admin and /play (single-operator law).
//
// Threat model, stated honestly: this is a STATIC site. The bundle is
// readable by anyone, so the password's sha256 ships in the clear and
// a determined attacker can brute-force offline. These gates are
// friction against lazy scripts and drive-by lookers, not a security
// boundary — the real boundary is the Cloudflare WAF rate rule on the
// gate POST-like endpoints plus the bridge binding (see DEPLOY.md).
// Client-side QoS (exponential backoff below) handles the restless
// human and the naive script; the WAF handles the real one.

export const sha256 = (ascii: string): string => {
  const rightRotate = (v: number, n: number) => (v >>> n) | (v << (32 - n));
  const words: number[] = [];
  for (let i = 0; i < ascii.length; i++) {
    words[i >> 2] = (words[i >> 2] || 0) | (ascii.charCodeAt(i) << (24 - 8 * (i % 4)));
  }
  words[ascii.length >> 2] |= 0x80 << (24 - 8 * (ascii.length % 4));
  words[((ascii.length + 8) >> 6) * 16 + 15] = ascii.length * 8;
  const H: number[] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
  const k = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];
  const w = new Array<number>(64);
  for (let j = 0; j < words.length; j += 16) {
    for (let i = 0; i < 16; i++) w[i] = words[j + i] || 0;
    for (let i = 16; i < 64; i++) {
      const s0 = rightRotate(w[i - 15], 7) ^ rightRotate(w[i - 15], 18) ^ (w[i - 15] >>> 3);
      const s1 = rightRotate(w[i - 2], 17) ^ rightRotate(w[i - 2], 19) ^ (w[i - 2] >>> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) >>> 0;
    }
    // Working vars are COPIES of the state, not the state itself. The
    // pre-fix code compressed straight into H and never folded the
    // initial state back, so it returned the raw working vars instead
    // of (working vars + state) — every digest was wrong, and the
    // gate could never match a standard sha256 hex (caught by the
    // empty-string vector: gate gave 79a6dddb…, real is e3b0c442…).
    let a = H[0], b = H[1], c = H[2], d = H[3];
    let e = H[4], f = H[5], g = H[6], h = H[7];
    for (let i = 0; i < 64; i++) {
      const S1 = rightRotate(e, 6) ^ rightRotate(e, 11) ^ rightRotate(e, 25);
      const ch = (e & f) ^ (~e & g);
      const t1 = (h + S1 + ch + k[i] + w[i]) >>> 0;
      const S0 = rightRotate(a, 2) ^ rightRotate(a, 13) ^ rightRotate(a, 22);
      const maj = (a & b) ^ (a & c) ^ (b & c);
      const t2 = (S0 + maj) >>> 0;
      h = g; g = f; f = e; e = (d + t1) >>> 0;
      d = c; c = b; b = a; a = (t1 + t2) >>> 0;
    }
    H[0] = (H[0] + a) >>> 0; H[1] = (H[1] + b) >>> 0;
    H[2] = (H[2] + c) >>> 0; H[3] = (H[3] + d) >>> 0;
    H[4] = (H[4] + e) >>> 0; H[5] = (H[5] + f) >>> 0;
    H[6] = (H[6] + g) >>> 0; H[7] = (H[7] + h) >>> 0;
  }
  return H.map((x) => ('00000000' + ((x >>> 0).toString(16))).slice(-8)).join('');
};

// ── Attempt limiter: in-memory exponential backoff ───────────
// Per mount (page view). Not a durable record — a reload resets it,
// but the WAF rule is the durable wall; this only curbs the restless
// human and the naive replayer that lives inside one page load.
export class AttemptLimiter {
  private failures = 0;
  private lockedUntil = 0;

  /** Seconds the caller must wait before the next attempt (0 = now). */
  cooldownSeconds(): number {
    if (Date.now() < this.lockedUntil) {
      return Math.ceil((this.lockedUntil - Date.now()) / 1000);
    }
    return 0;
  }

  /** Register a failure; doubles the cooldown, capped at 5 min. */
  fail(): void {
    this.failures += 1;
    const seconds = Math.min(Math.pow(2, this.failures - 1) * 5, 300);
    this.lockedUntil = Date.now() + seconds * 1000;
  }

  /** Register a success; clears the limiter. */
  reset(): void {
    this.failures = 0;
    this.lockedUntil = 0;
  }
}

// ── Session-scoped unlock storage ────────────────────────────

export const unlockSession = (key: string): boolean => {
  try {
    return sessionStorage.getItem(key) === '1';
  } catch {
    return false;
  }
};

export const rememberUnlock = (key: string): void => {
  try {
    sessionStorage.setItem(key, '1');
  } catch {
    /* private mode: per-visit gate */
  }
};
