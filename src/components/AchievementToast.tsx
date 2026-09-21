import React, { useEffect, useRef, useState } from 'react';
import confetti from 'canvas-confetti';
import { Trophy, X } from 'lucide-react';
import type { AchievementUnlock } from '../services/achievements';

interface AchievementToastProps {
  toasts: AchievementUnlock[];
  onDismiss: (unlock: AchievementUnlock) => void;
  /** Skip the confetti burst (used when honoring mute). */
  muted?: boolean;
}

const TIER_ACCENT: Record<string, string> = {
  bronze: 'border-amber-600/70 from-amber-950/80',
  silver: 'border-slate-300/60 from-slate-700/70',
  gold: 'border-amber-400/80 from-amber-900/70',
  epic: 'border-fuchsia-400/80 from-fuchsia-950/70',
};

export const AchievementToast: React.FC<AchievementToastProps> = ({
  toasts,
  onDismiss,
  muted = false,
}) => {
  const lastCountRef = useRef(0);

  // Confetti once per unlock batch (not per toast, to avoid spam).
  useEffect(() => {
    if (toasts.length > lastCountRef.current && !muted && toasts.length > 0) {
      confetti({
        particleCount: 90,
        spread: 75,
        startVelocity: 38,
        origin: { y: 0.22 },
        colors: ['#facc15', '#f59e0b', '#fde68a', '#fff7ed'],
        disableForReducedMotion: true,
      });
    }
    lastCountRef.current = toasts.length;
  }, [toasts, muted]);

  if (toasts.length === 0) return null;

  return (
    <div className="pointer-events-none absolute top-24 left-1/2 -translate-x-1/2 z-50 flex flex-col items-center gap-2 w-[min(92vw,26rem)]">
      {toasts.slice(-3).map((unlock) => (
        <AchievementToastCard key={unlock.def.id} unlock={unlock} onDismiss={onDismiss} />
      ))}
    </div>
  );
};

const AchievementToastCard: React.FC<{
  unlock: AchievementUnlock;
  onDismiss: (unlock: AchievementUnlock) => void;
}> = ({ unlock, onDismiss }) => {
  const [leaving, setLeaving] = useState(false);
  const timerRef = useRef<number | null>(null);

  const startDismiss = () => {
    setLeaving(true);
    timerRef.current = window.setTimeout(() => onDismiss(unlock), 240);
  };

  useEffect(() => {
    timerRef.current = window.setTimeout(startDismiss, 5200);
    return () => {
      if (timerRef.current) window.clearTimeout(timerRef.current);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const accent = TIER_ACCENT[unlock.def.tier] ?? TIER_ACCENT.bronze;

  return (
    <div
      id={`achievement-toast-${unlock.def.id}`}
      className={`pointer-events-auto w-full flex items-center gap-3 rounded-xl border bg-gradient-to-r to-slate-900/95 px-4 py-3 shadow-2xl backdrop-blur-md transition-all duration-200 ${
        accent
      } ${leaving ? 'opacity-0 -translate-y-2' : 'opacity-100 translate-y-0'}`}
    >
      <div className="w-10 h-10 rounded-lg border border-amber-400/60 bg-amber-950/50 flex items-center justify-center shrink-0">
        <Trophy className="w-5 h-5 text-amber-300" />
      </div>
      <div className="flex-1 min-w-0">
        <p className="text-[10px] uppercase font-bold tracking-widest text-amber-400/90">
          Achievement Unlocked
        </p>
        <p className="text-sm font-fantasy font-bold text-slate-100 truncate">
          {unlock.def.title}
        </p>
        <p className="text-[11px] text-slate-400 truncate">{unlock.def.description}</p>
      </div>
      {(unlock.def.goldReward > 0 || unlock.def.xpReward > 0) && (
        <div className="text-right shrink-0">
          {unlock.def.goldReward > 0 && (
            <span className="block text-[11px] font-bold text-amber-300">
              +{unlock.def.goldReward}g
            </span>
          )}
          {unlock.def.xpReward > 0 && (
            <span className="block text-[11px] font-bold text-sky-300">
              +{unlock.def.xpReward} XP
            </span>
          )}
        </div>
      )}
      <button
        onClick={startDismiss}
        className="text-slate-500 hover:text-slate-200 p-1 shrink-0"
        title="Dismiss"
      >
        <X className="w-3.5 h-3.5" />
      </button>
    </div>
  );
};
