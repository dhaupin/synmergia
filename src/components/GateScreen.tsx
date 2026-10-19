import { useState } from 'react';
import { Lock } from 'lucide-react';
import { sha256, AttemptLimiter, unlockSession, rememberUnlock } from '../lib/gate';

interface GateScreenProps {
  /** sessionStorage key remembering an unlocked tab. */
  sessionKey: string;
  /** sha256 of the operator/key password, baked at build time ('' = unset). */
  gateHash: string;
  /** The name of the env var, shown only in the unconfigured error. */
  envVarName: string;
  /** The friendly headline shown before unlock ("coming soon" law). */
  headline: string;
  /** One-liner under the headline explaining why the gate exists. */
  blurb: string;
  /** What a successful unlock renders. */
  children: React.ReactNode;
}

// Shared gate screen: the "coming soon + key" wall for /play and
// /admin. One UX, two hashes, one rate limiter per mount. The limiter
// starts at 5 s and doubles per failure (5 s -> 10 -> 20 -> ...), hard
// capped at 5 minutes — enough to exhaust a restless human's patience
// long before the WAF rule (the real wall) even matters.
export default function GateScreen({ sessionKey, gateHash, envVarName, headline, blurb, children }: GateScreenProps) {
  const [unlocked, setUnlocked] = useState(() => gateHash !== '' && unlockSession(sessionKey));
  const [attempt, setAttempt] = useState('');
  const [error, setError] = useState('');
  const [limiter] = useState(() => new AttemptLimiter());
  const [cooldown, setCooldown] = useState(0);

  const tryUnlock = () => {
    const wait = limiter.cooldownSeconds();
    if (wait > 0) {
      setCooldown(wait);
      return;
    }
    if (!gateHash) {
      setError(`Gate not configured — set ${envVarName} at build time.`);
      return;
    }
    if (sha256(attempt) === gateHash) {
      limiter.reset();
      rememberUnlock(sessionKey);
      setUnlocked(true);
      return;
    }
    limiter.fail();
    setCooldown(limiter.cooldownSeconds());
    setError('Key rejected.');
    setAttempt('');
  };

  if (unlocked) {
    return <>{children}</>;
  }

  return (
    <div className="max-w-md mx-auto px-4 py-24">
      <div className="rounded-2xl border border-line bg-surface p-8">
        <div className="w-12 h-12 rounded-full bg-accent/15 text-accent flex items-center justify-center mx-auto mb-4">
          <Lock className="w-6 h-6" />
        </div>
        <h1 className="font-display text-2xl text-center mb-1">{headline}</h1>
        <p className="text-xs text-ink-soft text-center mb-6">{blurb}</p>

        <label htmlFor="gate-pass" className="sr-only">
          Access key
        </label>
        <input
          id="gate-pass"
          type="password"
          value={attempt}
          onChange={(e) => {
            setAttempt(e.target.value);
            setError('');
          }}
          onKeyDown={(e) => e.key === 'Enter' && tryUnlock()}
          placeholder="Access key"
          autoComplete="off"
          className={`w-full bg-paper rounded-lg border px-3 py-2.5 text-sm mb-3 outline-none focus:border-accent transition-colors ${
            error ? 'border-err text-err' : 'border-line'
          }`}
        />
        {error && <p className="text-xs text-err mb-3">{error}</p>}
        {cooldown > 0 && (
          <p className="text-xs text-accent mb-3">
            Too many attempts — wait {cooldown}s.
          </p>
        )}
        <button
          type="button"
          onClick={tryUnlock}
          disabled={cooldown > 0}
          className="w-full py-2.5 rounded-lg bg-accent text-paper font-semibold text-sm hover:bg-accent-deep transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
        >
          Unlock
        </button>
      </div>
    </div>
  );
}
