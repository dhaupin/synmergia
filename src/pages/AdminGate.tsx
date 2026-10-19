import { useState } from 'react';
import { Lock, ShieldCheck } from 'lucide-react';
import { AdminDashboardView } from '../components/admin/AdminDashboardView';

// Admin gate (single-operator law): the dashboard touches the real
// database bridges, so the route itself must not be free. A modest
// password check — the password never ships as plaintext; the build
// inlines its SHA-256 (VITE_ADMIN_PASSWORD_SHA at build time), the
// entry hashes it with the tiny pure-JS shainter below, and success
// is remembered in sessionStorage for the tab session only.
//
// Threat-model note: this is a static site. A determined attacker can
// read the bundle and see the hash, so this gate is "keeps honest
// people and lazy scripts out", NOT a secure boundary. The real
// protection for ops data is the bridge binding to loopback on the
// server side; the wall here is deliberate friction, defense in depth
// for a zero-trust static host. Upgrade path documented in DEPLOY.md.

// Pure-JS SHA-256, no dependency. (Web Crypto's digest() is async and
// fine, but subtile broken-imports paths want sync here for the
// enter-key handler.)
function sha256(ascii: string): string {
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
    for (let i = 0; i < 64; i++) {
      const S1 = rightRotate(H[4], 6) ^ rightRotate(H[4], 11) ^ rightRotate(H[4], 25);
      const ch = (H[4] & H[5]) ^ (~H[4] & H[6]);
      const t1 = (H[7] + S1 + ch + k[i] + w[i]) >>> 0;
      const S0 = rightRotate(H[0], 2) ^ rightRotate(H[0], 13) ^ rightRotate(H[0], 22);
      const maj = (H[0] & H[1]) ^ (H[0] & H[2]) ^ (H[1] & H[2]);
      const t2 = (S0 + maj) >>> 0;
      H[7] = H[6]; H[6] = H[5]; H[5] = H[4]; H[4] = (H[3] + t1) >>> 0;
      H[3] = H[2]; H[2] = H[1]; H[1] = H[0]; H[0] = (t1 + t2) >>> 0;
    }
  }
  return H.map((x) => ('00000000' + ((x >>> 0).toString(16))).slice(-8)).join('');
}

const GATE_HASH =
  (import.meta.env.VITE_ADMIN_PASSWORD_SHA as string | undefined)?.toLowerCase() || '';
const GATE_KEY = 'syn_admin_ok';

export default function AdminGate() {
  const [unlocked, setUnlocked] = useState<boolean>(() => {
    try {
      return sessionStorage.getItem(GATE_KEY) === '1';
    } catch {
      return false;
    }
  });
  const [attempt, setAttempt] = useState('');
  const [error, setError] = useState(false);

  const tryUnlock = () => {
    if (!GATE_HASH) {
      setError(true);
      return;
    }
    if (sha256(attempt) === GATE_HASH) {
      try {
        sessionStorage.setItem(GATE_KEY, '1');
      } catch {
        /* private mode: per-visit gate */
      }
      setUnlocked(true);
    } else {
      setError(true);
      setAttempt('');
    }
  };

  if (unlocked) {
    return <AdminDashboardView />;
  }

  return (
    <div className="max-w-md mx-auto px-4 py-24">
      <div className="rounded-2xl border border-line bg-surface p-8">
        <div className="w-12 h-12 rounded-full bg-accent/15 text-accent flex items-center justify-center mx-auto mb-4">
          <Lock className="w-6 h-6" />
        </div>
        <h1 className="font-display text-2xl text-center mb-1">Operator access</h1>
        <p className="text-xs text-ink-soft text-center mb-6">
          Restricted ops tooling. Enter the key to proceed.
        </p>
        <label htmlFor="admin-pass" className="sr-only">
          Operator key
        </label>
        <input
          id="admin-pass"
          type="password"
          value={attempt}
          onChange={(e) => {
            setAttempt(e.target.value);
            setError(false);
          }}
          onKeyDown={(e) => e.key === 'Enter' && tryUnlock()}
          placeholder="Operator key"
          autoComplete="off"
          className={`w-full bg-paper rounded-lg border px-3 py-2.5 text-sm mb-3 outline-none focus:border-accent transition-colors ${
            error ? 'border-err text-err' : 'border-line'
          }`}
        />
        {error && <p className="text-xs text-err mb-3">{GATE_HASH ? 'Key rejected.' : 'Gate not configured (VITE_ADMIN_PASSWORD_SHA missing at build).'}</p>}
        <button
          type="button"
          onClick={tryUnlock}
          className="w-full py-2.5 rounded-lg bg-accent text-paper font-semibold text-sm hover:bg-accent-deep transition-colors flex items-center justify-center gap-2"
        >
          <ShieldCheck className="w-4 h-4" />
          Unlock
        </button>
      </div>
    </div>
  );
}
