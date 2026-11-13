import React, { useMemo, useState } from 'react';
import {
  Trophy, Lock, Star, Swords, Map, Backpack, Users, Castle, Handshake,
  Hammer, Flame, Skull, Compass, Sunrise, Sparkles, Heart, ScrollText,
  Coins, Crown, Award, CheckCircle2, User,
} from 'lucide-react';
import type { AchievementCategoryId, AchievementDef } from '../types';
import type { AchievementEngineState } from '../services/achievements';
import {
  getAchievementsByCategory,
  getChainProgress,
  getAchievementProgress,
  getOnboardingChain,
  getCatalog,
} from '../services/achievements';

interface AchievementsModalProps {
  isOpen: boolean;
  engineState: AchievementEngineState | null;
  unlockedIds: string[];
  onClose: () => void;
}

const ICONS: Record<string, React.ComponentType<{ className?: string }>> = {
  Trophy, Lock, Star, Swords, Map, Backpack, Users, Castle, Handshake,
  Hammer, Flame, Skull, Compass, Sunrise, Sparkles, Heart, ScrollText,
  Coins, Crown, Award, User,
};

const CATEGORIES: Array<{ id: AchievementCategoryId; label: string }> = [
  { id: 'combat', label: 'Combat' },
  { id: 'progression', label: 'Progression' },
  { id: 'exploration', label: 'Exploration' },
  { id: 'economy', label: 'Economy' },
  { id: 'social', label: 'Social' },
];

const TIER_BADGE: Record<string, string> = {
  bronze: 'bg-amber-950/60 text-amber-300 border-amber-600/50',
  silver: 'bg-slate-700/50 text-slate-200 border-slate-400/40',
  gold: 'bg-amber-800/60 text-amber-200 border-amber-400/60',
  epic: 'bg-fuchsia-950/60 text-fuchsia-300 border-fuchsia-400/60',
};

export const AchievementsModal: React.FC<AchievementsModalProps> = ({
  isOpen,
  engineState,
  unlockedIds,
  onClose,
}) => {
  const [activeCategory, setActiveCategory] = useState<AchievementCategoryId>('combat');

  const byCategory = useMemo(() => (isOpen ? getAchievementsByCategory() : null), [isOpen]);
  const chainProgress = useMemo(
    () => (isOpen && engineState ? getChainProgress(engineState) : null),
    [isOpen, engineState]
  );
  const totalPoints = useMemo(() => {
    if (!engineState) return 0;
    return getCatalog()
      .filter((d) => engineState.unlocked[d.id])
      .reduce((sum, d) => sum + d.points, 0);
  }, [engineState]);

  if (!isOpen) return null;

  // Lock safety for a state that failed to bootstrap.
  if (!engineState || !byCategory) {
    return (
      <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/75 backdrop-blur-sm">
        <div className="relative w-full max-w-xl bg-slate-900 border border-slate-700 rounded-2xl shadow-2xl p-6 text-slate-100">
          <h2 className="text-lg font-fantasy font-bold">Hall of Valor</h2>
          <p className="text-sm text-slate-400 mt-2">Achievement records are still initializing...</p>
          <button
            onClick={onClose}
            className="mt-4 text-slate-400 hover:text-slate-200 text-lg p-1"
          >
            ✕
          </button>
        </div>
      </div>
    );
  }

  const defsForCategory = byCategory[activeCategory] ?? [];

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/75 backdrop-blur-sm">
      <div
        id="achievements-modal"
        className="relative w-full max-w-2xl bg-slate-900 border border-slate-700 rounded-2xl shadow-2xl p-6 text-slate-100 max-h-[85vh] overflow-y-auto"
      >
        {/* Header */}
        <div className="flex items-center justify-between border-b border-slate-800 pb-3 mb-4">
          <div className="flex items-center gap-2">
            <Trophy className="w-5 h-5 text-amber-400" />
            <div>
              <h2 className="text-lg font-fantasy font-bold text-slate-100">Hall of Valor</h2>
              <p className="text-[11px] text-slate-400">Triumphs & legendary feats of Synmergia</p>
            </div>
          </div>
          <div className="flex items-center gap-3">
            <div className="flex items-center gap-1 text-xs font-bold text-amber-400 bg-slate-950 px-2.5 py-1 rounded-lg border border-amber-500/30">
              <Star className="w-3.5 h-3.5 fill-amber-400" />
              <span>{totalPoints} Pts</span>
            </div>
            <button onClick={onClose} className="text-slate-400 hover:text-slate-200 text-lg p-1">
              ✕
            </button>
          </div>
        </div>

        {/* Onboarding chain: "First Steps in Haven" */}
        {chainProgress && (
          <div className="mb-5 p-4 rounded-xl border border-amber-500/30 bg-gradient-to-br from-amber-950/25 to-slate-950/50">
            <div className="flex items-center justify-between mb-2">
              <h3 className="font-fantasy font-bold text-sm text-amber-200 flex items-center gap-1.5">
                <Sunrise className="w-4 h-4 text-amber-400" />
                First Steps in Haven
              </h3>
              <span className="text-[11px] font-bold text-amber-300">
                {chainProgress.completed} / {chainProgress.total}
              </span>
            </div>
            <div className="w-full h-2 bg-slate-950 rounded-full overflow-hidden border border-slate-800 mb-3">
              <div
                className="h-full bg-gradient-to-r from-amber-600 via-amber-400 to-amber-300 transition-all duration-300"
                style={{
                  width: `${chainProgress.total > 0 ? (chainProgress.completed / chainProgress.total) * 100 : 0}%`,
                }}
              />
            </div>
            <div className="flex flex-wrap gap-1.5">
              {getOnboardingChain().map((def) => {
                const done = Boolean(engineState.unlocked[def.id]);
                return (
                  <span
                    key={def.id}
                    title={`${def.title} - ${def.description}`}
                    className={`flex items-center gap-1 text-[10px] font-medium px-2 py-0.5 rounded-full border ${
                      done
                        ? 'bg-emerald-950/60 text-emerald-300 border-emerald-500/40'
                        : 'bg-slate-950/60 text-slate-500 border-slate-700/60'
                    }`}
                  >
                    {done ? <CheckCircle2 className="w-3 h-3" /> : <Lock className="w-3 h-3" />}
                    {def.title}
                  </span>
                );
              })}
            </div>
          </div>
        )}

        {/* Category tabs */}
        <div className="flex flex-wrap gap-1.5 mb-4">
          {CATEGORIES.map((cat) => {
            const defs = byCategory[cat.id] ?? [];
            const unlockedCount = defs.filter((d) => engineState.unlocked[d.id]).length;
            return (
              <button
                key={cat.id}
                onClick={() => setActiveCategory(cat.id)}
                className={`px-3 py-1 rounded-lg text-xs font-bold transition border ${
                  activeCategory === cat.id
                    ? 'bg-slate-800 text-amber-300 border-amber-500/40'
                    : 'bg-slate-950/60 text-slate-400 border-slate-800 hover:text-slate-200'
                }`}
              >
                {cat.label}
                <span className="ml-1.5 text-[10px] opacity-70">
                  {unlockedCount}/{defs.length}
                </span>
              </button>
            );
          })}
        </div>

        {/* Achievement list for the active category */}
        <div className="space-y-2.5">
          {defsForCategory.length === 0 && (
            <div className="p-4 rounded-xl bg-slate-950/60 border border-slate-800 text-center text-xs text-slate-400">
              Nothing recorded in this hall yet.
            </div>
          )}
          {defsForCategory.map((def) => {
            const isUnlocked = Boolean(engineState.unlocked[def.id]);
            const progress = getAchievementProgress(def, engineState);
            const Icon = ICONS[def.icon] ?? Award;
            return (
              <div
                key={def.id}
                className={`p-3.5 rounded-xl border transition ${
                  isUnlocked
                    ? 'border-amber-500/50 bg-amber-950/20 shadow'
                    : 'border-slate-800/80 bg-slate-950/60'
                }`}
              >
                <div className="flex items-center justify-between gap-3">
                  <div className="flex items-center gap-3 min-w-0">
                    <div
                      className={`w-9 h-9 rounded-lg flex items-center justify-center border shrink-0 ${
                        isUnlocked
                          ? 'border-amber-400 bg-amber-950/60 text-amber-300'
                          : 'border-slate-800 bg-slate-900 text-slate-600'
                      }`}
                    >
                      {isUnlocked ? <Icon className="w-4 h-4" /> : <Lock className="w-4 h-4" />}
                    </div>
                    <div className="min-w-0">
                      <div className="flex items-center gap-2">
                        <h4 className="font-fantasy font-bold text-sm text-slate-100 truncate">
                          {def.title}
                        </h4>
                        <span
                          className={`text-[9px] uppercase font-bold px-1.5 py-0.5 rounded border ${
                            TIER_BADGE[def.tier] ?? TIER_BADGE.bronze
                          }`}
                        >
                          {def.tier}
                        </span>
                      </div>
                      <p className="text-xs text-slate-400 truncate">{def.description}</p>
                    </div>
                  </div>

                  <div className="text-right shrink-0">
                    <span className="text-xs font-bold text-amber-400 block">+{def.points} Pts</span>
                    {(def.goldReward > 0 || def.xpReward > 0) && (
                      <span className="text-[9px] text-slate-500">
                        {def.goldReward > 0 && `${def.goldReward}g`}
                        {def.goldReward > 0 && def.xpReward > 0 && ' / '}
                        {def.xpReward > 0 && `${def.xpReward}xp`}
                      </span>
                    )}
                  </div>
                </div>

                {/* Progress bar for counter achievements not yet unlocked */}
                {!isUnlocked && def.counter && def.target != null && progress.target > 1 && (
                  <div className="mt-2.5 space-y-1">
                    <div className="flex justify-between text-[10px] text-slate-500">
                      <span>Progress</span>
                      <span className="font-mono text-slate-400">
                        {progress.current} / {progress.target}
                      </span>
                    </div>
                    <div className="w-full h-1.5 bg-slate-900 rounded-full overflow-hidden border border-slate-800">
                      <div
                        className="h-full bg-sky-500/70 transition-all duration-300"
                        style={{ width: `${progress.pct}%` }}
                      />
                    </div>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
};

