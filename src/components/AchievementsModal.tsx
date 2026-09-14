import React from 'react';
import { Trophy, CheckCircle, Lock, Award, Star } from 'lucide-react';

interface Achievement {
  id: string;
  title: string;
  description: string;
  points: number;
  unlocked: boolean;
}

interface AchievementsModalProps {
  isOpen: boolean;
  unlockedIds: string[];
  onClose: () => void;
}

const ALL_ACHIEVEMENTS: Achievement[] = [
  {
    id: 'ach_first_blood',
    title: 'First Blood',
    description: 'Slay your first rogue beast or hostile outlaw in Synmergia.',
    points: 10,
    unlocked: false,
  },
  {
    id: 'ach_bandit_scourge',
    title: 'Scourge of the Outlaws',
    description: 'Vanquish 5 highwaymen or rogue bandits in the Sunstone Plains.',
    points: 25,
    unlocked: false,
  },
  {
    id: 'ach_boss_slayer',
    title: 'Conqueror of the Depths',
    description: 'Defeat the Netherlord Malgor in the Abyssal Cavern.',
    points: 50,
    unlocked: false,
  },
  {
    id: 'ach_master_smith',
    title: 'Dwarven Temper',
    description: 'Temper your primary armament at Torvald’s Forge.',
    points: 20,
    unlocked: false,
  },
  {
    id: 'ach_realm_traveler',
    title: 'Wayfarer of the Shards',
    description: 'Travel through 3 distinct continental zones and discover their portals.',
    points: 30,
    unlocked: false,
  },
];

export const AchievementsModal: React.FC<AchievementsModalProps> = ({
  isOpen,
  unlockedIds,
  onClose,
}) => {
  if (!isOpen) return null;

  const totalPoints = ALL_ACHIEVEMENTS.filter((a) =>
    unlockedIds.includes(a.id)
  ).reduce((sum, a) => sum + a.points, 0);

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/75 backdrop-blur-sm">
      <div
        id="achievements-modal"
        className="relative w-full max-w-xl bg-slate-900 border border-slate-700 rounded-2xl shadow-2xl p-6 text-slate-100 max-h-[85vh] overflow-y-auto"
      >
        <div className="flex items-center justify-between border-b border-slate-800 pb-3 mb-4">
          <div className="flex items-center gap-2">
            <Trophy className="w-5 h-5 text-amber-400" />
            <div>
              <h2 className="text-lg font-fantasy font-bold text-slate-100">
                Hall of Valor
              </h2>
              <p className="text-[11px] text-slate-400">
                Triumphs & legendary feats of Synmergia
              </p>
            </div>
          </div>
          <div className="flex items-center gap-3">
            <div className="flex items-center gap-1 text-xs font-bold text-amber-400 bg-slate-950 px-2.5 py-1 rounded-lg border border-amber-500/30">
              <Star className="w-3.5 h-3.5 fill-amber-400" />
              <span>{totalPoints} Pts</span>
            </div>
            <button
              onClick={onClose}
              className="text-slate-400 hover:text-slate-200 text-lg p-1"
            >
              ✕
            </button>
          </div>
        </div>

        <div className="space-y-2.5">
          {ALL_ACHIEVEMENTS.map((ach) => {
            const isUnlocked = unlockedIds.includes(ach.id);
            return (
              <div
                key={ach.id}
                className={`p-3.5 rounded-xl border flex items-center justify-between transition ${
                  isUnlocked
                    ? 'border-amber-500/50 bg-amber-950/20 shadow'
                    : 'border-slate-800/80 bg-slate-950/60 opacity-60'
                }`}
              >
                <div className="flex items-center gap-3">
                  <div
                    className={`w-9 h-9 rounded-lg flex items-center justify-center border ${
                      isUnlocked
                        ? 'border-amber-400 bg-amber-950/60 text-amber-300'
                        : 'border-slate-800 bg-slate-900 text-slate-600'
                    }`}
                  >
                    {isUnlocked ? <Trophy className="w-4 h-4" /> : <Lock className="w-4 h-4" />}
                  </div>
                  <div>
                    <h4 className="font-fantasy font-bold text-sm text-slate-100">
                      {ach.title}
                    </h4>
                    <p className="text-xs text-slate-400">{ach.description}</p>
                  </div>
                </div>

                <div className="text-right">
                  <span className="text-xs font-bold text-amber-400 block">
                    +{ach.points} Pts
                  </span>
                  <span
                    className={`text-[9px] uppercase font-bold ${
                      isUnlocked ? 'text-emerald-400' : 'text-slate-500'
                    }`}
                  >
                    {isUnlocked ? 'Accomplished' : 'Locked'}
                  </span>
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
};
